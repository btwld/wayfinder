# `implementation/` — the companion implementation guide

[`okf-implementation-guide.md`](okf-implementation-guide.md) — current
**2026.1 guide**, binding Profile 2026.1 exactly to OKF 0.2.

[`profile-coverage-2026.1.md`](profile-coverage-2026.1.md) is the complete
rule-to-assessment matrix. It is separate from the OKF compatibility review
because implementation coverage cannot prove specification compatibility.

The profile specifies *what a bundle is*. This document specifies *how one is built, checked,
and kept*: adoption, the index generator's contract, the validation process contract, and the
migration method.

The two are normative on different things. The profile binds **bundles** — a bundle either
conforms or it does not. This guide binds **implementations**: tools, adoptions, migrations.
"A generator MUST be idempotent" constrains a program, never a bundle, which is why it could
not have been written in the profile. Both carry RFC 2119 force; "guide" is not the soft one.

Precedence runs one way — OKF over the profile, the profile over this — so where the two
appear to differ, the profile wins and this text is defective.

## What it covers

| § | Chapter | Settles |
| --- | --- | --- |
| 2 | Adoption | Four required root files, the conditional actor registry, the agent-instruction paragraph, and why generic setup creates no directories |
| 3 | Index generation | Determinism, idempotence, semantic projection, presentation-independent comparison, and preservation of authored history |
| 4 | Validation | Exit codes, stable finding IDs, what a validator must never report, and version dispatch |
| 5 | Migration | Measure, classify, cluster, slice vertically; granularity by the promotion rule; the three invariants every migration carries |
| 6 | Distribution | Skills installed per developer, tools pinned per repository; no project vendors a copy of the profile |
| 7 | Cross-bundle references | Deferred until a second bundle exists; ordinary URLs in the meantime |

## Still owed

- **The index generator itself.** §3 specifies it, but no generator is shipped. Until one
  exists, indexes are hand-written and the validator catches the drift.

## What §5 does not carry

A migration's own corpus measurement and slice plan are **project artifacts**. They stay in the
project being migrated and expire with it. Only the *method* generalizes, and that is §5.
