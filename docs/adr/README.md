# Architecture decision records

One file per decision. Decisions here bind the profile-toolchain work specced
in [#3](https://github.com/btwld/okf-profile/issues/3) and its sub-issues. A
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
| [0001](0001-ack-behind-interpreter-seam.md) | okf_profile owns frontmatter finding IDs; ack hides behind the interpreter seam |
| [0002](0002-judgment-parse-and-preserve.md) | The manifest `judgment` section is parse-and-preserve |
| [0003](0003-suppressions-in-profile-yaml.md) | Suppressions declare in `profile.yaml` |
| [0004](0004-profile-yaml-owned-by-profile-layer.md) | `profile.yaml` belongs to the profile layer; base okf never learns the name |
