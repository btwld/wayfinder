"""Exercise a relocated Wayfinder bundle in fresh processes using generic fixtures."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent / "ci"))
from bitwild_example import get_and_validate, prepare


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
        # Indexes are plain generation files: no ObjectBox library ships.
        assert not [f for f in app.rglob("*objectbox*") if f.is_file()
                    and "licenses" not in f.relative_to(app).parts[:1]], \
            "the bundle ships an ObjectBox library"
        assert not (app / "licenses" / "objectbox").exists()
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
        start = time.perf_counter()
        example = prepare(temp / "example")
        get_and_validate([str(binary)], example, env=env, cwd=cwd, timeout=90)
        reports.append({"case": "validation", "wallMs": (time.perf_counter()-start)*1000,
                        "exitCode": 0})
        graph = json.loads(run("graph", "graph", corpus, "--output=json").stdout)
        assert graph.get("schema_version") == "1"
        mermaid = run("graph-mermaid", "graph", corpus, "--output=mermaid")
        assert mermaid.stdout.startswith("flowchart")
        run("missing-index", "search", corpus, "password", expected=2)
        first = json.loads(run("first-index", "index", corpus, "--output=json").stdout)
        assert first["embeddedChunks"] > 0
        reports[-1]["counts"] = first
        index = Path(first["index"])
        assert index.parent.parent.name == "bundles", index
        pointer = index / "current"
        generation = pointer.read_text()
        snapshot = index / generation / "snapshot.json"
        checksum = hashlib.sha256(snapshot.read_bytes()).hexdigest()
        assert sorted(p.name for p in (index / generation).iterdir()) == [
            "snapshot.json", "vectors.f32"]
        record = json.loads(snapshot.read_text())
        vectors = (index / generation / "vectors.f32").read_bytes()
        assert record["vectors"]["sha256"] == hashlib.sha256(vectors).hexdigest()
        assert vectors[:6] == b"WFVF32"
        assert len(vectors) == 16 + 4 * record["vectors"]["dimension"] * record["vectors"]["count"]
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

        # Only writers lock: while another process holds the flock(2) writer
        # lock in the index directory, a second index is busy, and search
        # serves the published generation with a refresh notice (#110).
        if os.name != "nt":
            import fcntl
            lock_file = index / "writer.lock"
            assert json.loads(lock_file.read_text()) == {"root": first["bundle"]}
            with lock_file.open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                busy = run("cross-process-lock", "index", corpus, expected=2)
                assert "busy" in busy.stderr
                served = json.loads(run("search-while-indexing", "search", corpus,
                                        "password", "--output=json").stdout)
                assert served["matches"][0]["chunk"]["sourcePath"] == "recovery.md"
                assert any(n.startswith("refresh-in-progress: ")
                           for n in served["notices"]), served["notices"]
            released = json.loads(run("lock-released", "search", corpus, "password",
                                      "--output=json").stdout)
            assert not any(n.startswith("refresh-") for n in released["notices"])

            # Killing the lock owner releases its OS lock automatically.
            holder = subprocess.Popen(
                [sys.executable, "-u", "-c",
                 "import fcntl,sys,time; f=open(sys.argv[1],'a'); "
                 "fcntl.flock(f,fcntl.LOCK_EX); print('locked',flush=True); time.sleep(60)",
                 str(lock_file)],
                stdout=subprocess.PIPE, text=True,
            )
            try:
                assert holder.stdout.readline().strip() == "locked"
                run("crash-owner-busy", "index", corpus, "--force", expected=2)
                run("crash-owner-search", "search", corpus, "password", "--output=json")
            finally:
                holder.kill()
                holder.wait(timeout=10)
            run("crash-lock-recovered", "index", corpus, "--output=json")

            # A search loop in other processes keeps working while index --force
            # publishes new generations.
            forced = subprocess.Popen([str(binary), "index", corpus, "--force"],
                                      cwd=cwd, env=env, text=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            start = time.perf_counter()
            loops = refreshes = 0
            try:
                while forced.poll() is None or loops == 0:
                    result = subprocess.run(
                        [str(binary), "search", str(corpus), "password", "--output=json"],
                        cwd=cwd, env=env, text=True, capture_output=True, timeout=90,
                    )
                    assert result.returncode == 0, (result.stdout, result.stderr)
                    found = json.loads(result.stdout)
                    assert found["matches"][0]["chunk"]["sourcePath"] == "recovery.md"
                    loops += 1
                    refreshes += any(n.startswith("refresh-in-progress: ")
                                     for n in found["notices"])
            finally:
                out, err = forced.communicate(timeout=120)
            assert forced.returncode == 0, (out, err)
            reports.append({"case": "search-loop-during-force",
                            "wallMs": (time.perf_counter()-start)*1000,
                            "searches": loops, "refreshNotices": refreshes})

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
                     for name in ("snapshot.json", "vectors.f32")}
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
        run("validation-without-model", "validate", example / "knowledge")
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
