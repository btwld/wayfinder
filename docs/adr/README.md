# Architecture decision records

One file per decision. Decisions here bind the Concepta Profile and its
tooling. A
future architecture review must not re-litigate an accepted ADR unless real
friction warrants reopening it; supersede with a new record instead of editing
history.

Format note: the lightweight header (Status / Date / Issues) is deliberate.
These records govern this repository only; a project bundle's
`knowledge/architecture/` follows its own ADR conventions.

Vocabulary: these records use *module*, *interface*, *seam*, *adapter*, *depth*,
*leverage*, and *locality* in the deep-module sense — a module is anything with
an interface and an implementation; a seam is where an interface lives; depth is
behaviour per unit of interface a caller must learn.

| # | Decision |
|---|----------|
| [0004](0004-closed-concepta-profile-validator.md) | Accepted — first implement a closed Concepta Profile validator; defer the generic platform |
| [0006](0006-raw-tier-under-references.md) | Accepted — a per-source `raw/` tier under `references/` for verbatim originals; no markdown inside but each directory's index |
| [0007](0007-index-targets-compared-percent-decoded.md) | Accepted — index entry targets are relative URLs compared percent-decoded, so real-world filenames stay expressible |
| [0008](0008-okfp-adopts-okf-finding-contract.md) | Accepted — okfp republishes okf 0.2.0's finding report as its wire format; the separate load-issue channel is retired |
