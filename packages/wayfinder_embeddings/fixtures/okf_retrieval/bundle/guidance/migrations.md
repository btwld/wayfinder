---
type: "Guideline"
title: "Database schema migrations"
---

Apply additive schema changes first. Remove an old column only after every deployed reader has stopped using it.
