# ADR-0020: Programmatic adoption as plan, then apply

- Status: accepted
- Date: 2026-10-22
- Scope: `package:wayfinder/adoption.dart`, the generic adoption seed, the configuration encoder and editor, and the resolver's fetch policy; no Profile rule and no change to results
- Builds on [ADR-0018](0018-embeddable-libraries.md)

## Context

Adoption (guide §2) was something only an agent could do: the
`adopt-knowledge-bundle` skill wrote `wayfinder.json` by hand from the
templates in its `SEEDING.md`, ran `wayfinder get`, seeded the bundle root
files and edited `AGENTS.md`. A host such as an IDE or an agent runtime that
sets up a project for a person needs the same result in process, with a
complete preview before anything changes and nothing half done when a step
fails. It also must not decide for the user how agents in the project are
configured.

## Decision

**Adoption is a plan, then an apply.** `KnowledgeAdoption.plan` reads the
project and resolves the requested Profile through the resolver's own plan
(ADR-0018) and writes nothing in the project. The plan lists every file
applying writes, with its text or, for a Profile skill file, its digest;
every Git fetch, which planning made into the Profile cache and applying
never repeats; the Profile's source, release, commit and chain; the skill
directories it installs or replaces; and the conflicts that stop it. It also
validates the bundle as applying will leave it, so the gate is known before
any write. `KnowledgeAdoption.apply` refuses a plan with a conflict, one made
with another Profile cache, or one whose project files, bundle, skill
directories or cached package files changed since planning, before writing
anything. It then writes the seeded bundle (staged as a hidden sibling and
renamed into place), `wayfinder.json`, the lock and the skills through the
resolver, the `.gitignore` line, and finally runs the host's own step if
the host gives one, reporting each step and checking the host's
cancellation before each. When a step fails, it undoes the earlier ones in
reverse, restoring a replaced skill directory, so the project holds no
partial bundle; a step whose undo also fails is reported `undo-failed`.
Validation runs last and undoes nothing: a gate other than `PASS` leaves
adoption incomplete (guide §2.3).

**Applying holds the project as `get` does.** From the check step until
every step has finished or been undone, `apply` holds the resolver's
`projects/<sha256(root)>.get.lock` (ADR-0018), and writes the lock and
skills under that hold rather than through `WayfinderProfileResolver.apply`,
whose lock does not nest. A `get`, or another adoption, that holds the
project stops adoption at the check step with `resolution-busy`, before
anything is written; one that starts while adoption applies is refused the
same way. So an undo never removes what a concurrent `get` wrote, and no
separate adoption lock exists. A replaced skill directory waits beside the
new one under the name an interrupted `get` gives its copies, so a `get`
after a crash removes it.

**The host approves each fetch.** A chain reaches a parent's source only
once it has read the child's package, so no plan can list every source
before it fetches. Each clone or refresh goes through the request's fetch
policy first, the named source and every parent alike, including a parent
in another repository that the configuration never names; an offline
request refuses them all and reads the cache as it is. A refused fetch
stops planning with `ProfileFetchRequiredException` (`fetch-required`),
which names it, before it runs. A host asks the person about the named
source before planning, then about each fetch a refusal names, and plans
again with it allowed; what the person declines is never fetched.

**The binding pins what it resolved.** A request without a ref binds the
source's default branch as the commit it resolves to, so the binding moves
only when someone changes it. A request with a ref keeps that ref, and the
lock pins its commit.

**Adoption writes only Wayfinder's files.** It writes `wayfinder.json`,
`wayfinder.lock`, the bundle, the Profile skills under `.claude/skills/<id>`
and `.agents/skills/<id>`, and by default a `<bundle>/.okf.lock` line in
`.gitignore` unless `.gitignore` already lists it, because okf keeps its
lock file inside the bundle. It never
writes `AGENTS.md`, `CLAUDE.md`, `.mcp.json` or Git hooks. The plan returns
the `### Knowledge bundle` block, with the lines the Profile's adoption
guidance adds, for the host to place; the host step lets a host write it
inside the same undo. A skill directory without the `.wayfinder-profile`
marker is a conflict, as it is for `get`. So is a marked skill directory the
adoption does not install: the next `get` would delete it, and adoption
deletes nothing.

**The generic seed is code.** `KnowledgeSeeds` holds the project binding,
OKF's root files and the agent-instruction blocks that `SEEDING.md` showed.
`SEEDING.md` still shows them, and a test keeps the two equal. Adoption
seeds only what the request names: the root files, and seed concepts the
host derives from the project and passes as text, with the project
vocabulary they use. With a concept, every index is what the chain's
generated-index rules expect, as `validate --fix` writes it. Adoption never
invents a concept. An existing bundle can be bound instead of seeded when it
passes OKF; nothing is written in it. A bundle directory that holds only
okf's `.okf.lock` counts as empty, and the lock file stays.

**`wayfinder.json` has one writer's format.** `WayfinderProjectConfig.toJson`
and `WayfinderConfigEncoder` write the layout the documentation shows, and
`WayfinderConfigEditor` makes structured edits (a Profile's source and
bundles, project vocabulary, actors) that keep every field it does not
model and every value as written.

## Consequences

A host can show a person exactly what adoption changes, ask once, and
apply it. Consent to fetch is per source: a chain whose parent lives in
another repository asks twice. A failed adoption leaves the project as it
was, apart from Profile cache entries outside it. Because agent
configuration stays the host's choice, a project adopted through the library
still needs its `AGENTS.md` paragraph (guide §2.1) before adoption is done,
which the host step can write; the skill path keeps writing it, and
`wayfinder setup --hooks` stays a separate, explicit step.

Changing an existing binding, its Profile or its release remains migration
work: `wayfinder.json` or `wayfinder.lock` in the project is a conflict.
Registering an actor later is an edit with `WayfinderConfigEditor` followed
by `wayfinder get`, which reuses the locked commit without fetching.

## Reconsider when

Profiles ship machine-readable adoption seeds, or a host needs adoption to
change a binding that already exists.
