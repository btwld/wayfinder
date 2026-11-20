# Dora Profile

`dora-profile` is an additive child of the Bitwild Profile. It adds no machine
rules or vocabulary: OKF and Bitwild continue to decide bundle conformance.
This package adds Dora's source-first retrieval, evidence, lifecycle, session
continuity, and data-minimization guidance for human and agent review. Those
decisions depend on context outside a static bundle, so they are documented in
the installed skill and review map rather than presented as validator results.

The governing Dora policies remain in the Dora vault. This package does not
copy them or publish their vault paths. In a Dora bundle, use the
`Dora policy source map` concept to follow the originals through
`sources[].resource`.

## Inherited rules

All machine rules are inherited from `profiles/bitwild`. This child adds none.

See the [Dora Profile skill](skill/SKILL.md) and its [review map](skill/references/review-map.md) for authoring and judgment guidance.
