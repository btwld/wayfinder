# Unreleased

- The engine selects a Profile only through `wayfinder.json`.
  The 2026.2 dispatch through an in-bundle `profile.md` declaration is gone,
  with its `types.md` and `actors.md` registry readers and its index
  projection. A bundle with no `wayfinder.json` above it is `NOT ASSESSED`
  with `wayfinder/config-missing` and gate `INCOMPLETE`, whatever its root
  files say, and `--fix` writes nothing there. A `profile.md` no longer
  exempts a bundle from `wayfinder/config-invalid` or
  `wayfinder/bundle-unbound`. The 19 builtins frozen for 2026.2, the
  builtins' `installedOnlyIn` restriction, `tag-literal-duplication` (dead
  since 2026.3 checks tag collisions while reading the binding), and the
  2026.2-only `reserved` param of `root-structure-files` are deleted, as are
  `LegacyRegistries`, `EffectiveProfile.legacyDispatch`,
  `Vocabulary.standardTypes`, `legacyProfileRelease`, and
  `legacyStandardTypes`. Only `profile/wayfinder-profile.json` and
  `profile/wayfinder-rules.json` are embedded, and the `yaml` dependency is
  dropped. A 2026.2 bundle keeps validating on wayfinder 0.1.x, or migrates
  to a `wayfinder.json` binding.
- The engine reports on its own run as `EngineDiagnostic`s, a closed set of
  `wayfinder/*` codes with a level, instead of dressing them as Profile
  findings. Release dispatch problems (`DispatchRule` is gone), the
  `link-graph-unavailable` and `configured-type-extension` catalog rules and
  their builtins, and `--fix` failure or refusal (`ProfileFix` is gone)
  become diagnostics. `ProfileValidationResult` holds a sealed
  `ProfileAssessment` (`Assessed`, `BlockedByOkf`, `NotAssessed`) and derives
  `gate`: `FAIL` when OKF fails or a finding is an error, else `INCOMPLETE`
  when a diagnostic is an error, else `PASS`, exiting 0, 1 or 2. JSON gains
  `diagnostics` and `gate` and loses `judgment_rules` and `automated_gate`;
  `fix` is `{written}`. Profile state `UNSUPPORTED` becomes `NOT ASSESSED`.
  SARIF reports diagnostics as invocation notifications with
  `driver.notifications` descriptors, and `executionSuccessful` is false only
  for an error diagnostic. `internalErrorJson` and `internalErrorSarif`
  describe a run that stopped. A link graph that cannot be built now makes
  the gate `INCOMPLETE` rather than `FAIL`. `ProfileValidator` takes a
  `buildGraph` function so a test can force that path.
- `index-current` and `validate --fix` compare an index with CRLF line
  endings, as a Windows checkout writes it, equal to the generated LF text,
  so neither reports nor rewrites it.
- `validate --fix` replaces each generated index atomically, refuses a
  symbolic link at any path segment, and reports a failed write with the
  files already written. SARIF locations inside the working directory
  are relative to a recorded `WORKINGDIR` base, and summary results carry
  level `none`.
- The 2026.2 dispatch parses `types.md` and `actors.md` once and shares
  them with the engine through `EffectiveProfile.legacyDispatch`, which
  replaces `declaration`. `ProfileFinding` takes a `FindingDescriptor`,
  which only an error or advisory descriptor can become, so a note rule has
  no path to a finding.
- `RuleCatalog.parse` rejects more at load: a rule whose own examples
  disagree with its schema; `each` over a fact that is not a list;
  `failing_field` that is not an element field; a `properties` or
  `required` name at the subject level that no fact or element field of a
  closed subject carries; params for a builtin that declares none; a message
  placeholder the builtin does not fill; and a builtin frozen for 2026.2
  (the registry readers, `declared-okf-binding`, `relationships-shape`,
  `relationship-label-extension`, `index-semantic-projection`,
  `source-attribution-in-source`) in any catalog but the installed 2026.2
  one. `CatalogRule.failingExamples` is gone; load runs the examples.
- Profile 2026.3 `relationship-shape` fails a `relationships` value that is
  null, and an entry whose `resource` okf resolves as `invalid` or as a
  scope `descriptor`, as §7.2 requires of a link target. The rule moves to
  the `concept` subject: each `relationships` element carries the authored
  `entry` with the `resolution` beside it, and a non-list value stays the
  value itself. `okfFieldEdges` resolves targets as source resources, so
  prose resolves as `descriptor` rather than `unresolved`. The engine tests
  a non-list `each` fact as one `{"value": ...}` instance instead of failing
  it outright, so the rule's schema decides.
- Profile 2026.3 reports an undeclared relationship name as the new
  `used-relationship-declared` (vocabulary, error), like
  `used-type-registered` and `used-actor-registered`, instead of
  `relationship-shape`, which now checks that `relationship` is a nonempty
  string, not that it is declared. The new rule tests a name only once the entry is a
  mapping with nonempty text there, so one defect never reports under both.
- `{failing}` and `{fact}` placeholders render a non-string value as compact
  JSON instead of Dart's `{key: value}` text, so a failing relationships
  entry reads as it was authored. Strings are unchanged.
- A failure while resolving relationship targets no longer drops the
  `relationships` and `inbound` facts silently. okf's graph and the
  relationship edges resolve as one link layer; when it fails, no link fact
  exists for a link rule to pass on, and the run reports it.
  `BundleFacts.project` takes a `buildGraph` function so a test can force
  that path.
- Export `OkfLinkField`, `OkfFieldEdge` and `okfFieldEdges`, the typed
  link-field model and resolution `wayfinder_embeddings` and the CLI graph
  shared with the engine, plus `relationshipsLinkField` for the Profile's
  `relationships` key. The engine's relationship facts resolve through the
  same function.
- The 2026.2 catalog checks `source-attribution-join` through the frozen
  `source-attribution-in-source` builtin, which reads a footnote definition
  from the raw source, fenced code included, as before the `footnotes` fact
  stopped counting definitions inside a fence. 2026.2 output is unchanged
  from 0.1.x.
- Profile 2026.3 reports what it permits as summary entries instead of
  advisories. Catalog rules take a third severity, `note`, whose results
  fill `ProfileValidationResult.summary` (`ProfileSummaryEntry`), JSON
  `profile.summary`, a text `Summary:` block and SARIF results of kind
  `informational` with level `none`, and never affect a state or the exit code.
  `internal-link-unresolved` and `relationship-unresolved` become notes. `evaluate` returns findings and
  summary entries apart. A declared tag that equals a type, status, trust
  tier or relationship name fails `WayfinderProjectConfig.parse` and binding
  composition, and the 2026.3 catalog drops `tag-literal-duplication`.
  2026.2 is unchanged.
- Profile 2026.3 types relationships in the `relationships` frontmatter key
  instead of a `# Relationships` body section. The 2026.3 catalog declares
  the key in its new `frontmatter_keys`, renames `frontmatter-fields-okf` to
  `frontmatter-fields-declared`, adds `relationship-shape` (error) and the
  `relationship-bundle-relative` and `relationship-unresolved` advisories, and
  drops `relationships-shape` and `relationship-label-extension`.
  `tag-literal-duplication` compares tags with the declared relationship
  names. Relationship names are vocabulary: the manifest declares eleven
  standard names and `WayfinderProfileBinding.relationships` adds project
  names. A catalog declaring an OKF key fails to load. 2026.2 is unchanged.
- Profile 2026.3 indexes are okf's generated output: `index-current` replaces
  `index-semantic-projection` and `directory-index-present` in the 2026.3
  catalog and reports each generated index that is missing or differs.
  `ProfileValidator.validate(fix: true)` writes those indexes first and
  reports what it wrote as `ProfileValidationResult.fixed`. It also reports a
  leftover `index.md` the generator no longer writes, such as one in a
  `raw/` tier, so the parent index stops linking to it. Conformance now
  depends on okf's generator output; the configured-fixture goldens fail if an
  okf release changes it, which is the signal to update the guide's pin.
  2026.2 is unchanged.
- Add exact `bitwild_profile/2026.3` direct-source project bindings from
  `wayfinder.json`, with additive `extends`, strict type, tag, actor, and
  path checks. Version 1 accepts only `source` + `applies_to`; the earlier
  unpublished `bundles` / `implements` draft is not a compatibility form.
  Include OKF's Attested Computation in the twelve standard types.
- Inspect OKF independently before Profile dispatch and enforce the 2026.3
  root `okf_version`. Preserve published 2026.2 in-bundle validation without
  migrating it because of an unrelated project configuration.
- Report a configured project type at the configuration path as supplied, or
  `wayfinder.json` when discovered, instead of the file's absolute path.
- Stop reporting nested `profile.md`, `types.md`, or `actors.md` concepts as
  `root-structure-files` under 2026.3, whose §3.5 forbids only the legacy root
  registries. 2026.2 still reserves the names at every depth.
- Profile 2026.3 `log-entry-lead-word` no longer fails a root log without
  entries. §10 requires a lead word on every entry, not that entries exist.
  okf's `missing-log-date` and `empty-log-date` errors still reject such a
  log before Profile validation runs. 2026.2 is unchanged.

# 0.1.0

- Validate against Concepta Profile 2026.2, which adopts the OKF 0.2 revision
  where every timestamp is an ISO 8601 datetime with an explicit UTC offset, and
  pins the specification to its canonical `open-knowledge-format` repository at
  `ad30107`. A bundle still declaring `concepta_profile: "2026.1"` now reports an
  unsupported release rather than a conformance verdict; update the declaration
  and, where timestamps are date-only, run `okf format --migrate-timestamps`.
- Depend on `okf` ^0.5.0. A date-only timestamp is reported through okf's
  non-blocking `okf/timestamp-without-offset` advisory, so a bundle conformant
  under 2026.1 stays conformant once its declaration is updated.
- Raise the Dart floor from 3.6.0 to 3.11.0, matching every Concepta
  package. A consumer on an older SDK no longer resolves this package and
  must upgrade Dart to take 0.1.0.

# 0.0.1

Core library replaces okf_profile; import package:wayfinder/wayfinder.dart. Validation contracts remain unchanged. The command and MCP server now live in wayfinder_cli.

# Changelog

## 0.2.1-dev.0

- Expose the existing validator and result contracts for Wayfinder without changing
  `okfp` commands, validation semantics or exit codes.

Release history of the `okf_profile` Dart package (the `okfp` toolchain).
This is package semver; profile releases are recorded in `profile/`, not here.

## 0.2.0

- Migrate to okf 0.2.0 and adopt its finding contract as the wire format
  (ADR-0008): the `okf.report` JSON object is now okf's own projection — a
  canonically ordered `findings` array of `{id, severity, message, location}`
  objects with namespaced kebab-case IDs — and the separate `okf.load_issues`
  channel is retired, because load failures are error-severity findings in the
  same report.
- Text output reports the OKF component as `N error(s), N advisory(ies)`;
  the `warning` tier no longer exists upstream.
- `ProfileValidator` validates through okf's single report-composition seam
  (`OkfBundleLoadResult.validate()`) and no longer takes an okf validator.
- Profile findings speak the same finding grammar (ADR-0008): each JSON
  finding is the okf projection — `{id, severity, message, location}` — plus
  the `profile_release` and `rule` references guide §4.2 requires, and
  findings sort in okf's canonical report order (path, line, column, id,
  severity, message) instead of emission order.
- Add the profile rule descriptor registry (id, severity, normative rule
  reference), mirroring okf's `okfSpecRuleDescriptors`. Every finding is
  built from its rule's descriptor, so id, severity, and rule reference
  cannot drift from the registry — a call site names only the rule, the
  observation, and its path — and a corpus test holds every emitted finding
  to a registered rule.
- The automated gate's exit codes are okf's `OkfExitCode` contract:
  `success`/`findings`/`usage` for PASS/FAIL/UNSUPPORTED (values unchanged).
- Index and log parsing go through okf's `OkfIndexDocument`/`OkfLogDocument`
  entry format instead of a hand-rolled markdown-AST parallel; ADR-0007's
  percent-decoded target comparison is unchanged on top of it. okf 0.2.0's
  angle-bracket destination form means a raw `)` no longer forces the
  percent-encoded spelling; the authoring skill teaches both. The §9 expected
  projection stays profile-owned — okf's generic index generator synthesizes
  directory descriptions the Concepta projection deliberately leaves empty.

## 0.1.1

- Enforce the Profile 2026.1 `raw/` tier amendment (ADR-0006): non-index
  markdown under a `raw/` directory in `references/` fails deterministically
  as `concepta-profile/raw-directory-markdown`, and a `raw/` directory sitting
  directly under `references/` fails as
  `concepta-profile/raw-directory-placement` — the tier is per source
  directory, and `references/` itself is not one.

## 0.1.0

- Bootstrap the `okf_profile` package and the `okfp` command-line interface,
  as a pub workspace member at `packages/wayfinder/`.
- Ship the closed `validate <bundle> [--output text|json]` automated gate for
  the Concepta Profile, backed by the independent OKF 0.2 result.
- Keep deterministic Profile findings, contextual judgment, and automated-gate
  states separate in stable text and JSON contracts.
