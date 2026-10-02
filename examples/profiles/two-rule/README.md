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
