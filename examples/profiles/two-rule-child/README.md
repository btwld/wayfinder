# acme-bitwild

`acme-bitwild` builds on Bitwild. Its package names the parent itself:

```json
"extends": {"path": "profiles/bitwild"}
```

A parent without `git` is the package at that path in the same repository at
the same commit as this one. Both packages live in this repository, so a
project that resolves `examples/profiles/two-rule-child` at any ref gets the
Bitwild package from that same commit. The project's `wayfinder.json` names
only `acme-bitwild`; it never wires the chain.

The package adds the tag `billing` and two rules, reported in its own
namespace after every Bitwild rule. It cannot change a Bitwild rule.

Each rule id below is a heading, so a finding's `help_uri` lands on its rule.

### title-without-period

A concept title MUST NOT end with a period.

### request-tagged

A Request MUST carry at least one tag.
