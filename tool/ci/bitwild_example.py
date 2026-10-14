"""Example projects, resolved against a local synthetic Profile Git source.

Validation never fetches, so a check of the shipped engine against an example
first needs `wayfinder get` to succeed offline. This builds a one-commit Git
repository from this checkout's Profile packages, copies an example project
beside it, and points the copy's `source.git` at that repository.
"""

import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "examples/bitwild"
BITWILD = "profiles/bitwild"
SKILL_ROOTS = [".claude/skills", ".agents/skills"]
MARKER = ".wayfinder-profile"


def _git(*args: str, cwd: Path) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=Wayfinder Example",
         "-c", "user.email=example@example.test", *args],
        cwd=cwd, check=True, text=True, capture_output=True,
    ).stdout.strip()


def synthetic_source(work: Path, paths: list) -> tuple[Path, str]:
    source = work / "source"
    for relative in paths:
        origin, copy = ROOT / relative, source / relative
        if origin.is_dir():
            shutil.copytree(origin, copy)
        else:
            copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(origin, copy)
    _git("init", "-q", cwd=source)
    _git("add", ".", cwd=source)
    _git("commit", "-q", "-m", "Synthetic Profile", cwd=source)
    return source, _git("rev-parse", "HEAD", cwd=source)


def bind_project(example: Path, work: Path, source: Path, commit: str,
                 name: str = "project") -> Path:
    project = work / name
    shutil.copytree(example, project)
    config_path = project / "wayfinder.json"
    config = json.loads(config_path.read_text())
    for entry in config["profiles"].values():
        entry["source"]["git"] = str(source)
        entry["source"]["ref"] = commit
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    return project


def prepare(work: Path) -> Path:
    source, commit = synthetic_source(work, [BITWILD])
    return bind_project(EXAMPLE, work, source, commit)


def skill_dirs(profile_id: str) -> list:
    return [f"{root}/{profile_id}" for root in SKILL_ROOTS]


def check_skill(project: Path, source: Path, commit: str, package: str,
                profile_id: str, release: str) -> None:
    tree = f"{commit}:{package}/skill"
    names = _git("ls-tree", "-r", "-z", "--name-only", tree,
                 cwd=source).strip("\0").split("\0")
    assert "SKILL.md" in names, names
    expected = {name: subprocess.run(
        ["git", "show", f"{tree}/{name}"], cwd=source, check=True,
        capture_output=True).stdout for name in names}
    assert expected["SKILL.md"].startswith(
        f"---\nname: {profile_id}\n".encode()), expected["SKILL.md"][:80]
    marker = {"id": profile_id, "release": release, "commit": commit}
    for directory in skill_dirs(profile_id):
        root = project / directory
        files = {path.relative_to(root).as_posix(): path.read_bytes()
                 for path in root.rglob("*") if path.is_file()}
        assert json.loads(files.pop(MARKER)) == marker, directory
        assert files == expected, (directory, sorted(files), sorted(expected))


def cli_json(output: str) -> dict:
    # `dart run` may announce build hooks on stdout before the CLI's JSON.
    start = output.find("{")
    assert start >= 0, output
    return json.loads(output[start:])


def with_git(env: dict) -> dict:
    if shutil.which("git", path=env.get("PATH")):
        return env
    git = shutil.which("git")
    assert git, "the example check needs git"
    return {**env, "PATH": os.pathsep.join([str(Path(git).parent), env.get("PATH", "")])}


def get_and_validate(wayfinder: list, project: Path, env: dict = None,
                     cwd: Path = None, timeout: int = 180,
                     release: str = "2026.3") -> dict:
    env = with_git(dict(os.environ if env is None else env))

    def run(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run([*wayfinder, *args], env=env, cwd=cwd, text=True,
                              capture_output=True, timeout=timeout)

    got = run("get", str(project))
    assert got.returncode == 0, (got.stdout, got.stderr)
    validated = run("validate", str(project / "knowledge"), "--output=json")
    assert validated.returncode == 0, (validated.stdout, validated.stderr)
    result = cli_json(validated.stdout)
    assert result["okf"]["state"] == "PASS", result
    assert result["profile"]["state"] == "PASS", result
    assert result["profile"]["release"] == release, result
    assert result["gate"] == {"state": "PASS"}, result
    return result
