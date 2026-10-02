---
name: create-profile
description: Create or revise a wayfinder Profile package for OKF knowledge bundles. Grounds in the author's corpus, interviews the author through a fixed question set, writes the package's rules with tests and its agent skill, proves both against a synthetic Git source, and releases it. Use for /create-profile, "make a Profile for our bundles", "turn our conventions into a Profile", or changing an existing Profile's rules or judgment.
disable-model-invocation: true
---

# Create a Profile

A Profile is a package that a project binds its OKF bundle to. Wayfinder
owns the questions a Profile must answer. The Profile's author owns every
answer. This skill turns the answers into two artifacts:

- `wayfinder-profile.json`, the rules and vocabulary `wayfinder validate`
  enforces;
- `skill/`, the judgment a validator cannot decide, which `wayfinder get`
  installs into every project that uses the Profile.

You write for two readers who never saw this conversation: the engine, which
parses the package, and an agent that reads the installed skill cold, in the
middle of a write or a review.

## 1. Ground in the author's corpus

Read before asking. Look at the bundles the Profile will govern, the
project's contributor docs, ADRs, review comments, and any existing agent
instructions. For a revision, also read the package, its `CHANGELOG.md`, its
skill, and recent `wayfinder validate --output json` results and Profile
Review reports from projects that use it.

For each question in [references/questions.md](references/questions.md),
draft an answer with the evidence that suggests it, as `path:line`. The
corpus shows what authors did, not what they intended. A pattern in the
corpus is a candidate answer, never a ratified one.

## 2. Interview the author

Walk the questions in order. For each one, show your draft answer and its
evidence, and ask the author to ratify, correct, or reject it. Never write an
answer the author has not ratified. "The Profile says nothing here" is a
valid answer; OKF then governs. For a revision, ask only the questions the
change touches, and confirm the rest still hold.

Classify each ratified answer:

- **Vocabulary.** Names the package declares (types, tags, relationship
  names, frontmatter keys).
- **Rule.** A statement a machine can decide from the bundle alone. Prefer a
  schema rule over subject facts. Use a builtin only when
  [references/builtins.md](references/builtins.md) admits it. A check
  neither can express is judgment, or a request for a new engine capability.
- **Judgment.** A decision that needs context. It goes in the skill, with a
  check in the review map.
- **OKF.** OKF already settles it. Write nothing.

One answer often splits. "Every concept type must be declared" is a rule;
"choose `Decision` over `Analysis` when a choice was made" is judgment.

## 3. Write the package

Follow [references/package-format.md](references/package-format.md). It
lists every field, the subject facts, and the package layout.

- Give every schema rule `tests` with at least one valid and one invalid
  example. The engine runs them at parse, so a rule whose examples disagree
  with its check never loads.
- Give every rule id a heading in `README.md`, because each finding links
  to `docs#<rule-id>`.
- Write `skill/SKILL.md` with `name` equal to the Profile id. Agent Skills
  requires the name to match the installed directory, and `get` installs the
  skill as `.claude/skills/<id>/`.
- Give the skill a review map: one check per judgment answer, each with an
  id, a force (required, recommended, or permitted), and a link to the
  guidance it judges. The generic assessment flow reads it. One table row
  per check works:

  ```markdown
  | ID | Check | Force | Guide |
  | --- | --- | --- | --- |
  | R1 | Every Runbook holds steps someone follows. | Required | [When a page is a Runbook](#when-a-page-is-a-runbook) |
  ```
- Give the skill an adoption reference when projects need a seed: the
  `wayfinder.json` entry, root-file templates, the first log entry, and any
  lines for the agent instructions.
- Keep vocabulary in the package. When the skill shows a vocabulary table
  for readers, copy it from the package and keep both in step.
- Do not repeat what the rules already enforce as judgment, and do not
  restate OKF. Say where the skill is silent: OKF governs there.

## 4. Prove it

A package that was never resolved and validated is a draft. In a scratch
directory:

1. Commit the package directory, with `skill/`, into a new Git repository.
2. Create a project whose `wayfinder.json` points at that repository by
   absolute path, with `ref` set to the commit. Run `wayfinder get`. It
   parses the package, runs every rule's `tests`, and installs the skill.
   Check that `.claude/skills/<id>/SKILL.md` exists.
3. Write a small valid sample bundle that uses the Profile's vocabulary. Run
   `wayfinder validate <bundle> --fix`, then `wayfinder validate <bundle>`.
   The gate must be `PASS`.
4. For each rule, copy the sample and break exactly that rule. The run must
   report that rule's finding id, `<id>/<rule-id>`, and no other new error.
   A rule no fixture can trigger is wrong or unreachable. Fix it. Two traps
   hide a finding. A change can also stale a generated file, so run
   `--fix` on the fixture when the rule under test is not the generated-file
   rule. A change OKF itself rejects blocks every Profile rule, so keep each
   fixture valid OKF.
5. Plant one judgment defect in a copy of the sample, such as a concept
   that fails a required review-map check. Give a fresh agent, with no
   context from this session, only the generic wayfinder skills and the
   installed Profile skill, and ask it to assess the bundle. It must report
   the defect with the right check id. If it misses the defect or cites the
   wrong check, the skill is unclear. Fix the skill and run this step again.

## 5. Release it

Add a `CHANGELOG.md` entry for the release: what changed, which rule ids were
added, changed, or removed, and the migration impact on bundles that passed
the previous release. Then tag the commit. Projects move with
`wayfinder upgrade`. Never change a published release in place.

A revision that changes a rule's meaning or removes a rule id is a breaking
change for projects that pass today. Say so in the changelog and in the
release name if the author's scheme marks breaking changes.
