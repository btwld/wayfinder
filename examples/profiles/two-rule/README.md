# acme-notes

`acme-notes` is a complete Profile with two rules and no parent. It shows that
a Profile needs nothing from Bitwild: one `wayfinder-profile.json` holds its
identity, vocabulary and rules. [`examples/acme-notes/`](../../acme-notes/) is
a project that uses it.

Each rule id below is a heading, so a finding's `help_uri` lands on its rule.

### known-type

Every concept type MUST be declared. The Profile declares `Runbook`, and a
project can add its own types in `wayfinder.json`.

### index-current

Every `index.md` MUST equal okf's generated index. `wayfinder validate --fix`
writes the generated indexes.
