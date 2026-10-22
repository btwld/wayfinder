#!/usr/bin/env python3
"""Keep the analyzer and the Dart chunker out of wayfinder_embeddings.

wayfinder_embeddings does not depend on `analyzer`, so an application can pick
its own analyzer version; Dart chunking lives in wayfinder_dart_chunker, which
depends on wayfinder_embeddings. Two rules keep it that way:

- nothing wayfinder_embeddings depends on reaches `analyzer` or
  `_fe_analyzer_shared`;
- nothing it depends on, its dev dependencies included, reaches
  `wayfinder_dart_chunker`, which would be a cycle.

Its dev dependencies still reach `analyzer` through build_runner and
objectbox_generator; that is expected and allowed.

`dart pub deps` lists every workspace member, so a grep over its output also
matches the chunker's own `analyzer`. This walks the dependency graph from
wayfinder_embeddings instead. Run `dart pub get` first.
"""

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PACKAGE = "wayfinder_embeddings"
NO_RUNTIME = ("analyzer", "_fe_analyzer_shared")
NO_EDGE = "wayfinder_dart_chunker"


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
    development = closure(graph, package["devDependencies"])

    failures = [
        f"{PACKAGE} reaches {name} through its dependencies"
        for name in NO_RUNTIME
        if name in runtime
    ]
    if NO_EDGE in runtime | development:
        failures.append(
            f"{PACKAGE} reaches {NO_EDGE}, which depends on it; move the code "
            f"that needs the Dart chunker into {NO_EDGE}"
        )
    for failure in failures:
        print(failure, file=sys.stderr)
    if failures:
        return 1
    print(
        f"{PACKAGE}: {len(runtime)} runtime packages without "
        f"{' or '.join(NO_RUNTIME)}; {len(development)} dev packages, none of "
        f"them {NO_EDGE}."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
