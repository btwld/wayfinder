# Spec: Share an artifact with specific people (EXAMPLE)

Status: Approved (example)
Owner (product): Anne   Author: Anne   Date: 2026-07-06
Rolls up to: O4 Dogfood until market validation

## Problem / why
An owner needs to share one artifact with named people without exposing the whole org.

## Scope (minimum viable)
In: share a single artifact by name or email, or with an organization.
Out: public links, per-user data filtering within a shared connection (roadmap).

## User stories
As an artifact owner, I want to share one artifact with selected people, so that they see
only what that artifact shows.

## Behavior (BDD)
Given I own an artifact, when I add a person by email, then they can open that artifact and
nothing else in the organization.

## Negative paths
Unknown email, revoked access, a failing MCP behind the artifact (show a clear error, not a
blank page).

## Acceptance criteria
- [ ] Owner can add and remove a person on a single artifact.
- [ ] Shared user sees only that artifact.
- [ ] Credentials never reach the browser.

## Links
Decision Log: <link>   Issues: <links>   ADRs: docs/adr/0001-example-...
