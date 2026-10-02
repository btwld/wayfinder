#!/usr/bin/env python3
"""Exercise Profiles other than Bitwild against a local synthetic Profile Git repo.

`examples/acme-notes` uses `examples/profiles/two-rule`, a Profile with no
parent: its lock holds that package alone, and `get` installs the package's
skill from the locked commit. `examples/bitwild`, rebound to
`examples/profiles/two-rule-child`, uses a package that extends Bitwild by
same revision: the project names only the child, and the lock pins both
packages at one commit.
"""

import json
import os
import subprocess
import tempfile
from pathlib import Path

from bitwild_example import (BITWILD, EXAMPLE, ROOT, bind_project,
                             check_skill, cli_json, get_and_validate,
                             skill_dirs, synthetic_source)

WAYFINDER = ["dart", "run", "wayfinder_cli:wayfinder"]
INDEPENDENT = ROOT / "examples/acme-notes"
PACKAGE = "examples/profiles/two-rule"
SKILL_DIRS = skill_dirs("acme-notes")
CHILD_PATH = "examples/profiles/two-rule-child"


def wayfinder(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([*WAYFINDER, *args], cwd=ROOT, text=True,
                          capture_output=True)


def validate(project: Path) -> tuple:
    result = wayfinder("validate", str(project / "knowledge"), "--output=json")
    return result.returncode, cli_json(result.stdout)


def lock(project: Path) -> dict:
    return json.loads((project / "wayfinder.lock").read_text())


def written(project: Path) -> dict:
    """Every path `get` writes, with its modification time."""
    paths = [project / "wayfinder.lock"]
    for directory in SKILL_DIRS:
        paths += [project / directory, *(project / directory).rglob("*")]
    return {str(path): path.stat().st_mtime_ns for path in paths}


def check_independent(work: Path, source: Path, commit: str) -> None:
    project = bind_project(INDEPENDENT, work, source, commit, "independent")
    result = get_and_validate(WAYFINDER, project, cwd=ROOT, release="1.0")
    assert result["profile"]["id"] == "acme-notes", result
    assert result["profile"]["chain"] == [
        {"id": "acme-notes", "release": "1.0", "commit": commit}], result
    assert result["diagnostics"] == [], result
    assert list(lock(project)["packages"]) == ["acme-notes"], lock(project)
    check_skill(project, source, commit, PACKAGE, "acme-notes", "1.0")

    before = written(project)
    again = wayfinder("get", str(project), "--output=json")
    assert again.returncode == 0, again.stderr
    assert cli_json(again.stdout)["skills"] == [
        {"id": "acme-notes", "directories": SKILL_DIRS, "written": False}], again.stdout
    assert written(project) == before, "get is idempotent"

    marker = project / SKILL_DIRS[0] / ".wayfinder-profile"
    marker.write_text(marker.read_text().replace(commit, "0" * 40))
    code, stale = validate(project)
    assert code == 0 and stale["gate"] == {"state": "PASS"}, stale
    assert stale["diagnostics"] == [{
        "id": "wayfinder/profile-skill-stale", "level": "warning",
        "message": f"Profile acme-notes skill in {SKILL_DIRS[0]} is not the "
                   f"locked commit {commit}. Run wayfinder get.",
        "location": {"path": "wayfinder.json"}}], stale
    assert wayfinder("get", str(project)).returncode == 0
    check_skill(project, source, commit, PACKAGE, "acme-notes", "1.0")
    assert validate(project)[1]["diagnostics"] == []

    runbook = project / "knowledge/operations/restart-the-api.md"
    runbook.write_text(runbook.read_text().replace("type: Runbook", "type: Memo"))
    code, failed = validate(project)
    assert code == 1, failed
    # The generated index groups by type, so it goes stale with the type.
    assert [f["id"] for f in failed["profile"]["findings"]] == [
        "acme-notes/index-current", "acme-notes/known-type"], failed


def check_child(work: Path, source: Path, commit: str) -> None:
    project = bind_project(EXAMPLE, work, source, commit, "child")
    config_path = project / "wayfinder.json"
    config = json.loads(config_path.read_text())
    entry = config["profiles"].pop("bitwild-profile")
    entry["source"]["path"] = CHILD_PATH
    config["profiles"]["acme-bitwild"] = entry
    config_path.write_text(json.dumps(config, indent=2) + "\n")

    result = get_and_validate(WAYFINDER, project, cwd=ROOT, release="1.0")
    assert result["profile"]["chain"] == [
        {"id": "bitwild-profile", "release": "2026.3", "commit": commit},
        {"id": "acme-bitwild", "release": "1.0", "commit": commit},
    ], result
    assert lock(project)["packages"] == {
        "acme-bitwild": {
            "source": str(source), "requested_ref": commit,
            "resolved_commit": commit, "path": CHILD_PATH, "release": "1.0",
            "extends": "bitwild-profile",
        },
        "bitwild-profile": {
            "source": str(source), "requested_ref": commit,
            "resolved_commit": commit, "path": "profiles/bitwild",
            "release": "2026.3",
        },
    }, lock(project)

    # Validation reads only the lock and the local cache.
    source.rename(work / "source-gone")
    request = project / "knowledge/reporting/include-pdf-annotations.md"
    request.write_text(request.read_text().replace("tags: [reporting, export]\n", ""))
    code, failed = validate(project)
    assert code == 1, failed
    assert [f["id"] for f in failed["profile"]["findings"]] == [
        "acme-bitwild/request-tagged"], failed


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="wayfinder-independent-profile-") as tmp:
        work = Path(tmp)
        os.environ["WAYFINDER_DATA_DIR"] = str(work / "data")
        source, commit = synthetic_source(
            work, [BITWILD, "examples/profiles"])
        check_independent(work, source, commit)
        check_child(work, source, commit)
    print("Independent Profile and same-revision child: get, validate, lock, skill pass")


if __name__ == "__main__":
    main()
