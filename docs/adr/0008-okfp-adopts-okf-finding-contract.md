# ADR-0008: Publish okf's finding report unchanged

- Status: accepted
- Date: 2026-08-26
- Scope: the validation report's OKF component and the grammar of Profile findings

## Context

OKF 0.2 reports conformance as ordered `OkfFinding` values in one
`OkfReport`, with namespaced identifiers and a two-tier error/advisory
severity. A load failure is a finding like any other. Reshaping that report
into a validator-specific form would lose okf's identifiers and severity
meanings and create a second, lossy wire contract.

## Decision

Publish okf's own report projection as the OKF component of every result.
Validate through okf, let okf decide OKF conformance, and never reinterpret a
severity or add a strict mode. OKF conformance is `PASS` exactly when okf
reports no error.

Profile findings speak the same grammar and canonical ordering. Each finding
id is `<profile-id>/<rule-slug>`, where the namespace is the id of the package
that declares the rule. Rule metadata, such as the package release and the
`help_uri`, comes from the package, never from fields added to okf's wire
format. The engine reports its own state as `wayfinder/<code>` diagnostics,
never as findings. SARIF 2.1.0 carries the same findings for code scanning.
The [engine contract §4.1](../../implementation/okf-implementation-guide.md#41-results-and-exit-codes)
holds the exact shape.

## Options considered

- Keeping a validator-specific report shape was rejected because it would
  lose okf's identifiers and severity semantics.
- Translating okf's report into a compatibility shape was rejected because it
  would create a second wire contract to keep in step.

## Consequences

A consumer of okf's finding contract reads the OKF component without knowing
Wayfinder. OKF advisories never fail the gate, and a Profile finding never
enters the OKF report.

## Reconsider when

The pinned okf report contract changes, or a consumer needs a representation
the separate Profile result and diagnostics cannot carry.
