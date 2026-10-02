# Working in this repository

This repository holds Concepta's reusable approach to project knowledge: the OKF
Profile, its implementation guide, agent skills, and validation tooling. A project's
own knowledge belongs in that project's bundle. Examples here are illustrative.

Read [README.md](README.md) for the layout, then the files relevant to the task:

| Changing | Read |
| --- | --- |
| Bundle conventions | [Profile](profile/okf-profile.md) and [pinned OKF 0.2](skills/author-knowledge-bundle/references/OKF-0.2.md) |
| Adoption, generation, validation, or migration behavior | [Implementation guide](implementation/okf-implementation-guide.md) |
| Agent workflows | [Skills](skills/README.md), the affected `SKILL.md`, and its routed references |
| Validator or release tooling | [Package](packages/wayfinder/README.md), relevant [ADRs](docs/adr/README.md), and [CI](.github/workflows/ci.yml) |

## Authority and scope

**OKF → Profile → implementation guide.** The Profile constrains bundles; the
guide constrains implementations. Neither may redefine, extend, or narrow the
meaning of a rule or field above it. The guide binds behavior the Profile leaves
open; it must not become a second copy of Profile rules.

Where the Profile is silent, consult pinned OKF. Follow what it settles; silence
neither prohibits an OKF mechanism nor authorizes an invented Concepta convention.

Keep changes generic. A new convention needs evidence from a real corpus and must
hold across projects. Findings justify a release; they become rules only through
the Profile release process. Project vocabulary belongs in the project's bundle.
Outside the five names the Profile fixes — `architecture/`, `ways-of-working/`,
`interactions/`, `references/`, `computations/` — its example directory names are illustrative,
never a taxonomy to adopt.

This repository holds no client data or project knowledge. Read client material
live and read-only through MCP; do not store it here, including in `.context/`.

## Changing conventions

A Profile convention change needs all of the following in the same change:

1. An explicit MUST, MUST NOT, SHOULD, SHOULD NOT, or MAY rule.
2. A §15.3 change-record entry naming affected sections and the real-use driver.
3. Migration impact in words: whether existing conformant bundles stay conformant,
   and what they must do if not.
4. A new `<year>.<serial>` release and an immutable snapshot of the superseded
   release under `profile/versions/`.

Keep canonical paths and symbols stable. Releases live in document headers and
the validator's `supportedProfileRelease` constant, not filenames or symbol names.
Only immutable snapshots, including vendored OKF, carry versions in their names.

An upstream OKF **specification** release requires a new Profile release and a
compatibility review, even without another convention change. An `okf` package
release that changes no specification text does not, unless it changes the
output of the index generator a Profile names (Profile §9, §15.1); adopting
that release needs a Profile revision. Never claim unreviewed
compatibility. Update [compatibility evidence](docs/compatibility-review.md) and
[assessment coverage](implementation/profile-coverage.md) when their rules change;
they answer different questions and neither replaces the other.

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

## Completing work

- Use the driving issue as scope, or state the scope in the proposed PR for
  maintenance without an issue. Update affected documentation in the same change.
- Complete authorized inspection and reversible fixes. Ask only when missing
  information materially changes scope or correctness; do not repeat approval
  already supplied by the user.
- Use the [contributor checks](README.md#contributor-checks) and report what ran.
  Automated validation does not establish contextual Profile conformance.
- Keep review notes and temporary probes in `.context/`. Durable generic guidance
  belongs in the relevant tracked document. Test fixtures deliberately include
  invalid bundles; do not normalize them as housekeeping.
