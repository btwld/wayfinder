---
type: Architecture Decision Record
title: Express Profile rules as data
description: Rules are schemas over parsed facts or named builtins, facts carry no Profile's directory policy, the engine reads one package format, and generated output is pinned to the generator revision.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:23:07Z
sources:
  - id: adr-0015
    title: "ADR-0015: Profile rules are data"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#profile-rules-are-data-adr-0015-adr-0024
  - id: adr-0024
    title: "ADR-0024: Pin the generator revision, and relock offline"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#profile-rules-are-data-adr-0015-adr-0024
  - id: adr-0029
    title: "ADR-0029: Profile-owned directory policy"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#profile-owned-directory-policy-adr-0029
---

# Decision

## Profile rules are data

Represent Profile rules as schemas over parsed facts or named builtins, with engine-owned finding identity and messages the engine renders from Profile-supplied templates, so authors can change rules without a binary release; a fixture probe reproduced compiled findings and avoided the review/runtime cost of a new expression language.
This limits rules to shared facts/capabilities, requires engine releases for new ones and trusts source-provided regular expressions; bounded package parsing does not bound bundle assessment.
Pin generated-output assumptions to `okfIndexGeneratorRevision`, not the dependency release, so a generator change requires explicit compatibility/migration review under the [package contract](../../implementation/okf-implementation-guide.md#56-rules-and-builtins).

## Profile-owned directory policy

Read format 3 only, as a JSON integer, and derive `sibling_directory` from the loaded file inventory without directory-name exceptions, because hard-coded Bitwild exclusions leaked placement policy into independent Profiles and deleting them under format 2 would silently reinterpret packages. A non-integer format value is malformed, not a supported spelling of format 3.
Bitwild preserves its prior findings through its existing schema rule; every format 2 chain needs an explicit package migration or matching older engine, and valid OKF with an unmigrated Profile remains INCOMPLETE, as detailed in the [format and migration contract](../../implementation/okf-implementation-guide.md#54-identity-release-and-format).
