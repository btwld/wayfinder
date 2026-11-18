# current-truth Profile changelog

This package holds Wayfinder's own bundle, `knowledge/`, to the
[living-concept model](../../knowledge/ways-of-working/keep-one-living-concept-per-subject.md).
It extends [Bitwild](../../profiles/bitwild/README.md). Each entry states what
changed, the real use that drove it, the migration impact and the
compatibility test of guide §5.3 for each new or changed rule, newest first.

## 1 (2026-11-18)

Adds two error rules in category `history`, and no vocabulary:

- `a-concept-is-never-deprecated`: a concept's `status` is not `deprecated`.
- `a-concept-names-no-successor`: no `relationships` entry is `superseded-by`.

Driver: two bundles held to Bitwild, this repository's and one other, keep
one concept per subject and edit it in place. Search and query return
`deprecated` concepts unless the caller filters, and an unattended agent acts
on the first document it opens, so a deprecated copy of a decision is a stale
answer that looks current. Each bundle states the shape as rules, so the
CLI, MCP and SARIF report a departure from it.

Migration impact: none. `knowledge/` is the only bundle bound to this package
and is created with it. A bundle that passes Bitwild fails this package only
for a `deprecated` concept or a `superseded-by` relationship. Its fix is to
merge the old concept into the one that replaced it and delete it.

Compatibility with OKF 0.2, for each rule:

- It uses only constructs OKF permits. Both rules read `status` and
  `relationships`, which OKF defines, through a JSON Schema over existing
  facts.
- It keeps the upstream meaning of every field. `deprecated` and
  `superseded-by` keep their OKF meaning. The rules only rule them out in this
  bundle, which narrows through a rule as §5.3 allows.
- It leaves the OKF graph contract uninterpreted. The successor rule reads one
  relationship name and resolves no target.
- It leaves the independent OKF result unchanged. Both findings come from this
  package, and OKF's own findings are reported as before.
- It leaves the bundle readable by a generic OKF consumer, which sees ordinary
  concepts with OKF statuses and relationships.
