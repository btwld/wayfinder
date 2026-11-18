#!/usr/bin/env python3
"""Judge `knowledge/` against the Profile packages of this checkout.

This script adds no rule and no verdict of its own. The decision model is data
in `.wayfinder/profile/wayfinder-profile.json`, and `wayfinder validate` is the
only thing that evaluates it. The script exists because a binding cannot name
the commit it ships in (`source.ref` takes a commit, a branch or a tag), so it
builds that binding in a temporary directory, the way
`verify-configured-example.py` does for `examples/bitwild`.

Why the lock is not committed:
`knowledge/ways-of-working/judge-the-bundle-against-its-own-checkout.md`.

Usage:
    python3 tool/ci/verify-knowledge.py          # read-only; exit is Wayfinder's
    python3 tool/ci/verify-knowledge.py --fix    # also writes generated index.md files

Exit status: 0 gate PASS, 1 gate FAIL, 2 gate INCOMPLETE or the run could not start.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from bitwild_example import cli_json, synthetic_source, with_git

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "knowledge"
CONFIG = "wayfinder.json"
PACKAGE = "wayfinder-profile.json"
WAYFINDER = ("dart", "run", "wayfinder_cli:wayfinder")

GateState = Literal["PASS", "FAIL", "INCOMPLETE"]


class GateDidNotRun(Exception):
    """The binding could not be built, or Wayfinder printed no report."""


@dataclass(frozen=True)
class Verdict:
    """What Wayfinder reported, unchanged.

    `report` is the parsed `validate --output json` object. Nothing here
    re-derives a state: `gate` is `report["gate"]["state"]`.
    """

    gate: GateState
    exit_code: int
    report: dict
    written: tuple[str, ...]
    """Bundle-relative paths `--fix` wrote in the copy (`report["fix"]["written"]`)."""


def _json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise GateDidNotRun(f"{path}: {error}") from error


def chain_paths(root: Path) -> tuple[str, ...]:
    """Repository paths of every package the binding needs, derived, never listed.

    Each `source.path` in `wayfinder.json`, then each package's `extends.path`
    until a package has none. Refuses a source or an `extends` that names
    another repository: this bundle's chain lives in this repository, and a
    remote package would need a fetch.
    Today: `.wayfinder/profile`, `profiles/bitwild`.
    """
    paths: list[str] = []
    for profile_id, entry in _json(root / CONFIG)["profiles"].items():
        source = entry["source"]
        if source["git"] != ".":
            raise GateDidNotRun(
                f"{CONFIG}: Profile {profile_id} names the source {source['git']}; "
                "this gate binds only packages of this repository."
            )
        path = source["path"]
        while path not in paths:
            paths.append(path)
            parent = _json(root / path / PACKAGE).get("extends")
            if parent is None:
                break
            if "git" in parent:
                raise GateDidNotRun(
                    f"{path}/{PACKAGE}: extends names the repository {parent['git']}; "
                    "this gate binds only packages of this repository."
                )
            path = parent["path"]
    return tuple(paths)


def bind_working_tree(work: Path) -> Path:
    """Commit the working tree's Profile packages once and bind a project copy to them.

    Reads uncommitted edits, so a rule change and the concept that satisfies
    it are judged together in one pull request. Returns the copy's root, which
    holds exactly `wayfinder.json` and `knowledge/`. The tracked
    `wayfinder.json` is never rewritten.

    Idempotent: `work` is a fresh temporary directory per run.
    """
    if not (ROOT / BUNDLE).is_dir():
        raise GateDidNotRun(f"{BUNDLE}/ does not exist.")
    source_repo, commit = synthetic_source(work, list(chain_paths(ROOT)))
    project = work / "project"
    project.mkdir()
    shutil.copytree(ROOT / BUNDLE, project / BUNDLE)
    config = _json(ROOT / CONFIG)
    for entry in config["profiles"].values():
        entry["source"]["git"] = str(source_repo)
        entry["source"]["ref"] = commit
    (project / CONFIG).write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    return project


def judge(project: Path, *, fix: bool) -> Verdict:
    """Run `get`, then `validate knowledge --output json` (with `--fix` when asked).

    `WAYFINDER_DATA_DIR` points inside the temporary directory, so no run
    reads or writes a contributor's cache.

    A `get` failure is exit 2 with its stderr printed: a package that does not
    parse, including one whose rule `tests` disagree with its check, stops here.
    """
    env = with_git(
        {**os.environ, "WAYFINDER_DATA_DIR": str(project.parent / "data")}
    )

    def run(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [*WAYFINDER, *args], cwd=ROOT, env=env, text=True, capture_output=True
        )

    got = run("get", str(project))
    if got.returncode != 0:
        raise GateDidNotRun(f"wayfinder get failed ({got.returncode})\n{got.stderr}")
    validated = run(
        "validate",
        str(project / BUNDLE),
        "--output=json",
        *(["--fix"] if fix else []),
    )
    if "{" not in validated.stdout:
        raise GateDidNotRun(
            f"wayfinder validate printed no report ({validated.returncode})\n"
            f"{validated.stderr}"
        )
    report = cli_json(validated.stdout)
    return Verdict(
        gate=report["gate"]["state"],
        exit_code=validated.returncode,
        report=report,
        written=tuple(report.get("fix", {}).get("written", ())),
    )


def copy_back(project: Path, written: tuple[str, ...]) -> None:
    """Copy each generated `index.md` that `--fix` wrote into the real `knowledge/`.

    Writes only paths named in `written`, and only files named `index.md`,
    and prints each one. Running it twice writes the same bytes.
    """
    for path in written:
        if Path(path).name == "index.md":
            shutil.copyfile(project / BUNDLE / path, ROOT / BUNDLE / path)
            print(f"wrote {BUNDLE}/{path}")


def describe(verdict: Verdict) -> list[str]:
    """Lines for a person: one per error finding and diagnostic, then the gate.

    `knowledge/<path>: <finding id>: <message>` and, when present, the
    `help_uri` on the next line. Advisories and notes are counted, not listed.
    The last line names the chain: `Gate: PASS (bitwild-profile 2026.3, current-truth 1)`.
    """
    report = verdict.report
    profile = report["profile"]
    findings = report["okf"]["report"]["findings"] + profile.get("findings", [])
    lines = []
    for finding in findings:
        if finding["severity"] != "error":
            continue
        lines.append(
            f"{BUNDLE}/{finding['location']['path']}: {finding['id']}: {finding['message']}"
        )
        if "help_uri" in finding:
            lines.append(f"  {finding['help_uri']}")
    for diagnostic in report["diagnostics"]:
        if diagnostic["level"] == "error":
            lines.append(f"{diagnostic['id']}: {diagnostic['message']}")
    advisories = sum(finding["severity"] == "advisory" for finding in findings)
    notes = len(profile.get("summary", [])) + sum(
        diagnostic["level"] == "note" for diagnostic in report["diagnostics"]
    )
    if advisories or notes:
        lines.append(f"Not listed: advisories {advisories}, notes {notes}.")
    chain = ", ".join(
        f"{package['id']} {package['release']}" for package in profile.get("chain", [])
    )
    lines.append(f"Gate: {verdict.gate} ({chain or 'no Profile resolved'})")
    return lines


def main(argv: list[str]) -> int:
    """Bind, judge, copy back when `--fix`, print, and return Wayfinder's exit code."""
    if argv not in ([], ["--fix"]):
        print(__doc__.split("Usage:\n", 1)[1], file=sys.stderr)
        return 2
    fix = bool(argv)
    try:
        with tempfile.TemporaryDirectory(prefix="wayfinder-knowledge-") as tmp:
            project = bind_working_tree(Path(tmp))
            verdict = judge(project, fix=fix)
            copy_back(project, verdict.written)
        lines = describe(verdict)
    except GateDidNotRun as error:
        print(error, file=sys.stderr)
        return 2
    except Exception:
        # Exit 1 is Wayfinder's FAIL. A missing `dart`, a failed `git commit` or
        # an unexpected report stops the gate without a verdict, so it is 2.
        traceback.print_exc()
        return 2
    print("\n".join(lines))
    return verdict.exit_code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
