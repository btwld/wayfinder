# Profile assessment

Part of the `author-knowledge-bundle` skill; `SKILL.md`'s release dispatch
applies. This reference defines Profile Review for both scopes: the scoped
review that completes every atomic write, and the deliberate whole-bundle
assessment the `assess-knowledge-bundle` skill runs.

After a write or when asked for Profile Review, collect automated validation over
the whole bundle, then assess every contextual rule taught in this skill's
references for the supported release and review scope. Prefer an installed
`okfp validate knowledge`; `dart run okf_profile:okfp validate knowledge` is an
alternative when the repository has that Dart dependency. Reuse a result already
collected for the same unchanged tree; rerun after repairs. If neither command is
available, report `NOT RUN` and the reason. Unsupported or unreadable declarations
still allow collecting automated diagnostics, but do not authorize contextual
review under an assumed release.

The canonical assignment
audit is `implementation/profile-coverage.md` in the
[Wayfinder repository](https://github.com/conceptadev/wayfinder); the review
map below keeps this installed skill self-contained.
Routine review covers changed concepts and their directly affected placement,
indexes, relationships, and dependents. Adoption, release upgrades, migrations,
and structural reorganizations cover the whole bundle.

Use this compact review map to enumerate the contextual surface: structure and
placement (§§3, 9–10, 13); durable capture and concept boundaries (§4);
metadata, type fit, provenance, actor history, trust, lifecycle, and freshness
(§§5–6); relationship meaning, execution ownership, identity, moves, and
retirement (§§7–8); Profile declaration semantics (§11); and source mirroring
(§12). Mark a section not applicable only after checking it against the scope.

Complete the review autonomously when the required context is present and every
judgment is clear. Use `NEEDS HUMAN` for an ambiguous mandatory rule, apparent
Profile/OKF conflict, missing external context, or proposed exception. Fix clear
defects and review again. Emit this compact report in the interaction or pull
request, never as a blanket certificate inside the bundle:

```markdown
## Profile Review Report

- Profile: 2026.1 (OKF 0.2)
- Scope: <changed concepts and affected neighbors | whole bundle>
- Automated gate: <PASS | FAIL | UNSUPPORTED | NOT RUN — reason>
- Reviewed: <applicable Judgment Rule Profile sections, comma-separated>
- Outcome: <PASS | CHANGES REQUIRED | NEEDS HUMAN>
- Concerns: <none | compact actionable findings or uncertainty>
```

`Automated gate` is the CLI's combined state. When it is not `PASS`, name the
failing component in Concerns — OKF conformance, deterministic Profile
validation, or `BLOCKED BY OKF` — so the reader knows which bar failed.
Outcome `PASS` means every Judgment Rule in scope was assessed with sufficient
context; it does not replace or reinterpret the independent OKF or automated
Profile result.
