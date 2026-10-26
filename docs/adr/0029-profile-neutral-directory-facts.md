# ADR-0029: Keep directory policy in the Profile package

- Status: accepted
- Date: 2026-10-26
- Scope: neutral sibling-directory facts and explicit package-format migration
- Amends: [ADR-0015](0015-profile-rule-catalogs.md) and [ADR-0016](0016-independent-profile-packages.md)

## Context

Independent Profiles and Bitwild share the same parser and fact projection.
The shipped example workflows exercise both, while Bitwild's example and
structure fixture use mirrored-source directories. The projection nevertheless
hard-coded `interactions/` and `references/` as non-areas for every package's
`sibling_directory` fact. The fact was therefore already deciding part of
Bitwild's placement policy before an independent Profile could inspect it.

Simply deleting those exceptions would reinterpret existing format 2
packages. Keeping a legacy Profile-specific fact beside a new fact would
retain the policy leak and two meanings to maintain. No new rule or builtin
is needed: a package can express its own exception with the existing `path`
fact and schema keywords.

## Decision

Read package format 3 only. Refuse format 2 whole as `profile-unsupported`
before evaluating its rules. Keep `sibling_directory` a boolean with one
precise definition: the loaded file inventory represents a directory beside
the concept whose name is the concept filename without `.md`, regardless of
directory names. Do not add disk I/O for empty directories; this fact must
also work for an uncommitted in-memory candidate.

Move Bitwild's existing exceptions into its existing
`concept-area-name-collision` schema. Preserve the exact scope: top-level
`interactions/` and `references/` trees, including same-named root concepts,
not nested occurrences under another subject or similar prefixes. This is a
representation correction, not a new placement rule. Its unpublished 2026.3
revision keeps its release name, id, severity, message and findings. A
contract golden contrasts the neutral independent probe with that policy;
existing bundle report goldens remain unchanged.

All rules still receive the chain's and project's effective vocabulary
(ADR-0027). This format migration changes no inheritance behavior.

## Consequences

Every format 2 package must be deliberately migrated, even one that never
uses the changed fact. Its author reviews uses of `sibling_directory`, moves
any chosen exceptions into rules, declares format 3 and follows the package's
release process. A package whose own rules never use the fact needs no rule
changes, but its parents must also be migrated. The chain's verdicts stay
unchanged only when no rule in it uses the fact or every affected package
explicitly preserves its prior policy. Published package revisions must
never be rewritten in place.

Projects move source refs and any pinned parent refs to migrated revisions,
then refresh and commit locks and installed skills with `get` or `upgrade`.
An immutable old source ref cannot advance merely because `upgrade` ran.
Until migration, valid OKF remains valid, but its format 2 Profile is
`NOT ASSESSED` and the gate is `INCOMPLETE` (exit 2). An intentionally
unmigrated project can retain an engine that reads format 2. No historical
Profile snapshot, tag or OKF mechanism changes.
