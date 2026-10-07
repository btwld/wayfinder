## What this changes

## Linked issue
Closes #

## If this changes the engine contract
- [ ] ADR added or amended, and an entry in the implementation guide's §9 change record naming the sections and the driver
- [ ] Package `format` bumped if an existing package would read differently
- [ ] `create-profile` and its references updated

## If this changes a Profile
- [ ] Rule written in the package with `tests`, a golden that fires it, and a README heading with its rationale
- [ ] Changelog entry naming the rules, the driver, and the migration: does a bundle that passed still pass?
- [ ] Compatibility review row for each new or changed rule or declared key
- [ ] On publication, `release` bumped, the release tagged, and the superseded package snapshotted under `profiles/<name>/versions/`
- [ ] The Profile's skill grepped for the old rule. A skill teaching a withdrawn rule produces passing files that are wrong, and no validator catches it

## Checks
- [ ] Dart format, analysis, tests, and the shipped `wayfinder validate` example gate pass
- [ ] Nothing added that names a client, a domain, or a project's own vocabulary
- [ ] Precedence respected: OKF over the engine contract, the engine contract over each Profile package
- [ ] Scope not widened beyond the issue
