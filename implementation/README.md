# `implementation/`: the wayfinder engine contract

[`okf-implementation-guide.md`](okf-implementation-guide.md) is the engine
contract for Profile package format 2 and OKF 0.2. It binds no single Profile.

Precedence runs one way. OKF wins over the engine contract, and the engine
contract wins over each Profile package. The contract is this guide plus the
JSON Schemas under [`docs/schemas/`](../docs/schemas/). A Profile package adds
rules within what the contract allows and can never change OKF or the contract.

The guide is normative on programs and packages. "A generator MUST be
idempotent" constrains a tool. "A package MUST NOT declare an OKF key"
constrains a Profile author. Conformance to a Profile is what `wayfinder
validate` decides with that Profile selected, so a Profile's own rules,
rationale, and history live in its package, such as
[`profiles/bitwild/`](../profiles/bitwild/README.md), not here.

## What it covers

| § | Chapter | Settles |
| --- | --- | --- |
| 2 | Adoption | Project binding, seeding the bundle root, and the agent-instruction paragraph |
| 3 | Index generation | okf's reference generator, exact comparison, and `validate --fix`; preservation of authored history |
| 4 | Validation | Results, diagnostics, and the derived gate; stable finding IDs; what a validator must never report; dispatch; the project binding and lock |
| 5 | Profile packages | What a package is; OKF first; the compatibility test; identity, release, and format; vocabulary and frontmatter keys; rules and builtins; composition; exact selection; tolerant reading; how the contract and each Profile change |
| 6 | Distribution | Profiles distribute themselves as packages; their skills reach projects through `get`; tools pinned per repository |
| 7 | Cross-bundle references | Deferred until a second bundle exists; ordinary URLs in the meantime |

## What it does not carry

Migrating an existing document tree into a bundle follows the selected
Profile's guidance, such as Bitwild's
[migration reference](../profiles/bitwild/skill/references/migration.md). A
migration's own corpus measurement and slice plan are project artifacts. They
stay in the project being migrated.
