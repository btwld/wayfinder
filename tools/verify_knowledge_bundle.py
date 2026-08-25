#!/usr/bin/env python3
"""Verify the knowledge/ bundle against OKF 0.2 and the Concepta OKF Profile 2026.1.

Two severities, kept distinct as profile §14.1 requires:

  ERROR    an OKF §11 violation. The document cannot be interpreted, so it
           cannot be accepted. Exits nonzero.
  ADVISORY a profile deviation. Reported and attributed, but never a reason to
           reject a bundle that is valid OKF. Exits nonzero only with --strict.

Usage:
    python3 tools/verify_knowledge_bundle.py [--strict] [<repo-root>]

The bundle is located by walking up from <repo-root> (default: the working
directory) for a directory containing knowledge/index.md, so the tool runs
against any repository rather than only the one it ships in.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def find_root(start: Path) -> Path:
    for candidate in [start, *start.parents]:
        if (candidate / "knowledge" / "index.md").is_file():
            return candidate
    sys.exit(f"no knowledge/index.md found at or above {start}")


_args = [a for a in sys.argv[1:] if not a.startswith("-")]
ROOT = find_root(Path(_args[0] if _args else ".").resolve())
BUNDLE = ROOT / "knowledge"
RESERVED = {"index.md", "log.md"}
ROOT_CONCEPTS = {"profile.md", "types.md"}
# Kind is carried by `type`, never by a directory (§3). `interactions/` is the
# one type-named directory the profile allows, on the time axis.
TYPE_NAMED = {
    "glossary", "rules", "questions", "decisions", "analyses", "analysis",
    "specifications", "specs", "guides", "adr", "adrs", "requests",
}
CORE_LABELS = {
    "Superseded by", "Depends on", "Constrained by", "Part of", "Refines",
    "Specified by", "Implemented by", "Resolves", "Partially resolves",
    "Tracked by", "Related to",
}
ACTOR = re.compile(r"^(?:human:[a-z0-9][a-z0-9-]*|process:[a-z0-9][a-z0-9-]*|[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9.-]*)$")

errors: list[str] = []
advisories: list[str] = []


def error(where: Path | str, msg: str) -> None:
    errors.append(f"{_rel(where)}: {msg}")


def advise(where: Path | str, msg: str) -> None:
    advisories.append(f"{_rel(where)}: {msg}")


def _rel(where: Path | str) -> str:
    return str(Path(where).relative_to(ROOT)) if isinstance(where, Path) else str(where)


def split_frontmatter(text: str) -> tuple[str | None, str]:
    """Return (frontmatter_block, body). Block is None when absent."""
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---", 4)
    if end == -1:
        return None, text
    return text[4:end], text[end + 4:]


def parse_scalars(block: str) -> dict[str, str]:
    """Top-level `key: value` pairs. Nested structures are returned raw."""
    out: dict[str, str] = {}
    for line in block.splitlines():
        if not line or line.startswith((" ", "\t", "#", "-")):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        out[key.strip()] = value.strip()
    return out


def concept_files() -> list[Path]:
    return sorted(
        p for p in BUNDLE.rglob("*.md")
        if p.name not in RESERVED and p.is_file()
    )


# --- OKF conformance (§11) --------------------------------------------------

def check_okf(path: Path, block: str | None, fields: dict[str, str]) -> None:
    if block is None:
        error(path, "OKF §11: missing or unparseable YAML frontmatter")
        return
    if not fields.get("type"):
        error(path, "OKF §11: frontmatter carries no non-empty `type`")


# --- Profile conformance (§3–§13) ------------------------------------------

def check_baseline(path: Path, fields: dict[str, str]) -> None:
    for key in ("title", "description", "status", "generated"):
        if not fields.get(key):
            advise(path, f"baseline metadata: missing `{key}`")
    status = fields.get("status")
    if status and status not in {"draft", "stable", "deprecated"}:
        advise(path, f"`status: {status}` is not draft|stable|deprecated")
    generated = fields.get("generated", "")
    if generated:
        m = re.search(r"by:\s*([^,}\s]+)", generated)
        if not m:
            advise(path, "`generated` has no `by:` actor")
        elif not ACTOR.match(m.group(1)):
            advise(path, f"`generated.by: {m.group(1)}` is not an OKF §7 actor")


def trust_tier(block: str) -> str:
    """Derive the OKF §5.3 tier. Never a finding — absence carries meaning.

    Profile §14.1 forbids reporting a missing `verified` event: the only way an
    author can clear such a report is to record a verification that never
    happened, which corrupts the trust model the field exists to protect.
    Summarizing tiers is permitted; it must not affect exit status.
    """
    m = re.search(r"^verified:(.*?)(?=^\S|\Z)", block, re.M | re.S)
    if not m:
        return "unverified"
    return "human-reviewed" if "human:" in m.group(1) else "machine-confirmed"


def _concept_title(path: Path) -> str:
    block, _ = split_frontmatter(path.read_text(encoding="utf-8"))
    return parse_scalars(block or "").get("title", "")


def check_areas() -> None:
    """Areas name subjects and are indexed (§3.1).

    Mixed types inside an area are the point of it, so there is no type check
    here. Placement is reviewed by a person, not inferred from a numeric minimum.
    """
    references = BUNDLE / "references"
    if references.is_dir():
        # references/ may nest (§3.4); every nonempty level needs an index (§9).
        for level in [references, *(p for p in references.rglob("*") if p.is_dir())]:
            if any(level.iterdir()) and not (level / "index.md").exists():
                advise(level, "nonempty references/ directory has no index.md")

    for d in sorted(p for p in BUNDLE.rglob("*") if p.is_dir()):
        if d == references or references in d.parents:
            continue
        concepts = [p for p in d.glob("*.md") if p.name not in RESERVED]
        subareas = [p for p in d.iterdir() if p.is_dir()]
        if not concepts and not subareas:
            advise(d, "empty area should not exist (profile §3.1)")
            continue
        if not (d / "index.md").exists():
            advise(d, "nonempty area has no index.md")
        if d.name in TYPE_NAMED:
            advise(d, f"`{d.name}/` names a document kind, not a subject (profile §3)")
        # An area named after one of its members is named after a part of the
        # set rather than what the set shares (§3.1 rule 1).
        for c in concepts:
            slug = re.sub(r"[^a-z0-9]+", "-", _concept_title(c).lower()).strip("-")
            if slug and slug == d.name:
                advise(d, f"area name matches member concept `{c.name}` — likely too narrow")
        if (d.parent / f"{d.name}.md").exists():
            advise(d, "a concept sits beside this area rather than inside it (§3.1 rule 1)")


def check_registries() -> None:
    """types.md and actors.md are producer-side declarations, never gates (§14.2)."""
    types_md = BUNDLE / "types.md"
    actors_md = BUNDLE / "actors.md"
    if not types_md.exists():
        advise(BUNDLE, "profile §5.2: bundle has no type registry at types.md")
        declared_types: set[str] = set()
    else:
        declared_types = set(re.findall(r"^\|\s*`([^`]+)`\s*\|", types_md.read_text(encoding="utf-8"), re.M))

    declared_actors: set[str] = set()
    if actors_md.exists():
        declared_actors = set(re.findall(r"`(human:[^`]+|process:[^`]+|[^`|]+/[^`]+)`", actors_md.read_text(encoding="utf-8")))

    used_actors: set[str] = set()
    for path in concept_files():
        text = path.read_text(encoding="utf-8")
        block, _ = split_frontmatter(text)
        if block is None:
            continue
        t = parse_scalars(block).get("type", "")
        if t and declared_types and t not in declared_types:
            advise(path, f"`type: {t}` is not registered in types.md (profile §5.2)")
        for field in ("generated", "verified"):
            for m in re.finditer(rf"{field}:(.*?)(?=^\S|\Z)", block, re.M | re.S):
                used_actors.update(re.findall(r"by:\s*([^,}\s]+)", m.group(1)))
        used_actors.update(re.findall(r"^\s+author:\s*(\S+)", block, re.M))

    if actors_md.exists():
        for actor in sorted(used_actors - declared_actors):
            advise(actors_md, f"actor `{actor}` is used in the bundle but absent from actors.md")
    elif used_actors:
        advise(BUNDLE, "an OKF actor-valued field is used but there is no actors.md (§6.1.1)")


def check_indexes() -> None:
    """Every index covers its directory: each concept verbatim, each sub-directory named.

    This deprecated verifier checks coverage and concept descriptions only. The
    closed validator owns Profile 2026.2 semantic grouping and ordering.
    """
    entry = re.compile(r"^\*\s*\[([^\]]+)\]\(([^)]+)\)(?:\s*-\s*(.+?))?\s*$")
    references = BUNDLE / "references"
    for index in sorted(BUNDLE.rglob("index.md")):
        d = index.parent
        if d == references or references in d.parents:
            continue
        described: dict[str, str] = {}
        for c in (p for p in d.glob("*.md") if p.name not in RESERVED):
            block, _ = split_frontmatter(c.read_text(encoding="utf-8"))
            described[c.name] = parse_scalars(block or "").get("description", "")
        subdirs = {f"{p.name}/" for p in d.iterdir() if p.is_dir() and any(p.iterdir())}
        listed: set[str] = set()
        for n, line in enumerate(index.read_text(encoding="utf-8").splitlines(), 1):
            if not line.startswith("*"):
                continue
            m = entry.match(line)
            if not m:
                advise(f"{_rel(index)}:{n}", "entry is not a Markdown index bullet")
                continue
            _, target, desc = m.groups()
            listed.add(target)
            if target.endswith("/"):
                if target not in subdirs:
                    advise(f"{_rel(index)}:{n}", f"entry targets missing or empty directory `{target}`")
                continue
            if d == BUNDLE and target == "log.md":
                continue
            if target not in described:
                advise(f"{_rel(index)}:{n}", f"entry targets missing concept `{target}`")
            elif described[target] and desc != described[target]:
                advise(
                    f"{_rel(index)}:{n}",
                    f"description differs from `{target}` frontmatter (profile §9 requires verbatim)",
                )
        for missing in sorted(set(described) - listed):
            advise(index, f"concept `{missing}` has no index entry")
        for missing in sorted(subdirs - listed):
            advise(index, f"directory `{missing}` has no index entry")


def check_links() -> None:
    """Resolve markdown links, ignoring fenced blocks and inline code spans.

    Illustrative link syntax inside backticks is documentation, not a link — a
    verifier that flags it trains authors to stop writing examples.
    """
    link = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)")
    inline_code = re.compile(r"`[^`]*`")
    for path in concept_files() + sorted(BUNDLE.rglob("index.md")):
        text = path.read_text(encoding="utf-8")
        in_fence = False
        for n, raw in enumerate(text.splitlines(), 1):
            if raw.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            line = inline_code.sub("", raw)
            for target in link.findall(line):
                if target.startswith(("http://", "https://", "#", "mailto:")):
                    continue
                clean = target.split("#", 1)[0]
                if not clean:
                    continue
                base = BUNDLE if clean.startswith("/") else path.parent
                resolved = (base / clean.lstrip("/")).resolve()
                if not resolved.exists():
                    advise(f"{_rel(path)}:{n}", f"broken link -> {target}")


def check_relationships() -> None:
    bullet = re.compile(r"^-\s*([^:]+):\s*\[")
    for path in concept_files():
        body = split_frontmatter(path.read_text(encoding="utf-8"))[1]
        section = re.search(r"^#+\s*Relationships\s*$(.*?)(?=^#+\s|\Z)", body, re.M | re.S)
        if not section:
            continue
        for n, line in enumerate(section.group(1).splitlines(), 1):
            line = line.strip()
            if not line.startswith("-"):
                continue
            m = bullet.match(line)
            if not m:
                advise(path, f"Relationships bullet is not `- Label: [target](path)`: {line[:60]}")
            elif m.group(1).strip() not in CORE_LABELS:
                advise(path, f"non-core relationship label `{m.group(1).strip()}` (permitted; noting)")


def check_profile_declaration() -> None:
    profile = BUNDLE / "profile.md"
    index = BUNDLE / "index.md"
    if not profile.exists():
        error(BUNDLE, "profile §11: bundle has no profile.md")
        return
    body = split_frontmatter(profile.read_text(encoding="utf-8"))[1]
    fence = re.search(r"```yaml\n(.*?)```", body, re.S)
    if not fence:
        advise(profile, "no fenced yaml declaration block (profile §11)")
        return
    decl = parse_scalars(fence.group(1))
    for key in ("concepta_profile", "okf_version"):
        if key not in decl:
            advise(profile, f"declaration missing `{key}`")
    idx_block, _ = split_frontmatter(index.read_text(encoding="utf-8"))
    idx_version = parse_scalars(idx_block or "").get("okf_version", "")
    if idx_version and decl.get("okf_version") and idx_version != decl["okf_version"]:
        advise(index, f"okf_version {idx_version} disagrees with profile.md {decl['okf_version']}")


def check_root_index() -> None:
    index = BUNDLE / "index.md"
    block, _ = split_frontmatter(index.read_text(encoding="utf-8"))
    if not parse_scalars(block or "").get("okf_version"):
        advise(index, "root index carries no `okf_version` (profile §9)")
    for name in sorted(ROOT_CONCEPTS):
        if not (BUNDLE / name).exists():
            advise(BUNDLE, f"root concept `{name}` is missing (profile §3.5)")
    if not (BUNDLE / "log.md").exists():
        advise(BUNDLE, "root log `log.md` is missing (profile §3.5)")


def main() -> int:
    strict = "--strict" in sys.argv
    if not BUNDLE.is_dir():
        print(f"no bundle at {_rel(BUNDLE)}", file=sys.stderr)
        return 2

    files = concept_files()
    tiers: dict[str, int] = {}
    for path in files:
        text = path.read_text(encoding="utf-8")
        block, _ = split_frontmatter(text)
        fields = parse_scalars(block or "")
        check_okf(path, block, fields)
        if block is not None:
            check_baseline(path, fields)
            tier = trust_tier(block)
            tiers[tier] = tiers.get(tier, 0) + 1

    check_areas()
    check_registries()
    check_indexes()
    check_links()
    check_relationships()
    check_profile_declaration()
    check_root_index()

    print(f"knowledge bundle: {len(files)} concept(s) checked")
    if tiers:
        summary = " · ".join(f"{n} {t}" for t, n in sorted(tiers.items(), key=lambda kv: -kv[1]))
        print(f"  trust tiers (informational, not findings): {summary}")
    for e in errors:
        print(f"  ERROR    {e}")
    for a in advisories:
        print(f"  ADVISORY {a}")
    if not errors and not advisories:
        print("  clean")

    if errors:
        return 1
    return 1 if (strict and advisories) else 0


if __name__ == "__main__":
    sys.exit(main())
