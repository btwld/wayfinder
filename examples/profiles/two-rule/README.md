# acme-notes

`acme-notes` is a complete Profile with two rules and no parent. It shows that
a Profile needs nothing from Bitwild: one `wayfinder-profile.json` holds its
identity, vocabulary and rules. [`examples/acme-notes/`](../../acme-notes/) is
a project that uses it.

The package also ships [`skill/`](skill/SKILL.md), the judgment its rules
cannot check. `wayfinder get` installs it into a project as
`.claude/skills/acme-notes/` and `.agents/skills/acme-notes/`, pinned to the
same commit as the rules.

Each rule id below is a heading, so a finding's `help_uri` lands on its rule.

### known-type

Every concept type MUST be declared. The Profile declares `Runbook`, and a
project can add its own types in `wayfinder.json`.

### index-current

Every `index.md` MUST equal okf's generated index. `wayfinder validate --fix`
writes the generated indexes.

## Interview answers

These are the author's ratified answers to the `create-profile` questions.
The package and skill above are their output.

- **Identity.** Id `acme-notes`, release `1.0`, OKF `0.2`, no parent. The
  package lives at `examples/profiles/two-rule` in
  `https://github.com/btwld/wayfinder`, and `docs` is this README at
  `https://github.com/btwld/wayfinder/blob/main/examples/profiles/two-rule/README.md`.
  It ships a skill.
- **Enforced or judgment.** A machine enforces two things, both as errors.
  Every concept type is declared, and every `index.md` equals okf's
  generated index. Whether a page is a Runbook, and how one is written, is
  judgment for the skill.
- **1 to 4. Capture, promotion, splitting, interaction records.** The
  Profile says nothing; OKF governs.
- **5. Types.** One type, `Runbook`: "Steps to operate a running system".
  Projects may add their own types. Every concept type must be declared, as
  an error. Write a Runbook for steps someone follows to operate a running
  system, such as restarting a service or rotating a credential. A page that
  explains why a system behaves as it does is not a Runbook.
- **6. Body shape.** A Runbook names the system and the trigger in its
  title, numbers its steps with a check for each, and holds one procedure.
  These are guidance, not rules.
- **7. Directory names.** The Profile says nothing.
- **8. Placement and required files.** Every `index.md` must equal okf's
  generated index, as an error. The root `index.md` is never reported as
  extra. No directory names are fixed.
- **9 to 15. Relationships, external records, provenance, metadata,
  identity, mirroring, raw evidence.** The Profile says nothing; OKF
  governs. It declares no tags, relationship names, or frontmatter keys.
- **16. Review.** Required: a Runbook holds steps someone follows to operate
  a running system. Recommended: the title, numbered steps with checks, and
  one procedure per page. No escalation cases beyond the generic ones.
- **17. Adoption.** A project binds the package by its Git source and path.
  The OKF root files need nothing extra, so the skill has no adoption
  reference.
