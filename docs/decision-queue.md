# Open documentation and implementation decisions

These are unresolved maintenance decisions, not Profile rules or accepted
ADRs. Maintainers own the next evidence review; do not silently settle an item
while condensing historical records. The source is the
[2026-09-09 maintenance review at `dfd46e1`](https://github.com/btwld/wayfinder/blob/dfd46e1/docs/maintenance-review.md),
which was a dated snapshot rather than current guidance.

| Decision | Current boundary | Evidence needed before changing it |
| --- | --- | --- |
| Human-only migration checkpoint | [Implementation guide §5.4](../implementation/okf-implementation-guide.md#54-slice-vertically-never-by-kind) asks a person to read the area index, while [Profile assessment](../skills/author-knowledge-bundle/references/profile-assessment.md) supports human or agent review. | Decide whether the human-only step is intentional, using a real migration review; then align the guide and skill without weakening contextual review. |
| `Proposed` versus current-release terminology | The [Profile header](../profile/okf-profile.md) and [§15.3 release record](../profile/okf-profile.md#153-change-record) serve different purposes. | Confirm publication status and the actual release process before changing either declaration or publishing another convention release. |
| Cross-bundle references | [Implementation guide §7](../implementation/okf-implementation-guide.md#7-cross-bundle-references) defers a dedicated mechanism; ordinary URLs remain available. | Check whether multiple live bundles now provide the missing design evidence; define a mechanism only through the Profile release process if the generic need is proven. |
