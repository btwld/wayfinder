#!/usr/bin/env python3
"""Keep sibling dependency floors resolvable outside the workspace.

Workspace resolution always links a sibling's source, so a floor that admits
an older published release builds here and fails for a consumer who resolves
that release. Two rules close the gap. A dependent's floor is the sibling's
own version. A sibling with unreleased changes carries a version pub.dev does
not have yet, so that floor can only resolve to the source it was tested on.
"""

import json
import re
import sys
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def dependencies(text: str) -> dict[str, str]:
    match = re.search(r"^dependencies:\n((?:[ \t]+.*\n|\n)*)", text, re.M)
    return dict(re.findall(r"^  (\w+):[ \t]*(\S.*)$", match[1], re.M)) if match else {}


def unreleased(changelog: Path) -> bool:
    match = re.match(r"# Unreleased\n(.*?)(?:^# |\Z)", changelog.read_text(), re.M | re.S)
    return bool(match and match[1].strip())


def published(name: str) -> set[str]:
    with urllib.request.urlopen(f"https://pub.dev/api/packages/{name}") as response:
        return {entry["version"] for entry in json.load(response)["versions"]}


def main() -> int:
    members = re.findall(r"^  - (\S+)$", (ROOT / "pubspec.yaml").read_text(), re.M)
    packages = {}
    for member in members:
        text = (ROOT / member / "pubspec.yaml").read_text()
        name = re.search(r"^name: (\S+)$", text, re.M)[1]
        version = re.search(r"^version: (\S+)$", text, re.M)[1]
        packages[name] = (member, version, dependencies(text))
    failures = []
    depended = set()
    for member, _, needs in packages.values():
        for name, constraint in needs.items():
            if name not in packages:
                continue
            depended.add(name)
            if constraint != f"^{packages[name][1]}":
                failures.append(f"{member}: {name} {constraint}; expected ^{packages[name][1]}")
    for name in sorted(depended):
        member, version, _ = packages[name]
        if unreleased(ROOT / member / "CHANGELOG.md") and version in published(name):
            failures.append(
                f"{member}: unreleased changes on {version}, which pub.dev already has; "
                "raise the version"
            )
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
