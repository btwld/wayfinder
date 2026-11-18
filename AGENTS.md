# Working in this repository

Wayfinder holds OKF validation, a Profile-rule engine, local retrieval, public
Dart libraries, CLI/MCP, generic agent skills and Bitwild, the first Profile.
Its own knowledge lives in its bundle, [`knowledge/`](knowledge/index.md).
Another project's knowledge belongs in that project's bundle. Examples are
illustrative.

Read [README.md](README.md) for the layout, then the task's relevant files:

| Changing | Read |
| --- | --- |
| Profile format, selection, evaluation, adoption or generation | [Engine contract](implementation/okf-implementation-guide.md), [schemas](docs/schemas/), [pinned OKF 0.2](skills/author-knowledge-bundle/references/OKF-0.2.md) |
| Bitwild rules or vocabulary | [README](profiles/bitwild/README.md), [package](profiles/bitwild/wayfinder-profile.json), [changelog](profiles/bitwild/CHANGELOG.md) |
| Agent workflows | [Skills](skills/README.md), affected `SKILL.md` and routed references |
| Validator, retrieval or release tooling | Relevant [package](packages/), [decision log](ARCHITECTURE.md), [contributor guide](docs/contributing.md) and [CI](.github/workflows/ci.yml) |
| Profile vocabulary, composition or source mirrors | [Profiles](knowledge/profiles/index.md) |
| Validation results, diagnostics, the gate or path targets | [Validation](knowledge/validation/index.md) |
| `knowledge/`, its gate or the link checker | [Ways of working](knowledge/ways-of-working/index.md) |

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

This repository holds no client data, and `knowledge/` holds only Wayfinder's
own knowledge. Read client material live and read-only through MCP; never store
it here, including in `knowledge/` and `.context/`.

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

## Knowledge bundle

`knowledge/` is held to `current-truth`, a two-rule Profile in
`.wayfinder/profile/` that extends Bitwild. Every concept states current truth
([why](knowledge/ways-of-working/keep-one-living-concept-per-subject.md)). To
change knowledge:

1. Edit the owning concept in place. The position that lost becomes one bullet
   under its `# Rejected`. Bitwild's skill says to deprecate a retired concept;
   here the `current-truth` rules decide: no `deprecated`, no `superseded-by`.
2. Add one `Update` or `Creation` entry to `knowledge/log.md`.
3. Run `python3 tool/ci/verify-knowledge.py --fix`. It regenerates the indexes
   and judges the bundle against this checkout's Profile packages. Never
   hand-edit an `index.md`.
4. Run `python3 tool/ci/verify-links.py`.

The migration into the bundle is in progress. Until a decision or a term has a
concept, it lives in its [ARCHITECTURE.md](ARCHITECTURE.md) entry or in
[docs/GLOSSARY.md](docs/GLOSSARY.md); edit it there.

`wayfinder.lock` and installed Profile skills are ignored local state here,
because the binding follows this repository's own branch
([why](knowledge/ways-of-working/judge-the-bundle-against-its-own-checkout.md)).
Documents that readers outside this checkout link
[stay at their paths](knowledge/ways-of-working/keep-published-documents-at-their-paths.md);
add nothing new under `docs/`.

## Completing work

Use issue scope, or state maintenance scope in the PR. Update affected docs.
Complete authorized inspection and reversible fixes; ask only when missing
information materially changes scope or correctness, without repeating approval.
Run the [contributor checks](docs/contributing.md#checks) and report results.
Keep review notes/probes in `.context/`; durable guidance belongs in tracked docs.
Fixtures deliberately include invalid bundles: do not normalize them.
