# Working in this repository

This repository holds wayfinder: OKF validation plus a static-analysis engine
for your own Profile rules, its engine contract, its generic agent skills, and
Bitwild, the first Profile package. A project's own knowledge belongs in that
project's bundle. Examples here are illustrative.

Read [README.md](README.md) for the layout, then the files relevant to the task:

| Changing | Read |
| --- | --- |
| What a Profile package is, how the engine selects and evaluates one, results, adoption, or generation | [Engine contract](implementation/okf-implementation-guide.md), the [schemas](docs/schemas/), and [pinned OKF 0.2](skills/author-knowledge-bundle/references/OKF-0.2.md) |
| Bitwild's rules or vocabulary | [Bitwild README](profiles/bitwild/README.md), [package](profiles/bitwild/wayfinder-profile.json), and [changelog](profiles/bitwild/CHANGELOG.md) |
| Agent workflows | [Skills](skills/README.md), the affected `SKILL.md`, and its routed references |
| Validator or release tooling | [Package](packages/wayfinder/README.md), relevant [ADRs](docs/adr/README.md), and [CI](.github/workflows/ci.yml) |

## Authority and scope

**OKF → engine contract → each Profile package.** The engine contract is the
implementation guide plus the JSON Schemas under `docs/schemas/`. A Profile
package adds rules within that contract. Neither the contract nor a package
may redefine, extend, or narrow the meaning of an OKF field. Conformance to a
Profile is what `wayfinder validate` decides with that Profile selected. A
Profile's README and skill explain and guide; they add no requirement.

The framework contract lives once, in the guide's §5. Bitwild is one Profile
among others, never a base. Keep Bitwild's rules, rationale, and history in
`profiles/bitwild/`, and keep the engine, the guide, and the generic skills
free of any one Profile's conventions.

Where a Profile is silent, consult pinned OKF. Follow what it settles; silence
neither prohibits an OKF mechanism nor authorizes an invented convention.

Keep changes generic. A new rule needs evidence from a real corpus. Findings
justify a release; they become rules only through that Profile's release
process. Project vocabulary belongs in the project's binding.

This repository holds no client data or project knowledge. Read client material
live and read-only through MCP; do not store it here, including in `.context/`.

## Changing the engine contract

A change to what a package is, how the engine reads or composes one, its
results, its diagnostics, or its builtins needs all of the following in the
same change:

1. An ADR, or an amendment to the ADR it changes.
2. The guide's §9 change-record entry naming affected sections, the real-use
   driver, and the migration impact for implementations and packages.
3. A package `format` bump when an existing package would read differently.
   Never reinterpret an old package silently.
4. Updated schemas, goldens, and the generic skills that teach the contract.

An upstream OKF **specification** release requires an engine compatibility
review in [`docs/compatibility-review.md`](docs/compatibility-review.md) before
the engine reads it. An `okf` package release that changes what okf reports or
what its index generator writes needs a review row and a changelog entry that
names it as breaking for every Profile using `matches-generated`. Never claim
unreviewed compatibility.

## Changing a Profile

A Profile changes through its own release process, in its package. For
Bitwild, a rule or vocabulary change needs all of the following in the same
change:

1. The rule in `wayfinder-profile.json`, with `tests` that pass and fail, and
   a golden fixture that fires it.
2. A `### <rule-id>` heading with its rationale in the README.
3. A [`CHANGELOG.md`](profiles/bitwild/CHANGELOG.md) entry naming the rules
   changed, the real-use driver, and migration impact in words: whether
   bundles that passed still pass, and what they must do if not.
4. A row in Bitwild's [compatibility review](profiles/bitwild/compatibility-review.md)
   for each new or changed rule or declared key.
5. When the release is published, a new `release` value, a tag that never
   moves, and an immutable snapshot of the superseded package under
   `profiles/bitwild/versions/`.

Keep canonical paths and symbols stable. A Profile's release lives in its
package's `release` field, and the engine's in its pubspec and changelog, not
in filenames or symbol names. Only immutable snapshots, including vendored
OKF, carry versions in their names.

## Changing skills

Two kinds of skill live here. The generic family under `skills/` knows OKF
and the `wayfinder` CLI and no particular Profile. Each Profile's judgment
lives in that Profile's own skill, in its package's `skill/` directory, and
`wayfinder get` installs it into consuming projects. `create-profile` writes
and revises Profile skills from the author's answers to its questions.

Keep the generic family Profile-agnostic. A convention one Profile chooses
belongs in that Profile's skill, never in `skills/`. Concept mechanics live in
`author-knowledge-bundle`, which loads the skill of each Profile in a bundle's
chain; the other generic skills delegate to it.

When a Profile rule changes, search that Profile's skill for the old wording,
starting with its adoption seed. A skill can produce valid files while
teaching a withdrawn rule, which a validator cannot detect. Consumers install
the generic family as the `wayfinder` plugin or a copy of `skills/`; Profile
skills arrive pinned to each project's lock.

When the engine contract changes, update `create-profile` and its
`references/` in the same change. They teach the package format and the
builtins, and a Profile author reads them before the guide.

## Completing work

- Use the driving issue as scope, or state the scope in the proposed PR for
  maintenance without an issue. Update affected documentation in the same change.
- Complete authorized inspection and reversible fixes. Ask only when missing
  information materially changes scope or correctness; do not repeat approval
  already supplied by the user.
- Use the [contributor checks](README.md#contributor-checks) and report what ran.
  Validation decides conformance; it does not review the judgment a
  Profile's skill asks for.
- Keep review notes and temporary probes in `.context/`. Durable generic guidance
  belongs in the relevant tracked document. Test fixtures deliberately include
  invalid bundles; do not normalize them as housekeeping.
