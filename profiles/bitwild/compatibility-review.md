# Bitwild 2026.3 compatibility with OKF 0.2

Status: Complete for `bitwild-profile` 2026.3

This non-normative review applies the compatibility test of the
[engine contract](../../implementation/okf-implementation-guide.md#5-profile-packages)
to every rule, declared key, and vocabulary list in
[`wayfinder-profile.json`](wayfinder-profile.json). The OKF pin is
`open-knowledge-format` at `ad30107`. The package is authoritative over every
summary here. The engine's own review is
[`docs/compatibility-review.md`](../../docs/compatibility-review.md).

A row passes only when the rule uses only constructs OKF 0.2 permits, keeps
every OKF field's and reserved file's upstream meaning, leaves the OKF graph
uninterpreted, leaves the independent OKF result unchanged, and leaves the
bundle readable by a generic OKF consumer.

The skill under [`skill/`](skill/SKILL.md) is guidance, not conformance, so it
has no row. It follows the same limit: it narrows only when and how Bitwild
authors use an OKF mechanism, never what the mechanism means.

## Declared key and vocabulary

| Item | OKF basis | Result | Reasoning |
| --- | --- | --- | --- |
| Frontmatter key `relationships` | §4.1 permits additional producer keys; consumers must not reject them and should preserve them | Pass | OKF 0.2 defines no key of that name, so no OKF field gains a meaning, and the engine rejects any declared key okf defines. A generic consumer loads and preserves it as an unknown key, and OKF's graph reads no producer key. `sources` is deliberately not used, because its §5.1 meaning is derivation. An OKF release that defines `relationships` needs a new review. |
| `types`, including OKF §10's Attested Computation | §4.1 leaves types decentralized; §10 defines Attested Computation | Pass | The list is a producer-side declaration that never licenses a generic consumer to reject an unknown type. Attested Computation keeps its upstream fields and meaning. |
| `tags` | §4.1 keeps tags open topic strings | Pass | The closed list is producer policy. A generic consumer still accepts and preserves every tag string. |
| `relationships` names | §6.1 defines link targets | Pass | Each name labels one `relationships` entry. No OKF edge gains a type. |

## Rules

| Rule | OKF basis | Result | Reasoning |
| --- | --- | --- | --- |
| `okf-release-binding` | §12 permits the root `okf_version` marker | Pass | Requiring the marker the package binds to does not reinterpret it. |
| `configuration-legacy-registry` | §3.1 makes every non-reserved Markdown file an ordinary concept | Pass | Retiring three legacy registry concepts removes duplicate configuration and changes no OKF requirement. |
| `configured-tag-undeclared`, `configured-tag-duplicate` | §4.1 keeps tags open | Pass | Declared and unique tag values are producer policy. OKF reading of tags is unchanged. |
| `concept-baseline-fields` | §4.1 defines `type`, `title`, and `description`; §5.4 defines `status` | Pass | Requiring upstream fields that OKF makes recommended or optional narrows producers. Generic consumers read the same fields. |
| `frontmatter-fields-declared` | §4.1 permits producer keys and forbids consumers to reject unknown ones | Pass | Bitwild restricts its own output. The engine still loads the concept and keeps the key, and the OKF result is unchanged. |
| `status-value` | §5.4 defines `draft`, `stable`, and `deprecated` | Pass | The rule restates OKF's values and keeps their document-lifecycle meaning. |
| `generation-provenance-recommended` | §5.2 defines `generated` | Pass | An advisory recommends an upstream field and never changes the gate. Missing `generated` stays valid OKF. |
| `used-type-registered` | §4.1 permits any nonempty type | Pass | The rule checks producers against the declared types. Unknown types stay loadable for generic consumers. |
| `used-actor-registered` | §7 keeps actor IDs opaque | Pass | Lookup lives in project configuration. It changes no actor syntax, trust tier, or graph edge. |
| `source-entry-shape` | §5.1 makes `resource` required in a source entry; okf reports its absence as an advisory | Pass | The rule raises an upstream requirement to an error without changing its meaning. |
| `source-id-unique`, `source-attribution-join` | §5.1 defines source IDs and footnote joins | Pass | A footnote counts as attribution only when its label matches a source ID, so ordinary footnotes stay free-form body content. |
| `source-path-unresolved` | §6.2 defines path-valued fields; §11 forbids rejection for broken targets | Pass | An advisory that never changes the gate. |
| `relationship-shape`, `used-relationship-declared` | §4.1 permits the key; §6.1 defines link targets | Pass | The rule checks the shape and vocabulary of a Bitwild key. Targets resolve with OKF §6.1 rules. |
| `internal-link-bundle-relative`, `relationship-bundle-relative` | §6.1 recommends bundle-relative links | Pass | Advisories that repeat the upstream preference without prohibiting either form. |
| `internal-link-unresolved`, `relationship-unresolved` | §6.1 says a broken target is not malformed; §11 forbids rejection for it | Pass | Summary entries that keep the edge and never change the gate. |
| `raw-directory-placement`, `raw-directory-markdown` | §3.1 leaves organization to producers and makes only Markdown files concepts; §6.3 defines `references/` | Pass | Narrows where Bitwild keeps verbatim originals. Assets stay non-concepts, and the OKF result is unchanged. |
| `root-structure-files` | §3.1 reserves `index.md` and `log.md` | Pass | Requiring both reserved files keeps their meaning. |
| `root-index-lists-log` | §8 defines indexes | Pass | Narrows the content of the root index before the first concept exists. Index syntax is unchanged. |
| `concept-area-name-collision` | §3 permits both arrangements | Pass | An advisory asking for placement review. It prohibits nothing OKF permits. |
| `index-current` | §8 makes indexes optional and lets producers generate them | Pass | Requires the output of OKF's own reference generator. A stale index never changes the OKF result. |
| `log-entry-lead-word` | §9 defines date groups and conventional bold lead words | Pass | Requires a shape OKF already permits and leaves the lead-word vocabulary open. |

## Completion gate

Every rule id, the declared key, and every vocabulary list in the package has
a row, and every row passes. A release that adds or changes a rule or key adds
or changes its row in the same change.
