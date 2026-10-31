# Engine contract

The [implementation guide](okf-implementation-guide.md) plus
[JSON Schemas](../docs/schemas/) define Profile package format 3 for pinned
OKF 0.2. Authority is **OKF → engine contract → each Profile package**.
The guide constrains implementations and packages; a Profile's own README/skill
explains its rules and judgment without adding requirements.

| Section | Settles |
| --- | --- |
| §2 Adoption | Binding, root seeds and agent instructions |
| §3 Generation | okf generator, exact index comparison, `--fix`, authored history, Profile-aware writes (§3.5) |
| §4 Validation | Results, diagnostics, gates, findings and lock selection |
| §5 Profile packages | Identity, format, rules, facts, builtins, composition and change process |
| §6 Distribution | Packages, pinned skills and tools |
| §7 Cross-bundle references | Deferred graph semantics; use ordinary URLs |
| §9 Change record | Contract changes, drivers and migration impact |

Profile rationale/history belongs in its package, such as
[Bitwild](../profiles/bitwild/README.md). Corpus measurements and migration plans
belong in the consuming project; follow its Profile's migration guidance.
