# ADR-0007: Compare index targets as percent-decoded relative URLs

- Status: accepted
- Date: 2026-08-25
- Scope: Profile index projection

## Context

Verbatim assets can have spaces, parentheses, and non-ASCII filenames. A raw
path containing spaces is not a valid CommonMark link destination, while a
Markdown parser normalizes valid spellings. Comparing the parser's href
byte-for-byte with a raw filesystem path made correct indexes impossible.

## Decision

Write index targets as relative URLs, as OKF §8 describes them. Compare the
parsed target after percent-decoding with the projected path. Encoded and
CommonMark angle-bracket spellings that identify the same file are equivalent;
asset labels remain the exact filenames.

Reject malformed escapes and spellings whose URL meaning differs from that
path. In particular, raw `?` and `#` must be encoded because a URL treats them
as delimiters, and an escape must not decode to `/` as a path separator.
Decoding failures produce projection findings, not crashes.

This settles a Profile projection comparison without changing OKF's URL or
graph contract.

## Consequences

Ordinary unescaped targets stay conformant. A formerly byte-matching raw `?`
or `#` target needs its encoded spelling so a URL consumer reaches the file.
At adoption, upstream OKF's entry grammar also required encoding parentheses
in targets; that parser limitation is not a Profile rule.

The 2026.1 change was recorded during initial QA alongside
[ADR-0006](0006-raw-tier-under-references.md). Later convention changes
require a new Profile release.
