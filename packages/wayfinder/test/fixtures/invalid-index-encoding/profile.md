---
type: Knowledge Profile
title: Concepta OKF Profile
description: Declares the Concepta profile and OKF versions this bundle follows.
status: stable
timestamp: '2026-08-22T00:00:00Z'
resource: https://example.com/profile
tags: [governance]
generated: {by: process:fixture, at: 2026-08-22T00:00:00Z}
verified: {by: process:fixture, at: 2026-08-22T01:00:00Z}
stale_after: 2027-08-22T00:00:00Z
usage_window: {from: 2026-08-01T00:00:00Z, to: 2026-08-22T00:00:00Z}
runtime: dart
parameters: []
computation: https://example.com/computation
executor: {resource: https://example.com/executor, receipt: [result]}
attester: {resource: https://example.com/attester}
sources:
  - id: okf-reference
    resource: https://github.com/GoogleCloudPlatform/knowledge-catalog
    author: process:fixture
---

# Profile

```yaml
concepta_profile: "2026.1"
okf_version: "0.2"
```

The declaration remains an ordinary OKF concept.[^okf-reference]

# Relationships

* **Depends on**: [Type registry](/types.md)

[^okf-reference]: Open Knowledge Format reference implementation
