"""Exercise a relocated Station bundle in fresh processes using generic fixtures."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    workspace = Path(__file__).resolve().parent.parent
    reports = []
    with tempfile.TemporaryDirectory(prefix="station-native-") as temp:
        temp = Path(temp)
        app = temp / "relocated station"
        shutil.copytree(Path(args.bundle).resolve(), app)
        binary = app / "bin" / "station"
        corpus = temp / "knowledge"
        shutil.copytree(workspace / "packages/station/test/fixtures/knowledge", corpus)
        cwd = temp / "empty"
        cwd.mkdir()
        env = dict(os.environ, STATION_DATA_DIR=str(temp / "data"))
        env.pop("KNOWLEDGE_EMBEDDING_MODEL", None)

        def run(name, *command, expected=0):
            start = time.perf_counter()
            result = subprocess.run(
                [str(binary), *map(str, command)], cwd=cwd, env=env,
                text=True, capture_output=True, timeout=90,
            )
            assert result.returncode == expected, (name, result.stdout, result.stderr)
            reports.append({"case": name, "wallMs": (time.perf_counter()-start)*1000,
                            "exitCode": result.returncode})
            return result

        run("help", "--help")
        run("validation", "validate", workspace / "examples/knowledge", "--output=json")
        run("missing-index", "search", corpus, "password", expected=2)
        first = json.loads(run("first-index", "index", corpus, "--output=json").stdout)
        assert first["embeddedChunks"] > 0
        reports[-1]["counts"] = first
        index = Path(first["index"])
        pointer = index / "current"
        generation = pointer.read_text()
        snapshot = index / generation / "snapshot.json"
        checksum = hashlib.sha256(snapshot.read_bytes()).hexdigest()
        result = json.loads(run("fresh-search", "search", corpus,
                                "How do I regain access after forgetting my password?",
                                "--output=json").stdout)
        assert result["matches"][0]["chunk"]["sourcePath"] == "recovery.md"
        assert result["matches"][0]["chunk"]["lineStart"] > 5
        assert pointer.read_text() == generation
        assert hashlib.sha256(snapshot.read_bytes()).hexdigest() == checksum
        repeated = json.loads(run("unchanged-index", "index", corpus, "--output=json").stdout)
        assert repeated["embeddedChunks"] == 0
        reports[-1]["counts"] = repeated

        recovery = corpus / "recovery.md"
        original = recovery.read_text()
        recovery.write_text(original.replace("status: stable", "status: draft"))
        run("stale-search", "search", corpus, "password", expected=2)
        updated = json.loads(run("metadata-index", "index", corpus, "--output=json").stdout)
        assert updated["embeddedChunks"] == 0
        reports[-1]["counts"] = updated
        recovery.write_text(recovery.read_text() + "\nUse a backup code when email is unavailable.\n")
        updated = json.loads(run("body-index", "index", corpus, "--output=json").stdout)
        assert updated["embeddedChunks"] == 1
        reports[-1]["counts"] = updated
        (corpus / "weather.md").unlink()
        updated = json.loads(run("delete-index", "index", corpus, "--output=json").stdout)
        assert updated["removedChunks"] == 1 and updated["embeddedChunks"] == 0

        # A second process cannot open the same index until the OS lock is released.
        if os.name != "nt":
            import fcntl
            with (index / "command.lock").open("a") as lock:
                fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                busy = run("cross-process-lock", "index", corpus, expected=2)
                assert "busy" in busy.stderr
            run("lock-released", "search", corpus, "password", "--output=json")

            # Killing the lock owner releases its OS lock automatically.
            holder = subprocess.Popen(
                ["python3", "-u", "-c",
                 "import fcntl,sys,time; f=open(sys.argv[1],'a'); "
                 "fcntl.lockf(f,fcntl.LOCK_EX); print('locked',flush=True); time.sleep(60)",
                 str(index / "command.lock")],
                stdout=subprocess.PIPE, text=True,
            )
            try:
                assert holder.stdout.readline().strip() == "locked"
                run("crash-owner-busy", "search", corpus, "password", expected=2)
            finally:
                holder.kill()
                holder.wait(timeout=10)
            run("crash-lock-recovered", "search", corpus, "password", "--output=json")

        generation = pointer.read_text()
        saved = recovery.read_text()
        recovery.write_text(saved.replace("Account recovery", "word " * 700))
        run("failed-index", "index", corpus, expected=2)
        assert pointer.read_text() == generation
        recovery.write_text(saved)
        run("failure-preserved-search", "search", corpus, "password", "--output=json")
        model = app / "models/embedding.gguf"
        model.rename(app / "models/hidden.gguf")
        run("validation-without-model", "validate", workspace / "examples/knowledge")
        assert "Reinstall" in run("missing-model", "search", corpus, "password", expected=2).stderr
        model.write_bytes(b"corrupt")
        assert "verification" in run("corrupt-model", "search", corpus, "password", expected=2).stderr
        index_bytes = sum(f.stat().st_size for f in index.rglob("*") if f.is_file())

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({"cases": reports, "indexBytes": index_bytes}, indent=2)+"\n")
    print(f"Station: {len(reports)} native checks passed; results at {output}")


if __name__ == "__main__":
    main()
