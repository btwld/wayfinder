---
type: Field Note
title: Advisory boundary
description: Exercises conformant recommendations and tolerated absences.
status: stable
sources:
  - {id: code-ref, resource: https://example.com/code}
  - {id: indented-ref, resource: https://example.com/indented}
---

An ordinary footnote is not source attribution.[^ordinary]
An indented definition is still valid attribution.[^indented-ref]

```markdown
# Relationships

- Depends on: [Example](/not-a-real-edge.md)
[^code-ref]
```

# Relationships

- Informed by: [Planned concept](planned.md)

[^ordinary]: This label is not a declared source ID.
  [^indented-ref]: A valid indented source-attribution definition.
