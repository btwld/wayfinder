# ADR-0025: Give a host the adoption seams it runs

- Status: accepted
- Date: 2026-10-24
- Scope: how adoption binds a package, judges the bundle, and checks a host's own files; no Profile rule
- Amends: [ADR-0019](0019-profile-aware-writes.md) and [ADR-0020](0020-programmatic-adoption.md)

## Context

ADR-0019 and ADR-0020 stay as they were accepted. A host that sets a
project up needs a few seams those records do not give it. This record
carries them.

## Decision

- The binding is keyed by the id the package declares, read at the commit
  adoption resolves, before the chain resolves. A request may leave the id
  out. A request that names another id is `adoption-profile-conflict`, and
  nothing is written.
- Adoption takes the same `KnowledgeAssessor` as `KnowledgeWriter`, with an
  input that holds the one bundle and no base. `assessWithin` runs that
  assessment on an isolate and kills it at a timeout or when cancelled.
  Generating the seed's indexes stays on the calling isolate.
- A host names the files its step writes, such as `AGENTS.md`, as host
  inputs. The plan digests them with the files adoption writes, and the
  check step refuses a changed path as `adoption-stale` before anything is
  written. A `..` segment in the path as given is `adoption-invalid`. The
  check does not remove it first: a symlink earlier in the path can make
  `..` leave the project. A host input then counts with the file its
  symlinks resolve to. One that resolves outside the project, to the
  project directory, or into `.git` is `adoption-invalid`.
- `apply` reports each step as it starts and as it ends. A listener that
  throws while a step starts or ends fails that step. What it throws while
  a failure is reported is ignored, and so is what it throws for the host
  step's `done`, because those writes are already in place.

## Consequences

A host can adopt a Profile without knowing its id, bound the Profile's
rules, and keep its own files in the same staleness check. A path with
`..` is refused before any symlink is followed.
