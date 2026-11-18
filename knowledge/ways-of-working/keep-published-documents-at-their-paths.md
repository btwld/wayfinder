---
type: Decision
title: Keep published documents at their paths
description: The contract, the schemas, the user guides, package guides, Profile packages and skills stay where their readers' links point; `docs/` holds only the four user guides and the two schemas.
status: stable
generated: { by: claude-code/fable-5, at: "2026-11-18T13:53:00Z" }
sources:
  - resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/README.md#try-an-example
    title: README, "Try an example"
  - resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/AGENTS.md#authority-and-scope
    title: AGENTS.md, "Authority and scope"
---

# Decision

## A published document stays at its path

A document that a reader outside this checkout reaches by its path stays at
that path.

- The engine contract:
  [the guide](../../implementation/okf-implementation-guide.md) and the two
  schemas under [`docs/schemas/`](../../docs/schemas/wayfinder.schema.json).
  Each schema's `$id` is its URL, and every Profile package's `$schema` cites
  it.
- The four user guides: [install](../../docs/install.md),
  [configuration](../../docs/wayfinder-configuration.md),
  [queries](../../docs/queries.md) and [stability](../../docs/stability.md).
  Released binaries print the install guide's URL
  ([`update.dart`](../../packages/wayfinder_cli/lib/src/update.dart)), and
  [`use-wayfinder`](../../skills/use-wayfinder/SKILL.md) links the query guide.
- Each package's `README.md` and `CHANGELOG.md` under
  [`packages/`](../../packages/wayfinder/README.md), which pub.dev publishes.
- Profile packages under `profiles/`. Bitwild's `docs` URI and every help
  link of its findings point at
  [its README](../../profiles/bitwild/README.md).
- The [skill family](../../skills/README.md), which is installed as written,
  and the [examples](../../examples/README.md).
- [`README.md`](../../README.md) and [`AGENTS.md`](../../AGENTS.md).

## docs/ is for the four user guides and the two schemas

Nothing new lands under `docs/`. Knowledge about how Wayfinder is built,
decided and worked on is a concept under `knowledge/`.

## One concept owns the pointer to each staying document

A concept that needs a fact a staying document owns links the document and
does not restate it. One concept owns the pointer to each staying document.
This concept owns the pointers to `README.md` and `AGENTS.md`.

## The root bundle holds only Wayfinder's own knowledge

The root `knowledge/` is this repository's own bundle: its decisions, its
vocabulary and its ways of working. It holds no client data and no other
project's knowledge. A project's knowledge belongs in that project's bundle.
[`examples/bitwild`](../../examples/README.md) stays the illustrative project.

## A deleted path gets no stub

A document that moves into `knowledge/` is deleted at its old path in the same
change, with no forwarding stub. Every reader is repointed in that change.
`python3 tool/ci/verify-links.py` fails while a Markdown link, an anchor or a
URL of this repository's `main` still names the old path.

# Why

A link in a released binary, a published package page, an installed skill or
a package's `$schema` cannot be repaired after release. Keeping these
documents in place costs a `docs/` directory that survives with four guides
and two schemas. In exchange, the URLs that released binaries, installed
skills and `$schema` fields carry keep working.

A stub is one more document for its subject, and an unattended agent acts on
whichever single document it opens. Deleting without a stub costs a 404 for a
link on an already-published package page that names a deleted path.

# Rejected

- Moving the guide, the schemas and the user guides so that `docs/` and
  `implementation/` disappear. A reader gets one tree, at the price of the
  install URL that released binaries print, two schema `$id`s, and a rewrite
  of a configuration reference that restates the contract.
- A forwarding stub at each deleted path. It keeps a second document per
  subject for an agent to open in place of the owner.
- A rule that fails any new file under `docs/`. Prose holds the rule until
  the first violation shows that a check is needed.
