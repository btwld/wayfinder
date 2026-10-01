#!/usr/bin/env python3
"""Exercise the direct-source example against a local synthetic Profile Git repo."""

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "examples/configured-2026.3"


def run(*args: str, cwd: Path = ROOT) -> str:
    result = subprocess.run(
        args, cwd=cwd, text=True, capture_output=True
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"{' '.join(args)} failed ({result.returncode})\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result.stdout.strip()


def cli_json(output: str) -> dict:
    # `dart run` may announce build hooks on stdout before the CLI's JSON.
    start = output.find("{")
    assert start >= 0, output
    return json.loads(output[start:])


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="wayfinder-configured-example-") as tmp:
        work = Path(tmp)
        os.environ["WAYFINDER_DATA_DIR"] = str(work / "data")
        source = work / "source"
        (source / "profile").mkdir(parents=True)
        shutil.copy2(
            ROOT / "profile/wayfinder-profile.json",
            source / "profile/wayfinder-profile.json",
        )
        run("git", "init", "-q", cwd=source)
        run("git", "config", "user.name", "Wayfinder Example", cwd=source)
        run("git", "config", "user.email", "example@example.test", cwd=source)
        run("git", "add", "profile/wayfinder-profile.json", cwd=source)
        run("git", "commit", "-q", "-m", "Synthetic Profile", cwd=source)

        project = work / "project"
        shutil.copytree(EXAMPLE, project)
        config_path = project / "wayfinder.json"
        config = json.loads(config_path.read_text())
        selected = config["profiles"]["bitwild_profile"]["source"]
        selected["git"] = str(source)
        selected["ref"] = run("git", "rev-parse", "HEAD", cwd=source)
        config_path.write_text(json.dumps(config, indent=2) + "\n")

        run("dart", "run", "wayfinder_cli:wayfinder", "get", str(project))
        output = run(
            "dart",
            "run",
            "wayfinder_cli:wayfinder",
            "validate",
            str(project / "knowledge"),
            "--output=json",
        )
        result = cli_json(output)
        assert result["okf"]["state"] == "PASS", result
        assert result["profile"]["state"] == "PASS", result
        assert result["profile"]["release"] == "2026.3", result

        # The committed example is already what --fix would write.
        fixed = cli_json(
            run(
                "dart",
                "run",
                "wayfinder_cli:wayfinder",
                "validate",
                str(project / "knowledge"),
                "--fix",
                "--output=json",
            )
        )
        assert fixed["fix"] == {"state": "APPLIED", "written": []}, fixed
        assert fixed["profile"]["state"] == "PASS", fixed
        for original in (EXAMPLE / "knowledge").rglob("*"):
            if original.is_file():
                copy = project / original.relative_to(EXAMPLE)
                assert copy.read_bytes() == original.read_bytes(), copy

        # A generic graph still reads the bundle without its Profile lock.
        (project / "wayfinder.lock").unlink()
        missing_lock = subprocess.run(
            [
                "dart",
                "run",
                "wayfinder_cli:wayfinder",
                "validate",
                str(project / "knowledge"),
                "--output=json",
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        assert missing_lock.returncode == 2, missing_lock.stderr
        unresolved = cli_json(missing_lock.stdout)
        assert unresolved["okf"]["state"] == "PASS", unresolved
        assert unresolved["profile"]["state"] == "UNSUPPORTED", unresolved
        assert not (project / "wayfinder.lock").exists()
        graph = run(
            "dart",
            "run",
            "wayfinder_cli:wayfinder",
            "graph",
            str(project / "knowledge"),
            "--output=json",
        )
        assert cli_json(graph)["schema_version"] == "1", graph
    print("Configured 2026.3 example: Profile, --fix, read-only OKF, and graph pass")


if __name__ == "__main__":
    main()
