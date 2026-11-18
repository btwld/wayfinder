---
type: Guide
title: Change the engine contract
description: The same-change checklist for a contract change and the review an OKF release needs.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:32:44Z
sources:
  - id: contributing
    title: Contributing to Wayfinder
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/docs/contributing.md#engine-contract-changes
---

# Engine contract changes

A change to what a package is, how the engine reads or composes one, its
results, its diagnostics, or its builtins needs all of the following in the
same change:

1. An edit in place to the owning decision concept under
   [`knowledge/`](../index.md), plus one log entry. A new decision is a new concept.
   See [one living concept per subject](keep-one-living-concept-per-subject.md).
2. The guide's §9 change-record entry naming affected sections, the real-use
   driver, and the migration impact for implementations and packages.
3. A package `format` bump when an existing package would read differently.
   Never reinterpret an old package silently.
4. Updated schemas, goldens, and the generic skills that teach the contract.

An upstream OKF **specification** release requires an engine compatibility
review in [Engine compatibility with OKF](../architecture/engine-compatibility-with-okf.md) before
the engine reads it. An `okf` package release that changes what okf reports or
what its index generator writes needs a review row and a changelog entry that
names it as breaking for every Profile using `matches-generated`. Never claim
unreviewed compatibility.
