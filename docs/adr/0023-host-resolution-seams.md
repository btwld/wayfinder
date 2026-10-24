# ADR-0023: Give a host the resolution seams it runs

- Status: accepted
- Date: 2026-10-24
- Scope: package reads, Profile status, skill reads and writes, and which Git remote a refresh contacts; no Profile rule
- Amends: [ADR-0015](0015-profile-rule-catalogs.md) and [ADR-0018](0018-embeddable-libraries.md)

## Context

A host that embeds resolution needs to stop a package whose tests stall, to
learn a binding's state without parsing a message, and to run Git through its
own process layer. It also needs a skill read that stays on the paths it
checked. ADR-0015 and ADR-0018 stay as they were accepted; this record
carries the change.

## Decision

- `ProfilePackage.parseWithin` parses a package on its own isolate and kills
  it after `packageTimeout` (ten seconds). The package is
  `wayfinder/profile-timeout`, naming the rule whose tests were running. A
  parse that stops on another error is `profile-invalid`. No earlier verdict
  is reused. Validating a bundle's content is not bounded; a host that does
  not control that content runs it where the host can stop it.
- `status` reports each binding as data: a stable state, the locked chain,
  what the cache holds, and the skill directories. `plan(lockedOnly: true)`
  fetches only to obtain a locked commit and throws `lock-change-required`
  before Git when the lock would change. `plan(skills: false)` fills the
  cache and writes no skill directory. Library messages name no command.
  The remedy, when there is one, is data on the failure.
- A skill read uses the real paths it checked, opens only a regular file,
  and can stop after `maxBytes`. A marker that cannot be read counts as no
  marker. `ProfileSkills.write` throws `ProfileSkillDirectoriesException`
  for a directory with no marker for its id, including one that appears
  after the first check, the same type `get` throws. Roots already replaced
  stay replaced.
- A refresh runs `git remote update --prune origin`. `origin` is the remote
  the clone stored for the location the fetch policy approved. Another
  remote on the mirror is not contacted. A host may pass `GitProcessStarter`
  so its process layer starts that Git.

## Consequences

A hostile package fails `get` and selection instead of holding them.
Refreshing a mirror does not reach a remote the person did not approve.
A host words its own remedy from the failure's data.
