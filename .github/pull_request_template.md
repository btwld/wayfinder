## What this changes

## Linked issue
Closes #

## If this changes the profile
- [ ] Rule written as an explicit MUST / MUST NOT / SHOULD / SHOULD NOT / MAY
- [ ] Row added to the change record (profile §15.3) naming the sections and the driver
- [ ] Migration stated in words: does an existing conformant bundle stay conformant?
- [ ] Version bumped to `<year>.<serial>`, and the superseded release snapshotted under `profile/versions/`

## If this changes a rule the skills restate
- [ ] `skills/` grepped for the old rule — a skill teaching a withdrawn rule produces conforming files that are wrong, and no validator catches it

## Checks
- [ ] `python3 tools/verify_knowledge_bundle.py --strict examples` passes
- [ ] Nothing added that names a client, a domain, or a project's own vocabulary
- [ ] Precedence respected: OKF over the profile, the profile over the implementation guide
- [ ] Scope not widened beyond the issue
