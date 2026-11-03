# Profile assessment

Shared flow for scoped atomic-write review and whole-bundle assessment.
Each installed Profile skill owns the checks, force and escalation cases.

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

Load `profile.chain[].id` skills root first per
[Load the Profile chain](../SKILL.md#load-the-profile-chain), and judge every
in-scope check in every review map. If configuration is missing/unusable, never
assume a Profile: retain the OKF result and diagnostics, report review not
performed under `Reviewed`, and use `NEEDS HUMAN`. A chain member without a skill
contributes no contextual checks; say so in the report.

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
