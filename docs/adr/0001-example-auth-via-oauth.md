# ADR 0001: Platform auth via OAuth, not shared VPN (EXAMPLE)

Status: Accepted (example)
Date: 2026-07-06   Deciders: Anne, Kauan

## Context
Sharing artifacts with client users over a shared VPN does not scale and mixes trust
boundaries. We need enterprise-standard auth without hosting client data.

## Decision
Use OAuth for the platform and MCP connections. Read client data live and read-only; store
nothing of the client's.

## Consequences
Easier: safe cross-org sharing, enterprise standard. Harder: an extra confirm window on
login. Follow-up: migrate the Rockets auth module once beta-ready.

## Alternatives considered
Shared VPN (does not scale, blurs trust); hosting client data (liability, rejected).
