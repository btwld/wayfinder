# Profile assessment

Part of the `author-knowledge-bundle` skill; `SKILL.md`'s release dispatch
applies. This reference defines Profile Review for both scopes: the scoped
review that completes every atomic write, and the deliberate whole-bundle
assessment the `assess-knowledge-bundle` skill runs.

After a write or when asked for Profile Review, collect automated validation over
the whole bundle, then assess every contextual rule taught in this skill's
references for the supported release and review scope. Prefer an installed
`wayfinder validate knowledge`; `dart run wayfinder_cli:wayfinder validate knowledge` is an
alternative when the repository has that Dart dependency. Reuse a result already
collected for the same unchanged tree; rerun after repairs. If neither command is
available, report `NOT RUN` and the reason. A missing, unreadable, or unsupported
configuration still allows collecting automated diagnostics, but do not authorize contextual
review under an assumed release. Still emit the compact report below: Automated
gate records the collected result, Reviewed notes that contextual review was not
performed, and Outcome is `NEEDS HUMAN`. That is a capability or configuration
problem, not a judgment failure.

The canonical assignment
audit is `implementation/profile-coverage.md` in the
[Wayfinder repository](https://github.com/btwld/wayfinder); the review
map below keeps this installed skill self-contained.
Routine review covers changed concepts and their directly affected placement,
indexes, relationships, and dependents. Adoption, release upgrades, migrations,
and structural reorganizations cover the whole bundle.

Use this compact review map to enumerate the contextual surface: structure and
placement (§§3, 9–10, 13); durable capture and concept boundaries (§4);
metadata, type fit, provenance, actor lookup, trust, lifecycle, and freshness
(§§5–6); relationship meaning, execution ownership, identity, moves, and
retirement (§§7–8); Profile binding semantics (§11); and source mirroring
(§12). Mark a section not applicable only after checking it against the scope.

Complete the review autonomously when the required context is present and every
judgment is clear. Use `NEEDS HUMAN` for an ambiguous mandatory rule, apparent
Profile/OKF conflict, missing external context, or proposed exception. Fix clear
defects and review again. Emit this compact report in the interaction or pull
request, never as a blanket certificate inside the bundle:

```markdown
## Profile Review Report

- Profile: <2026.3> (OKF 0.2)
- Scope: <changed concepts and affected neighbors | whole bundle>
- Gate: <PASS | FAIL | INCOMPLETE | NOT RUN (reason)>
- Reviewed: <applicable Judgment Rule Profile sections, comma-separated>
- Outcome: <PASS | CHANGES REQUIRED | NEEDS HUMAN>
- Concerns: <none | compact actionable findings or uncertainty>
```

`Gate` is the gate the CLI derives. When it is not `PASS`, say in Concerns
whether OKF failed, a Profile finding is an error, or an error diagnostic left
the run `INCOMPLETE`, and name that diagnostic's id, so the reader knows which
bar failed.
Outcome `PASS` means every Judgment Rule in scope was assessed with sufficient
context; it does not replace or reinterpret the independent OKF or automated
Profile result.
