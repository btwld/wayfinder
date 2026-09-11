---
type: Guide
title: Source paths
description: Cites sources inside and outside the bundle, some of which do not exist.
status: stable
generated: {by: process:fixture, at: 2026-08-22T00:00:00Z}
resource: ../nowhere/original.docx
sources:
  - id: in-bundle-missing
    resource: /missing.md
  - id: outside-missing
    resource: "../nowhere/2026 08 19 meeting.docx"
  - id: outside-present
    resource: ../conformant/profile.md
  - id: url
    resource: https://example.com/spec
  - id: descriptor
    resource: Client demo recording, 30 July 2026 — retained outside this repository
---

Five sources, three of which cannot be followed.[^in-bundle-missing] [^outside-missing] [^outside-present] [^url] [^descriptor]

[^in-bundle-missing]: Missing inside the bundle
[^outside-missing]: Missing outside the bundle
[^outside-present]: Present outside the bundle
[^url]: A URL
[^descriptor]: A scope descriptor
