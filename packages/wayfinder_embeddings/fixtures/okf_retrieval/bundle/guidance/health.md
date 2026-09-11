---
type: "Guideline"
title: "Readiness versus liveness"
---

# Readiness

Return failure while required dependencies are unavailable so traffic is withheld.

# Liveness

Return failure only when the process cannot recover without restarting.
