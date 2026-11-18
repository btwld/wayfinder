---
type: Guide
title: Change a Profile
description: The same-change checklist for a Bitwild rule or vocabulary change, stable paths, and the skill wording search.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:32:44Z
sources:
  - id: contributing
    title: Contributing to Wayfinder
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/docs/contributing.md#profile-changes
---

# Profile changes

A Profile changes through its own release process, in its package. For
Bitwild, a rule or vocabulary change needs all of the following in the same
change:

1. The rule in `wayfinder-profile.json`, with `tests` that pass and fail, and
   a golden fixture that fires it.
2. A `### <rule-id>` heading with its rationale in the README.
3. A [`CHANGELOG.md`](../../profiles/bitwild/CHANGELOG.md) entry naming the rules
   changed, the real-use driver, and migration impact in words: whether
   bundles that passed still pass, and what they must do if not.
4. A row in Bitwild's [compatibility review](../../profiles/bitwild/compatibility-review.md)
   for each new or changed rule or declared key.
5. When the release is published, a new `release` value, a tag that never
   moves, and an immutable snapshot of the superseded package under
   `profiles/bitwild/versions/`.

Keep canonical paths and symbols stable. A Profile's release lives in its
package's `release` field, and the engine's in its pubspec and changelog, not
in filenames or symbol names. Only immutable snapshots, including vendored
OKF, carry versions in their names.

When a rule changes, search that Profile's skill for the old wording, starting
with its adoption seed. A validator cannot detect a skill teaching withdrawn
judgment. Keep the generic skill family Profile-agnostic; update `create-profile`
and its references with engine-contract changes.
