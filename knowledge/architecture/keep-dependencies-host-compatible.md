---
type: Architecture Decision Record
title: Keep dependencies compatible with hosts
description: Ack 2 and analyzer 13 are adopted for host compatibility, which moves ObjectBox to its 6 preview until the first stable 6 release.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: decision-ack-analyzer-objectbox
    title: Ack 2, analyzer 13 and ObjectBox 6 preview
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#ack-2-analyzer-13-and-objectbox-6-preview
---

# Decision

Adopt Ack 2 and analyzer 13 for host dependency compatibility. Supporting analyzer 13 in this workspace also moves the ObjectBox generator and its paired Dart and native runtime to 6 preview/beta. This accepts prerelease risk and requires ObjectBox 5 consumers to upgrade, while CLI knowledge indexes keep using plain-file generations. Exit: move the override, installer and manifest to the first stable ObjectBox 6 release, keeping every entity id and UID.
