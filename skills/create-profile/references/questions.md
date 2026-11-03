# The Profile questions

Every Profile settles its identity and answers the enforcement question. The
numbered questions are an optional checklist. The author ratifies each
answer. "The Profile says nothing here" is a valid answer to any checklist
question, and OKF then governs.

## Identity

Settle these before the enforcement question:

- **Id.** Lowercase kebab-case, at most 64 characters, not a reserved name.
  It becomes the finding namespace, the `wayfinder.json` key, and the skill
  name, so choose one that can last.
- **Release scheme.** How releases are named, and how a breaking change shows.
- **OKF release.** The one the Profile binds to (`implements`).
- **Parent.** Whether it builds on another Profile (`extends`), and at which
  revision.
- **Home.** The repository and path of the package, and the `docs` URL.

## What must a machine enforce, and what is judgment?

Ask this first. A good answer lists each requirement a machine should
check, in the author's words, with whether a violation fails the gate or
only asks for action. It lists separately the decisions that need a
person's context. Each enforced requirement becomes a rule, and each
decision becomes skill guidance with a review-map check. A Profile with
rules and no judgment needs no skill. Lands in: package rules; skill and
review map.

## Optional checklist

Offer these in any order; skipped questions mean “says nothing,” not an inferred
policy. Each row names useful answer content and its destination. “Package” is
`wayfinder-profile.json`; “review” is an id/force/guide check in the skill.

| # / Question | Useful answer | Destination |
| --- | --- | --- |
| 1. What earns a concept? | Durable knowledge vs activity; events/artifacts that never earn one alone. | Skill + review |
| 2. Separate outcome or embedded? | Lifecycle/ownership test and ambiguous-case default. | Skill + review |
| 3. When split? | Signals that justify splitting and those that do not (such as size alone). | Skill + review |
| 4. Are interactions concepts? | When calls/meetings/threads earn records, what they hold, treatment of a single durable outcome. | Skill + review; home in #8 |
| 5. Which types? | Meanings, project additions, tests between commonly confused neighbors. | Package types + declared-type rule; choice in skill/review |
| 6. Body shapes? | Starting headings; distinguish optional prompts from requirements. | Skill, or heading rule only if required |
| 7. Directory naming? | What names represent, forbidden names, minimum corpus, overview-page policy. | Skill + review; path rules for mechanical prohibitions |
| 8. Placement and required files? | Placement test, fixed homes/membership, root/directory files. | Skill + review; path rules and required/generated-file builtins |
| 9. Relationships? | Outward meaning, close-name distinctions, prohibited usage. | Package relationships/key/shape rules; choice in skill/review |
| 10. What stays outside? | Owning systems (issues/PRs/etc.) and links instead of copies. | Skill + review |
| 11. Provenance/trust? | Sources, truthful generated/verified actors, when stale_after is allowed. | Skill + review; mechanical shapes as rules/advisories |
| 12. OKF narrowing? | Required fields, statuses, tag meaning, added keys. | Rules + declared frontmatter keys; contextual meaning in skill |
| 13. Identity/lifecycle? | Slugs, dates, external identifiers, moves/freezing, retirement/deletion, log events. | Skill + review; mechanical path/log rules |
| 14. Mirroring? | When/where, medium policy, preserving originals. | Skill + review; mechanical placement rules |
| 15. Raw evidence? | Whether it exists, layout, intake record and citation pattern. | Skill + templates |
| 16. Review/escalation? | Check per judgment, required/recommended/permitted force, permitted cases and NEEDS HUMAN triggers. | Review map |
| 17. Adoption? | Binding, root templates, first log entry and agent instruction additions. | Skill adoption reference |
