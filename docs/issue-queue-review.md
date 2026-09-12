# Issue queue review

Reviewed: 2026-09-12, against repository commit `d25427d` and the live state of
[`conceptadev/wayfinder`](https://github.com/conceptadev/wayfinder),
[`conceptadev/okf`](https://github.com/conceptadev/okf),
[`conceptadev/homebrew-tap`](https://github.com/conceptadev/homebrew-tap) and pub.dev
at that time. This is a non-normative review; linked issues own work status. Nothing
was merged, closed or commented as part of it.

The review re-checks an earlier triage pass. Every claim below was confirmed against
an API response or a file in the tree; the corrections section records where the
earlier pass was wrong or has since gone stale.

## Confirmed

| Claim | Evidence |
| --- | --- |
| [#79](https://github.com/conceptadev/wayfinder/pull/79) merged | Merged 2026-09-12T01:53Z; `HEAD` is `d25427d`. |
| Wayfinder 0.0.4 and okf 0.5.0 shipped | `wayfinder-v0.0.4` published 2026-09-11T22:59Z with Linux, macOS arm64 and Windows archives plus `.sha256`. okf `0.5.0` published 2026-09-11T22:19Z. |
| okf 0.5.0 carries the timestamp work | Its changelog entry adopts OKF revision `62432a0`, adds `okf format --migrate-timestamps`, compares `stale_after` as an instant, and rejects impossible timestamps. |
| The `okf` pin is unraised | `okf: ^0.3.0` in `wayfinder`, `wayfinder_cli` and `wayfinder_embeddings`. A `^0.3.0` constraint does not admit 0.5.0, so the pin blocks the upgrade. |
| Profile on `main` is 2026.1 | `profile/okf-profile.md` declares version 2026.1 profiling OKF 0.2 exactly. |
| Issue states | Wayfinder open: [#87](https://github.com/conceptadev/wayfinder/issues/87), [#66](https://github.com/conceptadev/wayfinder/issues/66), [#53](https://github.com/conceptadev/wayfinder/issues/53), [#52](https://github.com/conceptadev/wayfinder/issues/52), [#45](https://github.com/conceptadev/wayfinder/issues/45), [#17](https://github.com/conceptadev/wayfinder/issues/17). okf open: [#58](https://github.com/conceptadev/okf/issues/58), [#43](https://github.com/conceptadev/okf/issues/43), [#35](https://github.com/conceptadev/okf/issues/35). |
| Closures | Wayfinder #78 closed as duplicate; #65 closed not-planned. okf #56, #57, #44 closed completed; okf [#33](https://github.com/conceptadev/okf/pull/33) closed unmerged. |
| okf #43 is real | `tool/ci/platforms.tsv` lists Linux x64/arm64 and macOS x64/arm64 only, and the 0.5.0 assets contain no Windows archive. Wayfinder ships its own Windows archive, so this blocks standalone `okf`, not Wayfinder's native install. |
| pub.dev state for #66 | `wayfinder` 0.0.1 and `wayfinder_embeddings` 0.0.1 (both 2026-09-11T03:13Z); `wayfinder_cli` 0.0.4 (2026-09-11T22:58Z). All three, and `okf`, are publisher `concepta.dev`. |
| The Homebrew checkbox on #53 is stale | Tap `Formula/wayfinder.rb` is still `version "0.0.1-dev.1"`, pointing at the `wayfinder-v0.0.1-dev.1` release assets, and #65 is closed not-planned. |
| okf #35 is not started | No `search-concepts` identifier exists anywhere in the okf repository. |
| Dependabot state | okf [#52](https://github.com/conceptadev/okf/pull/52) and [#53](https://github.com/conceptadev/okf/pull/53) all checks green and mergeable; [#54](https://github.com/conceptadev/okf/pull/54) failing. |

## Corrections

**Wayfinder has an open pull request.** [#88](https://github.com/conceptadev/wayfinder/pull/88),
"Propose local session memory and context services", is open as a draft and mergeable,
created 2026-09-12T02:32Z. The earlier pass reported no open Wayfinder PRs, which was
true before that PR existed.

**Post-merge CI for #79 has finished.** Run
[34666130421](https://github.com/conceptadev/wayfinder/actions/runs/34666130421) is
completed with conclusion `success`, not in progress.

**okf #54 fails more broadly than reported.** Four check runs fail — `Test`,
`Test on macos-latest`, `Test on windows-latest` and `SDK floor` — rather than a single
test. Its `mergeable` state is `MERGEABLE`; `UNSTABLE` is the separate merge-state
status, meaning mergeable with failing checks. The PR dates from 2026-09-10, before the
later merges, so a rebase is still the right first step before reading the failures.

**The spec-pin story needs restating before #87 is worked.** Three distinct SHAs are in
play, and the earlier pass collapsed them:

| Where | SHA | Repository |
| --- | --- | --- |
| Current pin, in `profile/okf-profile.md`, `skills/author-knowledge-bundle/` and the vendored `references/OKF-0.2.md` | `3fcbb9f` | `knowledge-catalog` |
| Target named in #87's plan | `62432a0` | `knowledge-catalog` |
| Canonical repository head carrying the same ISO-datetime change | `ad30107` | `open-knowledge-format` |

`62432a0` does not resolve in `open-knowledge-format` — it is a `knowledge-catalog`
commit (2026-08-21, from knowledge-catalog#323). The canonical repository landed the
equivalent change in its own head commit `ad30107` (2026-08-21, merging
`okf-iso-datetimes`). So "re-pin to `62432a0` on `open-knowledge-format`" is not a
reachable instruction. The re-pin onto the canonical repository comes from #78, which
was folded into #87 as a duplicate, but #87's body still says only "move the spec pin
to `62432a0`". #87 should be rewritten to name both moves and the SHA that actually
exists in each repository before the Profile 2026.2 work starts.

**okf #58's conformance target is available.** `open-knowledge-format` contains both
`bundles/` and `samples/` directories alongside `SPEC.md`, so the upstream sample
bundles can be vendored or asserted against directly.

## Standing

Nothing in either repository has airtight evidence for closing. The next coding work is
Wayfinder #87, gated on raising the `okf` pin; the next human work is #66, one pub.dev
administrative check on the `wayfinder_embeddings` automated-publishing trust, and the
non-Dart teammate walkthrough on #53, whose body should be rewritten to drop the
Homebrew checkbox. The okf leftovers are the Windows binary (#43), upstream conformance
(#58) and MCP identity (#35).
