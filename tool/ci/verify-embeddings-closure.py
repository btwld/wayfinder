#!/usr/bin/env python3
"""Keep the analyzer out of wayfinder_embeddings' runtime dependencies.

wayfinder_embeddings does not depend on `analyzer`, so an application can pick
its own analyzer version. Nothing it depends on at runtime may reach `analyzer`
or `_fe_analyzer_shared`.

Its dev dependencies still reach `analyzer` through build_runner and
objectbox_generator; that is expected and allowed.

`dart pub deps` lists every workspace member and dev dependency. This walks the
runtime dependency graph from wayfinder_embeddings instead. Run `dart pub get`
first.
"""

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PACKAGE = "wayfinder_embeddings"
NO_RUNTIME = ("analyzer", "_fe_analyzer_shared")


def closure(graph: dict[str, dict], start: list[str]) -> set[str]:
    """Every package [start] reaches through runtime dependencies."""
    seen: set[str] = set()
    pending = list(start)
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        # A workspace member's `dependencies` also lists its dev dependencies;
        # `directDependencies` holds only what its users get.
        pending.extend(graph[name].get("directDependencies", []))
    return seen


def main() -> int:
    output = subprocess.run(
        ["dart", "pub", "deps", "--json"],
        cwd=ROOT / "packages" / PACKAGE,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    graph = {entry["name"]: entry for entry in json.loads(output)["packages"]}
    package = graph[PACKAGE]
    runtime = closure(graph, package["directDependencies"])

    failures = [
        f"{PACKAGE} reaches {name} through its dependencies"
        for name in NO_RUNTIME
        if name in runtime
    ]
    for failure in failures:
        print(failure, file=sys.stderr)
    if failures:
        return 1
    print(
        f"{PACKAGE}: {len(runtime)} runtime packages without "
        f"{' or '.join(NO_RUNTIME)}."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
