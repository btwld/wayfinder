# Architecture decision records

One file per decision. Decisions here bind the Concepta Profile and its
tooling. A
future architecture review must not re-litigate an accepted ADR unless real
friction warrants reopening it; supersede with a new record instead of editing
history.

These records were accepted in the 2026-08-14 architecture review of the
original combined spec and re-homed here by the toolchain split; dates and
status are original. In the review's numbering they were 0005, 0007, and 0008;
conceptadev/okf scrubbed them before its ADR set landed, so this is the only
record of the mapping: 0005 → 0001, 0007 → 0002, 0008 → 0003.

Format note: the lightweight header (Status / Date / Issues) is deliberate.
The knowledge-bundle ADR template (`skills/engineering/domain-modeling/ADR-FORMAT.md`)
governs `knowledge/architecture/` in project bundles, not this directory.

Vocabulary: these records use *module*, *interface*, *seam*, *adapter*, *depth*,
*leverage*, and *locality* in the deep-module sense — a module is anything with
an interface and an implementation; a seam is where an interface lives; depth is
behaviour per unit of interface a caller must learn.

| # | Decision |
|---|----------|
| [0001](0001-ack-behind-interpreter-seam.md) | Superseded — ack and manifest-era finding IDs |
| [0002](0002-judgment-parse-and-preserve.md) | Superseded — manifest `judgment` declarations |
| [0003](0003-suppressions-in-profile-yaml.md) | Superseded — suppressions in `profile.yaml` |
| [0004](0004-closed-concepta-profile-validator.md) | Accepted — first implement a closed Concepta Profile validator; defer the generic platform |
