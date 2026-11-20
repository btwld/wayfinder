# Adopt the Dora Profile

This seed binds a Dora project bundle to the Profile in the Wayfinder
repository. Replace `<immutable-commit>` with the full commit containing the
ratified package; do not use a moving branch for a durable binding.

```json
{
  "version": 1,
  "profiles": {
    "dora-profile": {
      "source": {
        "git": "https://github.com/btwld/wayfinder",
        "ref": "<immutable-commit>",
        "path": "profiles/dora"
      },
      "applies_to": ["./knowledge"]
    }
  }
}
```

The package extends `profiles/bitwild` at the same repository commit. The
project selects only `dora-profile`; it does not need to list Bitwild again.
Run `wayfinder get` from the project to resolve the chain, refresh the lock, and
install the skill under `.claude/skills/dora-profile/`.

Create the ordinary OKF root `index.md` and `log.md` required by the inherited
Profile. Generate the index with Wayfinder rather than hand-maintaining it.
Record the Profile adoption in the root log. Keep Dora policy documents at
their canonical paths outside the bundle. When bundle concepts derive from
them, cite the originals via `sources[].resource` and preserve normal OKF
resource semantics.

Use only vocabulary in the selected Bitwild chain and the project binding.
Do not add a Dora frontmatter key for confidence or copy Dora's vault-only
metadata into OKF concepts. This package adds review guidance but does not
change inherited machine findings.
