# Engine compatibility with OKF 0.2

Status: Complete for package format 2, `okf` 0.5.0, and OKF 0.2

This non-normative review records whether the wayfinder engine keeps the
pinned OKF 0.2 contract intact. The specification pin is
`open-knowledge-format` at `ad30107`, vendored in
[`OKF-0.2.md`](../skills/author-knowledge-bundle/references/OKF-0.2.md). The
`okf` package pin is `>=0.5.0 <0.5.1`. The
[engine contract](../implementation/okf-implementation-guide.md) is
authoritative over every summary here.

This review covers the engine only. Each Profile reviews its own rules and
declared keys against OKF in its own release records (guide §5.10). Bitwild's
review is [`profiles/bitwild/compatibility-review.md`](../profiles/bitwild/compatibility-review.md).

## Compatibility test

An engine behavior passes only when all four answers are yes:

1. Does okf's own report reach the user unchanged?
2. Does every OKF field, reserved file, and graph edge keep its upstream meaning?
3. Does a bundle that is valid OKF stay loadable whatever Profile a project selects?
4. Does the engine add nothing to a bundle that a generic OKF consumer would have to understand?

## Engine review

| Engine behavior | OKF basis | Result | Reasoning |
| --- | --- | --- | --- |
| Runs okf's validation first and reports its findings in okf's own projection; OKF conformance is `PASS` exactly when okf reports no error | §11 defines OKF conformance and its rejection conditions | Pass | The engine judges okf's report non-strictly and never reclassifies a finding, so an OKF advisory never fails OKF conformance and a Profile finding never enters the OKF report. |
| Runs no Profile rule when OKF fails (`BLOCKED BY OKF`) | §11 | Pass | A Profile never reports on content OKF rejected, so its findings cannot be read as OKF findings. |
| Reports Profile findings in the package's namespace and engine diagnostics as `wayfinder/*` | §11 fixes only OKF's own result | Pass | Neither namespace is `okf/*`, so a consumer of okf's finding contract (ADR-0008) sees okf's findings alone. |
| Rejects a package that declares a key OKF 0.2 defines, using the key list of the pinned `okf` package | §4.1 permits additional producer keys | Pass | A Profile can add a key OKF permits but can never redeclare an OKF field. Whether a declared key gives an OKF field another meaning is each Profile's review. |
| Reads a `relationships` entry as a typed edge beside the OKF graph, resolved as OKF resolves a link target | §§4.1 and 6.1 | Pass | The engine adds edges under its own key and never changes OKF's nodes, edges, or their meanings. A generic consumer reads `relationships` as an unknown key and preserves it. |
| `matches-generated` with `generator: "okf-index"` compares indexes with `OkfIndexGenerator` output, and `--fix` writes only that output | §8 defines indexes and lets producers generate them | Pass | The engine uses OKF's own reference generator and writes only reserved `index.md` files whose bytes differ. A missing or stale index never changes the OKF result. |
| Reads `okf_version` from the root index and checks each package's `implements.release` against the OKF releases okf can read | §12 | Pass | The engine reads the marker with its upstream meaning and never writes it outside a generated index. |
| `graph`, `index`, and `search` read the explicit bundle without resolving Profile sources | §11 tolerant reading | Pass | A broken or absent Profile selection never makes ordinary OKF reading fail. |
| Keeps `wayfinder.json`, `wayfinder.lock`, and installed skills outside the bundle | §3.1 reserves `index.md` and `log.md` and makes every other Markdown file a concept | Pass | Project configuration never becomes a concept, frontmatter, or an index entry. |
| Never probes the network during validation | §11 does not make network resolution a rejection condition | Pass | An external resource that no longer resolves stays ordinary provenance or a body link. |

## When to redo this review

An upstream OKF specification release needs a new review before the engine
reads it, even when no engine behavior otherwise changes. An `okf` package
release needs a review row when it changes what okf reports, which keys it
defines, or what its index generator writes. The engine reports the `okf`
version it ran as `engine.okf`, and a generator change is a breaking engine
change (guide §5.6).

## Completion gate

Every engine behavior that reads, writes, or reports on a bundle has a row,
and every row passes the four-part test. No behavior passes by silence.
