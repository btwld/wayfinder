"""Exercise a relocated Wayfinder bundle in fresh processes using generic fixtures."""
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
    with tempfile.TemporaryDirectory(prefix="wayfinder-native-") as temp:
        temp = Path(temp)
        app = temp / "relocated wayfinder"
        shutil.copytree(Path(args.bundle).resolve(), app)
        binary = app / "bin" / ("wayfinder.exe" if os.name == "nt" else "wayfinder")
        corpus = temp / "knowledge"
        shutil.copytree(workspace / "packages/wayfinder_cli/test/fixtures/knowledge", corpus)
        cwd = temp / "empty"
        cwd.mkdir()
        env = dict(os.environ, WAYFINDER_DATA_DIR=str(temp / "data"))
        env.pop("KNOWLEDGE_EMBEDDING_MODEL", None)
        env.pop("WAYFINDER_EMBEDDING_MODEL", None)

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
        graph = json.loads(run("graph", "graph", corpus, "--output=json").stdout)
        assert graph.get("schema_version") == "1"
        mermaid = run("graph-mermaid", "graph", corpus, "--output=mermaid")
        assert mermaid.stdout.startswith("flowchart")
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

        # Oversized context and indented separators are recoverable, not index failures.
        oversized = corpus / "oversized.md"
        oversized.write_bytes((
            "---\ntitle: " + "word " * 700 + "\ntype: reference\n---\n"
            "  " + "-" * 700 + " end.\n"
        ).encode("utf-8"))
        oversized_bytes = oversized.read_bytes()
        recovered = json.loads(run("oversized-index", "index", corpus, "--output=json").stdout)
        assert recovered["embeddedChunks"] > 0
        warnings = recovered["warnings"]
        assert {warning["code"] for warning in warnings} == {
            "embedding_context_omitted", "oversized_segment_split",
        }, warnings
        assert all(warning["sourcePath"] == "oversized.md"
                   and warning["affectedChunks"] == 1
                   and warning["lineStart"] == warning["lineEnd"] == 5
                   for warning in warnings), warnings
        assert oversized.read_bytes() == oversized_bytes
        reports[-1]["counts"] = recovered
        current = json.loads(run("replay-warnings", "index", corpus, "--output=json").stdout)
        assert current["current"] and current["warnings"] == warnings
        text = run("text-warnings", "index", corpus)
        assert all(warning["code"] in text.stderr for warning in warnings)
        found = json.loads(run("search-after-recovery", "search", corpus,
                               "password", "--output=json").stdout)
        assert found["matches"][0]["chunk"]["sourcePath"] == "recovery.md"

        # A genuine load failure must still preserve the published generation.
        generation = pointer.read_text()
        preserved = {name: hashlib.sha256((index / generation / name).read_bytes()).hexdigest()
                     for name in ("snapshot.json", "data.mdb")}
        saved = recovery.read_bytes()
        recovery.write_text("---\ntitle: [unterminated\n---\nInvalid frontmatter.\n")
        run("failed-index", "index", corpus, expected=2)
        assert pointer.read_text() == generation
        assert all(hashlib.sha256((index / generation / name).read_bytes()).hexdigest() == digest
                   for name, digest in preserved.items())
        recovery.write_bytes(saved)
        run("failure-preserved-search", "search", corpus, "password", "--output=json")
        model = app / "models/embedding.gguf"
        model.rename(app / "models/hidden.gguf")
        current = json.loads(run("warnings-without-model", "index", corpus, "--output=json").stdout)
        assert current["current"] and current["warnings"] == warnings
        run("validation-without-model", "validate", workspace / "examples/knowledge")
        assert "Reinstall" in run("missing-model", "search", corpus, "password", expected=2).stderr
        model.write_bytes(b"corrupt")
        assert "verification" in run("corrupt-model", "search", corpus, "password", expected=2).stderr
        index_bytes = sum(f.stat().st_size for f in index.rglob("*") if f.is_file())

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({"cases": reports, "indexBytes": index_bytes}, indent=2)+"\n")
    print(f"Wayfinder: {len(reports)} native checks passed; results at {output}")


if __name__ == "__main__":
    main()
