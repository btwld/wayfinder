# ADR-0007: Compare index targets as percent-decoded relative URLs

- Status: accepted
- Date: 2026-08-25
- Revised: 2026-09-28 (condensed; [pre-rewrite record](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/adr/0007-index-targets-compared-percent-decoded.md))
- Scope: Profile index projection, 2026.1 and 2026.2
- Superseded for Profile 2026.3 by its in-place revision that makes every index
  the output of okf's reference generator ([Profile §9](../../profile/okf-profile.md#9-index-files)
  and §15.3); there is no projection left to compare. This record still governs
  2026.2.

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

## Options considered

- Byte-for-byte comparison was rejected because valid Markdown/URL spellings
  normalize differently.
- One newly invented canonical escape spelling was rejected because it would
  make parser presentation an artificial Profile requirement.

## Consequences

Ordinary unescaped targets stay conformant. A formerly byte-matching raw `?`
or `#` target needs its encoded spelling so a URL consumer reaches the file.
At adoption, upstream OKF's entry grammar also required encoding parentheses
in targets; that parser limitation is not a Profile rule.

The 2026.1 change was recorded during initial QA alongside
[ADR-0006](0006-raw-tier-under-references.md). Later convention changes
require a new Profile release.

## Reconsider when

Reopen this rule if the pinned OKF parser changes its relative-URL grammar or
normalization contract. Any replacement must preserve the target a generic URL
consumer resolves, not merely match a new parser representation.
