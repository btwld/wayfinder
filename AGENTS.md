# Working in this repository

Wayfinder holds OKF validation, a Profile-rule engine, local retrieval, public
Dart libraries, CLI/MCP, generic agent skills and Bitwild, the first Profile.
Project knowledge belongs in that project's bundle. Examples are illustrative.

Read [README.md](README.md) for the layout, then the task's relevant files:

| Changing | Read |
| --- | --- |
| Profile format, selection, evaluation, adoption or generation | [Engine contract](implementation/okf-implementation-guide.md), [schemas](docs/schemas/), [pinned OKF 0.2](skills/author-knowledge-bundle/references/OKF-0.2.md) |
| Bitwild rules or vocabulary | [README](profiles/bitwild/README.md), [package](profiles/bitwild/wayfinder-profile.json), [changelog](profiles/bitwild/CHANGELOG.md) |
| Agent workflows | [Skills](skills/README.md), affected `SKILL.md` and routed references |
| Validator, retrieval or release tooling | Relevant [package](packages/), [ADRs](docs/adr/README.md), [contributor guide](docs/contributing.md) and [CI](.github/workflows/ci.yml) |

## Authority and scope

**OKF → engine contract → each Profile package.** The contract is the guide plus
JSON Schemas. Neither contract nor Profile may redefine, extend or narrow an OKF
field's meaning. A Profile's README/skill guides judgment and adds no requirement.
`wayfinder validate` decides conformance with the selected Profile.

The framework contract lives once, in the guide's §5. Bitwild is one Profile,
never a base. Keep its rules, rationale and history in `profiles/bitwild/`; keep
engine, guide and generic skills free of any one Profile's conventions.
Where a Profile is silent, follow pinned OKF; silence neither prohibits its
mechanisms nor authorizes invented conventions.

A new rule needs evidence from a real corpus. Findings justify a release; they
become rules only through that Profile's release process. Project vocabulary
belongs in the project's binding.

This repository holds no client data or project knowledge. Read client material
live and read-only through MCP; never store it here, including in `.context/`.

## Change requirements

Follow the [engine-contract](docs/contributing.md#engine-contract-changes) or
[Profile](docs/contributing.md#profile-changes) checklist in the same change.
They cover ADR/change records, compatibility, schemas/goldens, migration and
release requirements. Never silently reinterpret a package or claim unreviewed
upstream compatibility.

Keep canonical paths and symbols stable. Releases live in package fields and
changelogs, not filenames; only immutable snapshots and vendored OKF carry
versions in their names.

Generic `skills/` owns OKF/CLI mechanics. Profile judgment lives in each package's
`skill/`, installed by `get`. `author-knowledge-bundle` loads each Profile skill;
other generic skills delegate to it. Update `create-profile` with the contract;
search a Profile's skill for withdrawn wording when changing its rules.

## Completing work

Use issue scope, or state maintenance scope in the PR. Update affected docs.
Complete authorized inspection and reversible fixes; ask only when missing
information materially changes scope or correctness, without repeating approval.
Run the [contributor checks](docs/contributing.md#checks) and report results.
Keep review notes/probes in `.context/`; durable guidance belongs in tracked docs.
Fixtures deliberately include invalid bundles: do not normalize them.
