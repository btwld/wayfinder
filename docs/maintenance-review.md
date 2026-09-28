# Repository maintenance review

Reviewed: 2026-09-09, against repository commit `8f38a8f` and the open issues and
pull requests at that time. This is a non-normative review; linked issues own work
status. No client corpus was inspected or copied for this review.

## Keep the layers, clarify their jobs

The repository already has the main parts needed to maintain an OKF-based project
memory. Keep the following responsibilities separate:

| Surface | Why it stays |
| --- | --- |
| [Profile](../profile/okf-profile.md) | Defines conformance of a bundle. New bundle conventions belong here. |
| [Implementation guide](../implementation/okf-implementation-guide.md) | Binds adoption, generation, validation, and migration behavior that the Profile leaves open. It is useful even where a tool is not implemented yet. |
| [Skills](../skills/README.md) | Distribute actionable instructions to agents. The authoring skill owns mechanics; adoption and assessment delegate. |
| [Validator](../packages/wayfinder/README.md) | Runs deterministic OKF and Profile checks. It cannot establish every contextual judgment. |
| [Compatibility review](compatibility-review.md) | Records whether Profile rules preserve the pinned OKF specification. |
| [Coverage matrix](../implementation/profile-coverage.md) | Records how each Profile rule is assessed. It answers a different question from compatibility. |
| [ADRs](adr/README.md), [examples](../examples/README.md), and [release tooling](../tool/) | Preserve design rationale, demonstrate bundle use, and distribute the implementation. |

`AGENTS.md` is contributor routing and working constraints. It does not replace
any of these sources or turn this repository into a project's knowledge bundle.

## Housekeeping applied

- **Contributor instructions:** shortened `AGENTS.md`, named the implementation
  guide consistently, added routing and contributor checks, and preserved the
  authority chain, generic scope, release safeguards, and client-data boundary.
  Clarified that existing authorization does not need to be requested again.
- **Repository orientation:** the README explains shared project memory and maps
  the validator, tooling, and supporting docs as well as the Profile and skills.
  It distinguishes shipped capabilities from the proposed artifact workflow.
- **Adoption:** removed unconditional reconfirmation, made existing-bundle
  preservation explicit, and added the validation and whole-bundle review already
  required by guide §2.3 and the canonical assessment reference. The generated
  agent instructions now delegate detailed rules instead of repeating them.
- **Mirroring:** the skill now preserves the optional `raw/` tier in Profile §3.4,
  and the "once cited" snapshot condition in §12. It distinguishes the validator's
  placement/Markdown checks from evidence of byte fidelity to an original.
- **Trust and optional guidance:** the authoring reference now distinguishes
  meaningful content production from verification (Profile §6.2; OKF §5.2), keeps
  a shared subject-assessment vocabulary optional (§6.3.1), and preserves the
  recommendation for a single outcome to link directly to its source (§4.3).
  The atomic-write summary no longer implies formatting-only edits need log entries
  (§10).

These changes repair routing and teaching against existing rules. They do not
change the Profile release, implementation contracts, validator, or seed schema.
The follow-up [skill evaluation](skill-evaluation.md) exercises all three skills
on synthetic repositories and records the additional corrections and limits.

## Pending work and decisions

| Topic | Evidence and next action |
| --- | --- |
| Profile index generation and MCP writes | Guide §3 has a generator contract; the current `okfp` CLI implements validation only. [#45](https://github.com/conceptadev/wayfinder/issues/45) proposes Profile-aware MCP writes and identifies the projection/transaction design choice. Resolve that seam before adding write commands. |
| Installation and distribution | [#53](https://github.com/conceptadev/wayfinder/issues/53) and [PR #54](https://github.com/conceptadev/wayfinder/pull/54) cover installation without Dart, plugin packaging, and release distribution. Continue that work there; the housekeeping change does not add a competing installer or manifest. |
| One consumer validation entry point | [#52](https://github.com/conceptadev/wayfinder/issues/52) asks about format/index checks alongside validation. The existing semantic gate differs from a generic index generator's rendering. Do not advertise a generic reindex as satisfying Profile §9 without validating the resulting projection. |
| Generic Profile platform | [#17](https://github.com/conceptadev/wayfinder/issues/17) remains an exploration with explicit evidence triggers. A second-brain workflow does not by itself justify a generic provider platform. |
| Migration review policy | Guide §5.4 says "one slice per working session" and requires a person to read the area index, while the canonical Profile assessment supports human or agent review. Decide whether the human-only migration checkpoint remains intentional before changing this implementation contract. |
| Release terminology | The Profile header says "Proposed" and "current release"; §15.3 describes publication. Reconcile publication status against the release record before changing those declarations or publishing another convention release. |
| Cross-bundle references | Guide §7 defers a dedicated mechanism pending a second bundle. Confirm whether multiple live bundles now supply the missing design evidence; ordinary URLs remain the documented approach. |
| Dependency updates | Open automated PRs #48–#51 update CI actions and lints. Review them with their own CI results instead of folding version changes into document cleanup. |

## The second-brain workflow to explore

The intended loop is: capture evidence, interpret and connect it, reuse knowledge
and methods, produce an artifact, and retain any new durable findings.

OKF already provides concepts, provenance, links, and asset references. A project
can document reusable guidance and cite evidence without promoting every capture
or generated file into a knowledge concept. Template storage, script invocation,
output provenance, and retention need a concrete project experiment. They are not
new standard directories or frontmatter fields established by this review.

Use one real reusable template, one analysis grounded in evidence, and one generated
deliverable to test that loop. Evaluate where the editable template lives, how the
script consumes knowledge, how an output identifies its input revisions, and which
findings deserve promotion back into the bundle. Keep project artifacts in the
project; bring a generic, demonstrated gap back here for an issue and scoped PR.

## Verification

The housekeeping change passed Dart formatting and analysis, all 33 package tests,
the example automated gate, and validation of a fresh bundle generated from the five
literal seed templates. The initial housekeeping check resolved all 74 local Markdown links and anchors
in its changed documents; the follow-up evaluation checks the expanded surface. Skill discovery metadata is unchanged; shared skill schema
checks passed, with the existing Claude `disable-model-invocation` field checked
separately because the generic Codex checker does not recognize it.

These checks support the edits and the existing automated gate; they do not certify
the whole Profile or prove behavior across agent products. Release-tool code was
unchanged, so release packaging and cross-platform CI were not rerun locally.
