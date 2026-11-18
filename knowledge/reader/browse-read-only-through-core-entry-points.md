---
type: Architecture Decision Record
title: Browse read-only through core entry points
description: Portable values behind `knowledge.dart`, bounded native browsing behind `project.dart`, and the rules for roots, hidden entries and capture reuse.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: decision-knowledge-entries
    title: Consolidated knowledge entries and model-free reader backends
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#consolidated-knowledge-entries-and-model-free-reader-backends
  - id: decision-desktop-browsing
    title: Desktop browsing maintenance
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#desktop-browsing-maintenance
---

# Decision

## Consolidated knowledge entries and model-free reader backends

Keep portable retained values, memory capture and lease mechanics behind core's browser-closed `knowledge.dart`, and native bounded read-only filesystem browsing behind `project.dart`, because import closures provide the platform boundary without two extra unpublished packages. Flutter owns widgets/controllers and preference/finding presentation; reader regression tests live in core and the portable closure is checked transitively in CI. The unpublished snapshot-validation conversion and capture-time external observations leave this change because they have no production caller; raw reads, byte revisions, grant/lifecycle safety, shared file classification and the native validator's optional external-lookup callback remain, with no Profile/OKF policy migration.

## Desktop browsing maintenance

For #180's desktop caller, reject file/symbolic project roots at open and exclude every dot-prefixed browsing entry before inspection, removing the unused hidden-entry option and finding-source field without changing OKF inventories or conformance. Native validation reserves `memory:` and authority-bearing `scheme://` roots for URI inputs, treating other colon-containing names as filesystem paths to avoid conflating POSIX names with URI schemes. Keep idle capture reuse until close because the host closes projects on worktree changes, accepting the retained capture and two-scan peak allocation.
