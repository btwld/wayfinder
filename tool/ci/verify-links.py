#!/usr/bin/env python3
"""Every link, anchor and self URL in the repository's own text resolves.

Standard library, no Dart, no network.

This is repository hygiene, not conformance. It never parses frontmatter and
knows no concept type. It exists because `wayfinder validate` reads no anchor
and no link that leaves a bundle, and this repository keeps one source per
fact by pointing at it.

Semantics are GitHub's, because that is where people and pub.dev follow the
links: a relative target resolves from the page, and a leading `/` resolves
from the repository root. A bundle-absolute body link therefore fails here,
which keeps concept links page-relative.

Exit status: 0 no issue, 1 at least one issue.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path, PurePosixPath
from typing import Iterable, Iterator, Literal
from urllib.parse import unquote

SELF_URL = "https://github.com/btwld/wayfinder/blob/main/"
SELF_PREFIXES = (
    SELF_URL,
    "https://github.com/btwld/wayfinder/tree/main/",
    "https://raw.githubusercontent.com/btwld/wayfinder/main/",
)
"""How readers outside the checkout address `main`: a page, a directory (a
pubspec `repository`), and raw bytes (the install one-liners)."""

UNCHECKED: tuple[tuple[str, str], ...] = (
    (r"(^|/)(test|tests|fixtures|goldens)/", "fixtures deliberately hold invalid bundles and dead links"),
    (r"^profiles/[^/]+/versions/", "immutable snapshots; versions/README.md says their links may not resolve"),
    (r"^skills/author-knowledge-bundle/references/OKF-0\.2\.md$", "vendored upstream bytes"),
    (r"^examples/[^/]+/knowledge/", "illustrative bundles hold a deliberate planned link"),
    (r"(^|/)\.(claude|agents)/skills/", "installed copies of another revision"),
)
"""Sources no rule reads, each with its reason. A target inside one of these is
still required to exist; only its own links and headings are not read."""

TEXT_SUFFIXES = frozenset({".md", ".dart", ".json", ".py", ".sh", ".ps1", ".yaml", ".yml"})
PROFILE_PACKAGE = "wayfinder-profile.json"

RuleId = Literal[
    "link-resolves",
    "anchor-names-a-heading",
    "self-url-resolves",
    "rule-help-link-lands",
]

_FENCE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")
_INLINE_CODE = re.compile(r"(`+).+?\1")
_INLINE_LINK = re.compile(
    r"""\]\(\s*(?:<([^>\n]*)>|([^)\s]+))(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)"""
)
_DEFINITION = re.compile(r"^\s{0,3}\[(?!\^)[^\]]+\]:\s*<?([^\s>]+)")
_SCHEME = re.compile(r"[a-zA-Z][a-zA-Z0-9+.-]*:|//")
_HEADING = re.compile(r"^ {0,3}#{1,6}[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$")
_LINK_TEXT = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
_SELF = re.compile(
    "(?:" + "|".join(map(re.escape, SELF_PREFIXES)) + ")" + r"""([^\s"'`<>()\[\]{}#\\]*)(?:#([\w.%-]*))?"""
)


@dataclass(frozen=True)
class Tree:
    """Tracked files plus untracked files Git does not ignore.

    `git ls-files -co --exclude-standard`, so a new concept is checked before
    `git add`. `directories` is every directory those paths imply.
    """

    root: Path
    paths: frozenset[str]
    directories: frozenset[str]

    @classmethod
    def holding(cls, root: Path, paths: Iterable[str]) -> Tree:
        """A tree of `paths` under `root`, with the directories they imply."""
        held = frozenset(paths)
        return cls(
            root=root,
            paths=held,
            directories=frozenset(
                parent.as_posix()
                for path in held
                for parent in PurePosixPath(path).parents
                if parent.as_posix() != "."
            ),
        )

    def text(self, path: str) -> str | None:
        """UTF-8 text of `path`, or None when it is not UTF-8."""
        try:
            return (self.root / path).read_text(encoding="utf-8")
        except UnicodeDecodeError:
            return None


@dataclass(frozen=True)
class Reference:
    """One thing a file points at, already resolved to a repository path.

    `target` is None when the written form climbs out of the repository.
    `fragment` is None when the reference has no `#…` part.
    """

    source: str
    line: int
    written: str
    target: str | None
    fragment: str | None


@dataclass(frozen=True)
class Issue:
    rule: RuleId
    source: str
    line: int
    message: str


def read_tree(root: Path) -> Tree:
    listed = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"],
        cwd=root, check=True, text=True, capture_output=True,
    ).stdout.split("\0")
    # The index still lists a file deleted in the working tree.
    return Tree.holding(root, (path for path in listed if (root / path).is_file()))


def _unchecked(path: str) -> bool:
    return any(re.search(pattern, path) for pattern, _ in UNCHECKED)


def _prose_lines(text: str) -> Iterator[tuple[int, str]]:
    """Numbered lines outside fenced code, whatever the fence's indentation."""
    fence = None
    for number, line in enumerate(text.splitlines(), start=1):
        match = _FENCE.match(line)
        if fence is None:
            if match:
                fence = match.group(1)
            else:
                yield number, line
        elif (
            match
            and match.group(1)[0] == fence[0]
            and len(match.group(1)) >= len(fence)
            and not match.group(2).strip()
        ):
            fence = None


def _resolve(source: str, written: str) -> tuple[str | None, str | None]:
    """The repository path and fragment a GitHub reader of `source` lands on."""
    location, hash_mark, fragment = written.partition("#")
    location = unquote(location.partition("?")[0])
    if not location:
        target = source
    else:
        base = "" if location.startswith("/") else PurePosixPath(source).parent.as_posix()
        target = _normalize(f"{base}/{location}")
    return target, unquote(fragment) if hash_mark else None


def _normalize(path: str) -> str | None:
    parts: list[str] = []
    for part in path.split("/"):
        if part in ("", "."):
            continue
        if part != "..":
            parts.append(part)
        elif parts:
            parts.pop()
        else:
            return None
    return "/".join(parts)


def markdown_references(path: str, text: str) -> Iterator[Reference]:
    """Inline links, reference definitions and images of one Markdown file.

    Skips fenced code at any indentation and inline code, so an example link
    inside a code block is not a reference. Skips targets with a URI scheme.
    A bare `#fragment` targets `path` itself.
    """
    for number, line in _prose_lines(text):
        prose = _INLINE_CODE.sub(lambda code: " " * len(code.group(0)), line)
        targets = [bracketed or bare for bracketed, bare in _INLINE_LINK.findall(prose)]
        definition = _DEFINITION.match(prose)
        if definition:
            targets.append(definition.group(1))
        for written in targets:
            if written and not _SCHEME.match(written):
                target, fragment = _resolve(path, written)
                yield Reference(path, number, written, target, fragment)


def self_url_references(path: str, text: str) -> Iterator[Reference]:
    """Every URL under a `SELF_PREFIXES` entry in any text file: Dart, JSON, Python,
    shell, YAML, Markdown.

    Trailing sentence punctuation is not part of the URL.
    """
    for number, line in enumerate(text.splitlines(), start=1):
        for match in _SELF.finditer(line):
            written = match.group(0).rstrip(".,;:!?")
            path_start = match.start(1) - match.start(0)
            target, fragment = _resolve("", "/" + written[path_start:])
            yield Reference(path, number, written, target, fragment)


def help_link_references(path: str, text: str) -> Iterator[Reference]:
    """For a `wayfinder-profile.json` whose `docs` starts with `SELF_URL`: one
    reference per rule, to `docs` with the rule id as fragment.

    This is the link the engine prints as a finding's `help_uri` (guide §5.4).
    """
    try:
        package = json.loads(text)
    except ValueError:
        return
    docs = package.get("docs") if isinstance(package, dict) else None
    if not isinstance(docs, str) or not docs.startswith(SELF_URL):
        return
    page = docs.partition("#")[0]
    target, _ = _resolve("", "/" + page[len(SELF_URL):])
    lines = text.splitlines()
    rules = package.get("rules")
    for rule in rules if isinstance(rules, list) else []:
        # `wayfinder get` reports a malformed package; this only skips it.
        rule_id = rule.get("id") if isinstance(rule, dict) else None
        if not isinstance(rule_id, str):
            continue
        declared = f'"id": "{rule_id}"'
        number = next((n for n, line in enumerate(lines, start=1) if declared in line), 1)
        yield Reference(path, number, f"{page}#{rule_id}", target, rule_id)


def heading_slugs(text: str) -> frozenset[str]:
    """GitHub's anchor for every ATX heading outside fenced code.

    Lowercase; drop everything but letters, digits, spaces, hyphens and
    underscores; spaces become hyphens; a repeated slug gains `-1`, `-2`.
    `### 5.6 Rules and builtins` gives `56-rules-and-builtins`.
    """
    slugs: set[str] = set()
    seen: dict[str, int] = {}
    for _, line in _prose_lines(text):
        heading = _HEADING.match(line)
        if not heading:
            continue
        shown = _LINK_TEXT.sub(r"\1", heading.group(1)).lower()
        slug = "".join(
            character for character in shown
            if character.isalnum() or character in " -_"
        ).replace(" ", "-")
        repeats = seen.get(slug, 0)
        seen[slug] = repeats + 1
        slugs.add(slug if repeats == 0 else f"{slug}-{repeats}")
    return frozenset(slugs)


@lru_cache(maxsize=None)
def _readable_slugs(tree: Tree, target: str | None) -> frozenset[str] | None:
    """Heading slugs of a Markdown `target` whose headings are read, else None."""
    if (
        target is None
        or target not in tree.paths
        or not target.endswith(".md")
        or _unchecked(target)
    ):
        return None
    text = tree.text(target)
    return None if text is None else heading_slugs(text)


def _names_a_heading(tree: Tree, reference: Reference) -> bool:
    """False only when the fragment can be checked and no heading has that slug."""
    slugs = _readable_slugs(tree, reference.target)
    if slugs is None or not reference.fragment:
        return True
    return reference.fragment.lower() in slugs


def _exists(tree: Tree, target: str | None) -> bool:
    return target is not None and (
        target == "" or target in tree.paths or target in tree.directories
    )


def checked_sources(tree: Tree) -> list[str]:
    """Text files of `tree` that the rules read."""
    return sorted(
        path for path in tree.paths
        if PurePosixPath(path).suffix in TEXT_SUFFIXES and not _unchecked(path)
    )


def check(tree: Tree) -> list[Issue]:
    """Apply the four rules below to every checked source. Pure over `tree`.

    Issues are ordered by source, line, rule.
    """
    found: list[Issue | None] = []
    for path in checked_sources(tree):
        text = tree.text(path)
        if text is None:
            continue
        if path.endswith(".md"):
            for reference in markdown_references(path, text):
                found.append(link_resolves(tree, reference))
                found.append(anchor_names_a_heading(tree, reference))
        for reference in self_url_references(path, text):
            found.append(self_url_resolves(tree, reference))
        if PurePosixPath(path).name == PROFILE_PACKAGE:
            for reference in help_link_references(path, text):
                found.append(rule_help_link_lands(tree, reference))
    return sorted(
        (issue for issue in found if issue is not None),
        key=lambda issue: (issue.source, issue.line, issue.rule, issue.message),
    )


def link_resolves(tree: Tree, reference: Reference) -> Issue | None:
    """Contract: a relative link in a Markdown file names a path the tree holds.

    Defect it catches: a document moves or is deleted and a pointer to it
    stays behind. The pointer is what replaced a restated fact, so a dead one
    leaves a reader with nothing. It is also what proves each migration slice
    repointed every reader.
    """
    if _exists(tree, reference.target):
        return None
    reason = (
        "leaves the repository" if reference.target is None
        else f"names {reference.target}, which does not exist"
    )
    return Issue("link-resolves", reference.source, reference.line,
                 f"{reference.written} {reason}")


def anchor_names_a_heading(tree: Tree, reference: Reference) -> Issue | None:
    """Contract: a `#fragment` on a link to a Markdown file is the slug of a heading there.

    Defect it catches: a living concept is edited in place and its rule
    heading is reworded, or a guide section is renumbered, while a package
    README, a skill or `AGENTS.md` still cites the old anchor. GitHub then
    opens the top of the page and the reader takes the wrong rule for the one
    cited.
    """
    if _names_a_heading(tree, reference):
        return None
    return Issue("anchor-names-a-heading", reference.source, reference.line,
                 f"{reference.written}: {reference.target} has no heading "
                 f"#{reference.fragment}")


def self_url_resolves(tree: Tree, reference: Reference) -> Issue | None:
    """Contract: a URL of this repository's `main` names a path the tree holds,
    and its fragment a heading when the path is Markdown.

    Defect it catches: a URL that ships inside an artifact goes dead on
    merge: the install guide URL the CLI prints, the install script URL, a
    pubspec `repository`, the query guide link in `skills/use-wayfinder/SKILL.md`,
    a schema `$id`, a Profile's `docs`. These are the links nobody can repair
    after release.
    """
    if not _exists(tree, reference.target):
        reason = "names a path that does not exist"
    elif not _names_a_heading(tree, reference):
        reason = f"names a heading {reference.target} does not have"
    else:
        return None
    return Issue("self-url-resolves", reference.source, reference.line,
                 f"{reference.written} {reason}")


def rule_help_link_lands(tree: Tree, reference: Reference) -> Issue | None:
    """Contract: every rule id of an in-repository Profile package is a heading
    slug of the page its `docs` names.

    Defect it catches: the `current-truth` rules take their text from the
    headings of the decision concept. Rewording a heading there, or renaming a
    rule, would leave a finding whose help link opens the wrong place, and the
    rule's one home would silently stop being its home. The same holds for
    Bitwild's README.
    """
    if _names_a_heading(tree, reference):
        return None
    return Issue("rule-help-link-lands", reference.source, reference.line,
                 f"rule {reference.fragment} is not a heading of {reference.target}")


def main(argv: list[str]) -> int:
    """Print `<source>:<line>: <rule>: <message>` per issue, then a count."""
    if argv:
        print("usage: python3 tool/ci/verify-links.py", file=sys.stderr)
        return 2
    tree = read_tree(Path(__file__).resolve().parents[2])
    issues = check(tree)
    for issue in issues:
        print(f"{issue.source}:{issue.line}: {issue.rule}: {issue.message}")
    print(f"{len(issues)} issue(s) in {len(checked_sources(tree))} files")
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
