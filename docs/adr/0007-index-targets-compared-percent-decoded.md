# ADR-0007: Index targets are relative URLs, compared percent-decoded

- Status: accepted
- Date: 2026-08-25

## Context

The migration QA behind ADR-0006 hit a second, harder edge in the same
`references/` tier. Verbatim originals keep their source filenames by design,
and real filenames carry spaces, parentheses, and characters outside ASCII.
For such a file, §9's projection comparison was unsatisfiable: the expected
side demanded the raw path as the entry target, while the parsed side reads
the link destination from a Markdown parser — and a parser normalizes
destinations to a percent-encoded form. A raw-spelled target is not a valid
CommonMark destination at all when it contains spaces; an encoded or
angle-bracket-spelled one parses, but its normalized href no longer equals the
raw path. Every spelling the author could write failed §9. Three directories
of the first migrated corpus were stuck this way.

The normalization is also not canonical across character classes (the parser
encodes spaces but leaves parentheses as written), so pinning one byte-exact
target spelling would chase parser internals rather than state a rule.

## Decision

- A §9 entry target is written as a relative URL, which is what OKF §8 already
  calls it. A character a plain link destination cannot carry literally is
  percent-encoded (RFC 3986), or carried by CommonMark's angle-bracket
  destination form.
- Conformance compares each parsed target **percent-decoded** against the
  projected path. Every valid spelling of the same target is therefore
  equivalent, and the projection stays deterministic where it matters: in
  what the entry identifies, not in which escape the author chose.
- A percent sign outside a valid escape sequence does not parse as a target,
  and a decoding failure is a projection finding, never a crash.
- A spelling a relative-URL consumer reads differently from the decoded
  comparison does not parse as a target either: a raw `?` or `#` must be
  percent-encoded — a URL splits at them into query and fragment — and no
  escape may decode to `/`, which a URL reads as data, never as a path
  separator. Without this, `vendor%2F` or a raw `#` would validate while
  resolving elsewhere as a URL, and the compatibility claim below would fail
  exactly where it matters.
- Labels are not URLs. An asset's label remains its filename exactly as
  written even when its target is encoded.

This passes ADR-0004's compatibility test: OKF §8 names the target a
"relative-url" and is silent on encoding; the profile settles the comparison
of its own projection — a construct OKF does not define — and adds no field or
filename meaning. A generic OKF consumer resolves the entry as any relative
URL, which is exactly the decoded path.

**Release handling.** Ships as the second in-place amendment to 2026.1 under
the same bounded QA-period exception ADR-0006 records; the §15.3 entry names
it. Once adopted bundles exist, a change of this kind takes a new release.

## Consequences

- Existing conformant bundles stay conformant: a target that matched before
  contains no escapes and decodes to itself. The one exception is a target
  that carried a raw `?` or `#` and matched byte-for-byte; it now needs the
  encoded spelling — the only one a URL consumer resolves to the file.
- Reference directories holding verbatim originals with real-world filenames
  become expressible; the authoring skill's index-projection reference teaches
  the encoded spelling.
- Upstream coordination, not profile scope: okf's index entry line grammar
  currently rejects a raw `)` inside a target, so the fully percent-encoded
  spelling (`%28`/`%29`) is the one that satisfies both layers until okf
  widens its grammar. The profile deliberately does not encode that tooling
  limit as a rule.
