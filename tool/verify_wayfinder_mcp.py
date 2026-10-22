"""Check a relocated Wayfinder MCP server with real embeddings and JSON-RPC stdio."""
import argparse
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time


class Session:
    def __init__(self, binary, corpus, cwd, env):
        self.process = subprocess.Popen(
            [str(binary), "mcp", *([] if corpus is None else [str(corpus)])],
            cwd=cwd, env=env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1,
        )
        self.messages = queue.Queue()
        self.diagnostics = []
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.errors = threading.Thread(target=self.drain_errors, daemon=True)
        self.reader.start()
        self.errors.start()
        self.next_id = 0

    def read(self):
        for line in self.process.stdout:
            try:
                self.messages.put(json.loads(line))
            except json.JSONDecodeError:
                self.messages.put(AssertionError(f"Non-JSON stdout: {line}"))
        self.messages.put(EOFError("Server stdout closed"))

    def drain_errors(self):
        for line in self.process.stderr:
            self.diagnostics.append(line)

    def send(self, message):
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", **message}) + "\n")
        self.process.stdin.flush()

    def request(self, method, params):
        self.next_id += 1
        self.send({"id": self.next_id, "method": method, "params": params})
        deadline = time.monotonic() + 120
        while True:
            message = self.messages.get(timeout=max(0, deadline - time.monotonic()))
            if isinstance(message, Exception):
                raise message
            assert message.get("jsonrpc") == "2.0", message
            if "id" not in message:
                continue
            assert message["id"] == self.next_id, message
            assert "error" not in message, message
            return message["result"]

    def initialize(self):
        result = self.request("initialize", {
            "protocolVersion": "2025-11-25", "capabilities": {},
            "clientInfo": {"name": "wayfinder-native-check", "version": "1.0.0"},
        })
        assert result["serverInfo"]["name"] == "wayfinder"
        self.send({"method": "notifications/initialized"})

    def tool(self, name, arguments=None, error=False):
        result = self.request("tools/call", {"name": name, "arguments": arguments or {}})
        assert bool(result.get("isError")) == error, result
        text = result["content"][0]["text"]
        return text if error or name == "search" else json.loads(text)

    def close(self):
        try:
            self.process.stdin.close()
            assert self.process.wait(timeout=120) == 0, self.diagnostics
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            self.reader.join(timeout=5)
            self.errors.join(timeout=5)
            self.process.stdout.close()
            self.process.stderr.close()
        while not self.messages.empty():
            message = self.messages.get_nowait()
            if isinstance(message, EOFError):
                continue
            if isinstance(message, Exception):
                raise message
            assert message.get("jsonrpc") == "2.0", message


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    workspace = Path(__file__).resolve().parent.parent
    reports = []
    with tempfile.TemporaryDirectory(prefix="wayfinder-mcp-") as temp:
        temp = Path(temp)
        app = temp / "relocated wayfinder"
        shutil.copytree(Path(args.bundle).resolve(), app)
        corpus = temp / "knowledge"
        shutil.copytree(workspace / "packages/wayfinder_cli/test/fixtures/knowledge", corpus)
        originals = {p.name: p.read_bytes() for p in corpus.iterdir()}
        cwd = temp / "empty"
        cwd.mkdir()
        env = dict(os.environ, WAYFINDER_DATA_DIR=str(temp / "data"))
        env.pop("KNOWLEDGE_EMBEDDING_MODEL", None)
        env.pop("WAYFINDER_EMBEDDING_MODEL", None)
        env.pop("WAYFINDER_KNOWLEDGE_DIR", None)
        binary = app / "bin" / ("wayfinder.exe" if os.name == "nt" else "wayfinder")

        def check(name, action):
            start = time.perf_counter()
            result = action()
            reports.append({"case": name, "wallMs": (time.perf_counter() - start) * 1000})
            return result

        # Startup, discovery and validation remain usable without model assets.
        model = app / "models/embedding.gguf"
        hidden = model.with_suffix(".hidden")
        model.rename(hidden)
        server = Session(binary, corpus, cwd, env)
        try:
            check("initialize-without-model", server.initialize)
            listing = check("list-tools", lambda: server.request("tools/list", {}))
            assert {t["name"] for t in listing["tools"]} == {
                "validate", "index", "search", "graph",
            }
            validate = check("validate-without-model", lambda: server.tool("validate"))
            cli = subprocess.run([str(binary), "validate", str(corpus), "--output=json"],
                                 env=env, cwd=cwd, text=True, capture_output=True, timeout=30)
            assert validate.pop("exit_code") == cli.returncode
            assert validate == json.loads(cli.stdout)
            graph = check("graph-without-model", lambda: server.tool("graph"))
            cli = subprocess.run([str(binary), "graph", str(corpus), "--output=json"],
                                 env=env, cwd=cwd, text=True, capture_output=True, timeout=30)
            assert cli.returncode == 0, cli.stderr
            assert graph == json.loads(cli.stdout)
            assert validate["gate"]["state"] in {"PASS", "FAIL", "INCOMPLETE"}
            assert isinstance(validate["diagnostics"], list)
            check("missing-index", lambda: server.tool("search", {"query": "password"}, error=True))
            check("missing-model", lambda: server.tool("index", error=True))
            hidden.rename(model)
            first = check("first-index", lambda: server.tool("index"))
            assert first["embeddedChunks"] > 0
            pointer = Path(first["index"]) / "current"
            generation = pointer.read_text()
            found = check("semantic-search", lambda: server.tool("search", {
                "query": "How can I regain access after forgetting my password?", "limit": 3,
            }))
            assert "## Matches" in found
            assert "### knowledge/recovery.md:" in found
            assert "[stable; match]" in found
            assert pointer.read_text() == generation
            unchanged = check("reuse-vectors", lambda: server.tool("index"))
            assert unchanged["embeddedChunks"] == 0
            check("reject-root-override", lambda: server.tool("index", {"bundle": str(temp)}, error=True))
            check("reject-invalid-limit", lambda: server.tool("search", {"query": "x", "limit": 0}, error=True))
            source = corpus / "recovery.md"
            source.write_text(source.read_text().replace("status: stable", "status: draft"))
            check("stale-index", lambda: server.tool("search", {"query": "password"}, error=True))
            updated = check("metadata-refresh", lambda: server.tool("index"))
            assert updated["embeddedChunks"] == 0
            found = check("search-refreshed-metadata", lambda: server.tool("search", {"query": "password"}))
            assert "### knowledge/recovery.md:" in found
            assert "[draft; match]" in found
            source.write_bytes(originals["recovery.md"])
            check("restore-index", lambda: server.tool("index"))
        finally:
            check("clean-disconnect", server.close)
        assert {p.name: p.read_bytes() for p in corpus.iterdir()} == originals
        server = Session(binary, corpus, cwd, env)
        try:
            check("restart", server.initialize)
            found = check("search-persisted-index", lambda: server.tool("search", {"query": "password"}))
            assert "### knowledge/recovery.md:" in found
        finally:
            server.close()

        # The plugin/default invocation searches configured bundles together.
        kit_path = ".wayfinder/bundles/shared-kit"
        shutil.copytree(corpus, temp / kit_path)
        (temp / ".git").mkdir()
        (temp / "wayfinder.json").write_text(json.dumps({
            "version": 1,
            "profiles": {"test-profile": {
                "source": {"git": "https://example.test/profile", "ref": "main", "path": "profile"},
                "applies_to": ["knowledge", kit_path],
            }},
        }))
        server = Session(binary, None, temp, env)
        try:
            check("project-initialize", server.initialize)
            indexed = check("project-index", lambda: server.tool("index"))
            assert {b["path"] for b in indexed["bundles"]} == {"knowledge", kit_path}
            found = check("project-search", lambda: server.tool("search", {"query": "password", "limit": 100}))
            assert "### knowledge/recovery.md:" in found
            assert f"### {kit_path}/recovery.md:" in found
            cli = subprocess.run([str(binary), "search", "password", "--limit=100"],
                                 env=env, cwd=temp, text=True, capture_output=True, timeout=120)
            assert cli.returncode == 0, cli.stderr
            assert found.strip() == cli.stdout.strip()
            validate = check("project-validate", lambda: server.tool("validate"))
            assert {b["path"] for b in validate["bundles"]} == {"knowledge", kit_path}
        finally:
            server.close()

        server = Session(binary, None, cwd, dict(env, WAYFINDER_KNOWLEDGE_DIR=str(corpus)))
        try:
            server.initialize()
            found = check("environment-single-bundle-override", lambda: server.tool("search", {"query": "password"}))
            assert "shared-kit" not in found
            assert "### knowledge/recovery.md:" in found
        finally:
            server.close()

        overridden = dict(env, WAYFINDER_EMBEDDING_MODEL=str(temp / "missing.gguf"),
                          KNOWLEDGE_EMBEDDING_MODEL=str(app / "models/embedding.gguf"))
        server = Session(binary, corpus, cwd, overridden)
        try:
            server.initialize()
            error = check("invalid-new-model-does-not-use-legacy", lambda:
                          server.tool("index", error=True))
            assert "model" in error.lower(), error
        finally:
            server.close()

        # The server needs no ObjectBox library, and the bundle ships none.
        assert not [f for f in app.rglob("*objectbox*") if f.is_file()
                    and "licenses" not in f.relative_to(app).parts[:1]]
        server = Session(binary, corpus, cwd, env)
        try:
            server.initialize()
            found = check("search-without-objectbox", lambda:
                          server.tool("search", {"query": "password"}))
            assert "### knowledge/recovery.md:" in found
            # Only writers lock: while another process holds the writer lock,
            # index is busy and search serves the published index (#110).
            if os.name != "nt":
                import fcntl
                index = Path(json.loads(subprocess.run(
                    [str(binary), "index", str(corpus), "--output=json"],
                    env=env, cwd=cwd, text=True, capture_output=True,
                    timeout=120).stdout)["index"])
                with (index / "writer.lock").open("a") as lock:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    busy = check("index-busy-while-held",
                                 lambda: server.tool("index", error=True))
                    assert "busy" in busy, busy
                    served = check("search-while-indexing", lambda:
                                   server.tool("search", {"query": "password"}))
                    assert "### knowledge/recovery.md:" in served
                    assert "Notice: refresh-in-progress: " in served, served
        finally:
            server.close()
    Path(args.output).write_text(json.dumps({"cases": reports}, indent=2) + "\n")
    print(f"Passed {len(reports)} Wayfinder MCP checks")


if __name__ == "__main__":
    main()
