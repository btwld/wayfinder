"""The Bitwild example project, resolved against a local synthetic Profile Git source.

Validation never fetches, so a check of the shipped engine against the example
first needs `wayfinder get` to succeed offline. This builds a one-commit Git
repository from this checkout's `profile/` manifest, copies `examples/bitwild`
beside it, and points the copy's `source.git` at that repository.
"""

import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "examples/bitwild"


def _git(*args: str, cwd: Path) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=Wayfinder Example",
         "-c", "user.email=example@example.test", *args],
        cwd=cwd, check=True, text=True, capture_output=True,
    ).stdout.strip()


def prepare(work: Path) -> Path:
    """Returns the copied project under [work], its source a local repository."""
    source = work / "source"
    (source / "profile").mkdir(parents=True)
    shutil.copy2(ROOT / "profile/wayfinder-profile.json",
                 source / "profile/wayfinder-profile.json")
    _git("init", "-q", cwd=source)
    _git("add", "profile/wayfinder-profile.json", cwd=source)
    _git("commit", "-q", "-m", "Synthetic Profile", cwd=source)

    project = work / "project"
    shutil.copytree(EXAMPLE, project)
    config_path = project / "wayfinder.json"
    config = json.loads(config_path.read_text())
    selected = config["profiles"]["bitwild_profile"]["source"]
    selected["git"] = str(source)
    selected["ref"] = _git("rev-parse", "HEAD", cwd=source)
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    return project


def cli_json(output: str) -> dict:
    # `dart run` may announce build hooks on stdout before the CLI's JSON.
    start = output.find("{")
    assert start >= 0, output
    return json.loads(output[start:])


def with_git(env: dict) -> dict:
    """[env] with the caller's git on PATH, for `get` under a narrowed PATH."""
    if shutil.which("git", path=env.get("PATH")):
        return env
    git = shutil.which("git")
    assert git, "the example check needs git"
    return {**env, "PATH": os.pathsep.join([str(Path(git).parent), env.get("PATH", "")])}


def get_and_validate(wayfinder: list, project: Path, env: dict = None,
                     cwd: Path = None, timeout: int = 180) -> dict:
    """Runs `get` and `validate` for [project] and returns the passing result."""
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
    assert result["profile"]["release"] == "2026.3", result
    assert result["gate"] == {"state": "PASS"}, result
    return result
