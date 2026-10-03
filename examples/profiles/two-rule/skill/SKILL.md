---
name: acme-notes
description: Judgment for knowledge bundles under the acme-notes Profile. Use when writing, placing, or reviewing a Runbook in a bundle whose wayfinder validate chain includes acme-notes.
---

# acme-notes

`wayfinder validate` already checks this Profile's two rules: every concept
type is declared, and every `index.md` is the generated index. This skill
covers what a validator cannot decide. Where it is silent, OKF governs.

## When a page is a Runbook

Write a Runbook for steps someone follows to operate a running system, such
as restarting a service or rotating a credential. A page that explains why a
system behaves as it does is not a Runbook, because no one runs it.

## Writing one

- Name the system and the trigger in the title, such as "Restart the API".
- Number the steps and give each one a check that tells the reader it worked.
- Keep one procedure per page; link related procedures instead of nesting them.

## After editing

Run `wayfinder validate <bundle> --fix` to regenerate the indexes, then
`wayfinder validate <bundle>` to confirm the gate passes.

## Review map

| ID | Check | Force | Guide |
| --- | --- | --- | --- |
| R1 | Every Runbook holds steps someone follows to operate a running system. | Required | [When a page is a Runbook](#when-a-page-is-a-runbook) |
| R2 | A Runbook's title names the system and the trigger. | Recommended | [Writing one](#writing-one) |
| R3 | Steps are numbered, and each has a check that it worked. | Recommended | [Writing one](#writing-one) |
| R4 | A Runbook holds one procedure and links related ones. | Recommended | [Writing one](#writing-one) |

A required check that fails makes the outcome `CHANGES REQUIRED`. The
generic escalation cases apply; this Profile adds none.
