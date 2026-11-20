# Dora Profile review map

These checks require source or lifecycle context and are not enforced by the
Profile validator. `Required` means the author or reviewer must address the
check for a Dora policy bundle; it does not add a machine conformance rule.

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| D1 | Dora-specific claims were retrieved from the authoritative source path, using Second Brain first and deterministic search after a miss. | Required | [Retrieve before making claims](../SKILL.md#retrieve-before-making-claims) |
| D2 | Material derivations cite the original source with a followable `sources[].resource`; the source has not been copied solely for convenience. | Required | [Keep Dora's policies canonical](../SKILL.md#keep-doras-policies-canonical) |
| D3 | The concept distinguishes what the cited artifact says from what is independently known about current or external state. | Required | [Separate evidence from interpretation](../SKILL.md#separate-evidence-from-interpretation) |
| D4 | No stale or ambiguous lifecycle state is represented as completed, deleted, or resolved without the required evidence and owner-directed procedure. | Required | [Preserve ambiguous lifecycle state](../SKILL.md#preserve-ambiguous-lifecycle-state) |
| D5 | A material session event has a structured checkpoint with the required fields, and a checkpoint is not misrepresented as archive or closure. | Required | [Keep session continuity useful and bounded](../SKILL.md#keep-session-continuity-useful-and-bounded) |
| D6 | The bundle and review artifacts exclude raw transcripts, credentials, authentication material, and raw lead or customer personal data. | Required | [Keep session continuity useful and bounded](../SKILL.md#keep-session-continuity-useful-and-bounded) |
| P1 | A missing Dora procedure is cited as a gap rather than filled by an invented convention. | Permitted | [Review flow](../SKILL.md#review-flow) |
