# Profile assessment

Part of the `author-knowledge-bundle` skill. This reference defines Profile
Review for both scopes: the scoped review that completes every atomic write,
and the deliberate whole-bundle assessment the `assess-knowledge-bundle`
skill runs. It owns the flow and the report. Each Profile skill in the
bundle's chain owns what to judge.

## Collect automated validation

Run validation over the whole bundle. Prefer an installed
`wayfinder validate knowledge --output json`;
`dart run wayfinder_cli:wayfinder validate knowledge --output json` works
when the repository has that Dart dependency. Reuse a result already
collected for the same unchanged tree, and rerun after repairs. If neither
command is available, record `NOT RUN` and the reason.

Record the OKF result, the Profile findings, the summary entries the
Profile reports as notes (`profile.summary`), the diagnostics, and the gate.
Never substitute a guess for a deterministic result.

## Load what to judge

Read `profile.chain[].id` from the JSON and load each Profile's installed
skill, root first, as the authoring skill's
[Load the Profile chain](../SKILL.md#load-the-profile-chain) describes.
Each Profile skill names its review map: the checks to judge, the force of
each, and its escalation cases. Judge every check in scope from every
chain member.

A missing, unreadable, or unresolved configuration still yields the OKF
result and the diagnostics, but it leaves no Profile to judge. Never review
under an assumed Profile. Emit the report anyway: `Gate` records the
collected result, `Reviewed` says contextual review was not performed, and
`Outcome` is `NEEDS HUMAN`. That is a configuration problem, not a judgment
failure.

## Scope

Routine review covers the changed concepts and their directly affected
placement, indexes, relationships, and dependents. Adoption, Profile or
release changes, migrations, and structural reorganizations cover the whole
bundle. A Profile's review map may say more about scope.

## Decide the outcome

Complete the review yourself when the context is present and every judgment
is clear. Fix clear defects within the requested scope, then review again.
Use `NEEDS HUMAN` for an ambiguous required check, an apparent conflict
between a Profile and OKF, missing external context, a proposed exception,
or any escalation case a Profile's review map names. When a review finds
both a clear required violation and an escalation case, the outcome is
`CHANGES REQUIRED`, and the escalation goes in `Concerns`.

## Report

Emit this report in the interaction or pull request, never as a certificate
inside the bundle:

```markdown
## Profile Review Report

- Profiles: <id release, for each chain member, root first> (OKF <okf_version of the root index>)
- Scope: <changed concepts and affected neighbors | whole bundle>
- Gate: <PASS | FAIL | INCOMPLETE | NOT RUN (reason)>
- Reviewed: <review-map sections judged, per Profile>
- Outcome: <PASS | CHANGES REQUIRED | NEEDS HUMAN>
- Concerns: <none | compact actionable findings or uncertainty, each with its check id>
```

The OKF release is the one the bundle declares, not the okf package version
the JSON reports as `engine.okf`. `Gate` is the gate the CLI derives. When it is not `PASS`, say in `Concerns`
whether OKF failed, a Profile finding is an error, or an error diagnostic
left the run `INCOMPLETE`, and name that diagnostic's id.

`Outcome` `PASS` means every check in scope was judged with enough context.
It does not replace or reinterpret the OKF result or the Profile findings.
A chain member that ships no skill contributes no checks; say so in
`Reviewed`.
