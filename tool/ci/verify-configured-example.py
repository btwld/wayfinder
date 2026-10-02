#!/usr/bin/env python3
"""Exercise the Bitwild example project against a local synthetic Profile Git repo."""

import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

from bitwild_example import (BITWILD, EXAMPLE, ROOT, bind_project,
                             check_skill, cli_json, get_and_validate,
                             synthetic_source)

WAYFINDER = ["dart", "run", "wayfinder_cli:wayfinder"]


def run(*args: str) -> str:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"{' '.join(args)} failed ({result.returncode})\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result.stdout.strip()


def table(markdown: Path, heading: str) -> dict:
    """The `name | description` rows of the table under [heading]."""
    section = markdown.read_text().split(f"\n## {heading}\n", 1)[1]
    section = section.split("\n## ", 1)[0]
    return dict(re.findall(r"^\| `([^`]+)` \| (.+?) \|$", section, re.M))


def check_skill_vocabulary() -> None:
    """The skill shows readers the package's vocabulary, so the two must agree."""
    package = json.loads((ROOT / BITWILD / "wayfinder-profile.json").read_text())
    references = ROOT / BITWILD / "skill/references"
    for key, markdown, heading in [
            ("types", "types.md", "Standard types"),
            ("relationships", "relationships.md", "Standard names")]:
        declared = {d["name"]: d["description"] for d in package[key]}
        shown = table(references / markdown, heading)
        assert shown == declared, (markdown, shown, declared)


def main() -> None:
    check_skill_vocabulary()
    with tempfile.TemporaryDirectory(prefix="wayfinder-configured-example-") as tmp:
        work = Path(tmp)
        os.environ["WAYFINDER_DATA_DIR"] = str(work / "data")
        source, commit = synthetic_source(work, [BITWILD])
        project = bind_project(EXAMPLE, work, source, commit)
        get_and_validate(WAYFINDER, project, cwd=ROOT)
        check_skill(project, source, commit, BITWILD, "bitwild-profile", "2026.3")

        # The committed example is already what --fix would write.
        fixed = cli_json(
            run(
                *WAYFINDER,
                "validate",
                str(project / "knowledge"),
                "--fix",
                "--output=json",
            )
        )
        assert fixed["fix"] == {"written": []}, fixed
        assert fixed["gate"] == {"state": "PASS"}, fixed
        assert fixed["profile"]["state"] == "PASS", fixed
        for original in (EXAMPLE / "knowledge").rglob("*"):
            if original.is_file():
                copy = project / original.relative_to(EXAMPLE)
                assert copy.read_bytes() == original.read_bytes(), copy

        # A generic graph still reads the bundle without its Profile lock.
        (project / "wayfinder.lock").unlink()
        missing_lock = subprocess.run(
            [
                *WAYFINDER,
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
        assert unresolved["profile"]["state"] == "NOT ASSESSED", unresolved
        assert [d["id"] for d in unresolved["diagnostics"]] == [
            "wayfinder/profile-unresolved"
        ], unresolved
        assert unresolved["gate"] == {"state": "INCOMPLETE"}, unresolved
        assert not (project / "wayfinder.lock").exists()
        graph = run(
            *WAYFINDER,
            "graph",
            str(project / "knowledge"),
            "--output=json",
        )
        assert cli_json(graph)["schema_version"] == "1", graph
    print("Bitwild example: Profile, skill, --fix, read-only OKF, and graph pass")


if __name__ == "__main__":
    main()
