---
type: Architecture Decision Record
title: Expose embeddable libraries and leave resources to the host
description: Project and retrieval behavior are public libraries with injected resources, bounded roots, typed failures and host-owned lifecycle.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:28:19Z
sources:
  - id: adr-0018
    title: "ADR-0018: Embeddable project and retrieval libraries"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#embeddable-libraries-and-host-ownership-adr-0018-adr-0023
  - id: adr-0023
    title: "ADR-0023: Give a host the resolution seams it runs"
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/ARCHITECTURE.md#embeddable-libraries-and-host-ownership-adr-0018-adr-0023
---

# Decision

Expose project and retrieval behavior as public libraries so IDE/agent hosts need no CLI internals, with injected resources, bounded project roots, typed failures, hardened origin-only Git and checked skill paths.
Hosts pay for resource lifecycle, fetch consent and serialization: all okf bundle I/O in one process stays on one isolate because its process-owned locks do not exclude isolates, while Wayfinder uses descriptor-owned locks on local disk.
Package parsing normally has a ten-second isolate bound but falls back to unbounded synchronous parsing when spawning fails; hosts needing hard bounds must isolate work themselves, as detailed in [host operating boundaries](../../packages/wayfinder/README.md#host-operating-boundaries).
