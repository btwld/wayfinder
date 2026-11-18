---
type: Decision
title: Ration hosted runners
description: Linux-only source tests, paused native distribution, zero jobs on a draft, heavy jobs skipped on a non-code diff, and the always-on knowledge job.
status: stable
generated:
  by: claude-code/fable-5
  at: 2026-11-18T14:32:44Z
sources:
  - id: contributing
    title: Contributing to Wayfinder
    resource: https://github.com/btwld/wayfinder/blob/e06df73055b1e20599a5aca3df4fd96ddee558e3/docs/contributing.md#hosted-runner-policy
---

# Decision

Source tests and native artifact verification currently run on Linux only to
limit compute usage; their macOS and Windows jobs are paused. Native
distribution is also paused because its release contract requires all three
platform archives; pub.dev publishing and Linux verification remain available.
The separate installer-script workflow checks PowerShell 7 and Windows
PowerShell 5.1 on installer pull requests. Public installer verification runs
automatically on Linux and supports manual macOS/Windows smoke tests against
the published release. These installer checks do not replace source tests or
verification of new native artifacts on those platforms.

Pull-request workflows use exactly `opened`, `synchronize`, `reopened`, and
`ready_for_review`. A draft pull request runs zero jobs: classification,
heavy work, light work, and the required check all stay skipped.
`ready_for_review` runs the suite once the pull request is ready. A ready
pull request whose diff is only non-code (documentation outside
`docs/schemas/`, readmes, licenses, issue and pull-request templates, and
non-build assets) skips the heavy jobs. The required check still runs and
succeeds. Schemas, examples, Profile skill text, version snapshots, and
test fixtures stay with the code jobs, because CI reads them.
The `knowledge` job is not classified: it runs on every ready pull request
and every push, because it is the only job that reads `knowledge/` and
Markdown links. It needs no model.
Classification, the required check, and POSIX installer lint use
`ubuntu-slim`. Package tests, native retrieval and the `knowledge` job stay
on `ubuntu-latest`.

No pull request schedules a `macos-*` runner. macOS and Windows public-install
coverage is the manual dispatch added in #170. The workflow selects that
runner only for `workflow_dispatch`.
