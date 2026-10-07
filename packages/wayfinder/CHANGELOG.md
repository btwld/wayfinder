# Unreleased

- A package may name its agent skill directory in `skill`
  (`ProfilePackage.skill`), relative to the package. A Profile id has at most
  64 characters (`ProfileId.maxLength`, `maxLength` in both schemas), the
  Agent Skills name limit, because the id names the installed skill. The new
  `wayfinder/profile-skill-stale` warning reports a Profile skill whose
  installed copy is not the locked revision, carried by
  `SelectedProfile.notes`.
- A package names its own parent in `extends`: `{"path"}` is the package at
  that path in the same repository at the same commit, and
  `{"git", "ref", "path"}` resolves its own revision (`PackageParent`,
  `SameRevision`, `OtherRevision`). `wayfinder.json` loses `extends`, and
  `applies_to` needs at least one path. `ProfileValidator.validate` takes a
  `ProfileSelection`, either `SelectedProfile` or `UnselectedProfile`,
  instead of reading the configuration itself; `WayfinderProjectConfig.bind`
  finds a bundle's binding or throws `BundleBindingException` with its one
  diagnostic. `ProfileSourceResolution`, `WayfinderProjectConfig.read`,
  `resolve` and `WayfinderResolvedConfig` are gone. Whenever a Profile was
  selected, including under `BLOCKED BY OKF`, the JSON result names it as
  `profile.id` and `profile.release` and its chain as `profile.chain`
  (`{id, release, commit}`, root first). Only `NOT ASSESSED` omits them.
  Text prints `Profile <id> <release>: <state>`, and SARIF gains the
  `profile_id` run property.
- A Profile is one package file, `wayfinder-profile.json` in package
  format 2, read by `ProfilePackage.parse` for every Profile alike. The
  manifest and rule catalog are merged (`standard_types` is `types`,
  `frontmatter_keys` is a list of definitions, the rule shape moves in, the
  per-rule `ref` is gone), `wayfinder-rules.schema.json` folds into
  `wayfinder-profile.schema.json`, and the engine embeds no Profile. Bitwild
  is the package at `profiles/bitwild/` with id `bitwild-profile`, so its
  findings are `bitwild-profile/*` (formerly `concepta-profile/*`), and it is
  fetched like any Profile; no chain has to reach it. A package id is the
  finding namespace, in kebab-case. `EffectiveProfile.compose` merges a
  chain and the project additions, and a name collision, a repeated
  frontmatter key or a tag equal to another vocabulary value is the
  `wayfinder/profile-composition` diagnostic (a tag collision was
  `config-invalid`). A malformed package is `wayfinder/profile-invalid`; a
  package with another `format`, an OKF release this okf cannot read or an
  unknown builtin is `wayfinder/profile-unsupported`. Findings and summary
  entries carry `help_uri`, the package `docs` URI with the rule id as its
  fragment, instead of `rule`; SARIF rule descriptors carry `helpUri` and
  lose `properties.ref`. Builtins are engine capabilities with params:
  `files-present` (`paths`), `path-targets-exist` (`fields`) and
  `matches-generated` (`generator`, `version`, `keep`, `extra`), and
  the generator declares the package's `implements.release`. The JSON
  result gains `engine.okf` and SARIF `tool.extensions` names the okf
  package the engine generates with. New root facts `has_concepts` and
  `index_links`, and the Bitwild rule `root-index-lists-log`. The
  generator is `tool/generate_published_schemas.dart`, writing
  `published_schemas.g.dart`.
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
  `legacyStandardTypes`, and the `yaml` dependency is dropped. A 2026.2
  bundle keeps validating on wayfinder 0.1.x, or migrates to a
  `wayfinder.json` binding.
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
  the gate `INCOMPLETE` rather than `FAIL`, and skips every rule that reads
  a link fact: by name, through a `$ref` applied to the subject, or through a
  keyword that reads the whole key set (`propertyNames`,
  `additionalProperties`, `minProperties`, `enum`, `const`).
  `ProfileValidator` takes a `buildGraph` function so a test can force that
  path.
- `index-current` and `validate --fix` compare an index with CRLF line
  endings, as a Windows checkout writes it, equal to the generated LF text,
  so neither reports nor rewrites it.
- `validate --fix` replaces each generated index atomically, refuses a
  symbolic link at any path segment, and reports a failed write with the
  files already written. SARIF locations inside the working directory
  are relative to a recorded `WORKINGDIR` base, and summary results carry
  level `none`.
- `ProfileFinding` takes a `FindingDescriptor`,
  which only an error or advisory descriptor can become, so a note rule has
  no path to a finding.
- A rule schema names a composed vocabulary as `{"$ref": "#/$defs/<slot>"}`,
  such as `#/$defs/profile.types`. The engine supplies those entries, so a
  package or rule `$defs` entry may not use a slot id. The `x-slot` keyword
  is gone, and any `x-` keyword now makes a package unsupported rather than
  being ignored, so every rule schema is plain JSON Schema.
- `ProfilePackage.parse` rejects more at load: a rule whose own examples
  disagree with its schema; `each` over a fact that is not a list;
  `failing_field` that is not an element field; a `properties` or
  `required` name at the subject level, inline or through a `$ref` applied
  to the same instance, that no fact or element field of a closed subject
  carries; params for a builtin that declares none; and a
  message placeholder the builtin does not fill. `failingExamples` is gone;
  load runs the examples.
- Bitwild 2026.3 `relationship-shape` fails a `relationships` value that is
  null, and an entry whose `resource` okf resolves as `invalid` or as a
  scope `descriptor`. The rule moves to
  the `concept` subject: each `relationships` element carries the authored
  `entry` with the `resolution` beside it, and a non-list value stays the
  value itself. `okfFieldEdges` resolves targets as source resources, so
  prose resolves as `descriptor` rather than `unresolved`. The engine tests
  a non-list `each` fact as one `{"value": ...}` instance instead of failing
  it outright, so the rule's schema decides.
- Bitwild 2026.3 reports an undeclared relationship name as the new
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
- Bitwild 2026.3 reports what it permits as summary entries instead of
  advisories. Rules take a third severity, `note`, whose results
  fill `ProfileValidationResult.summary` (`ProfileSummaryEntry`), JSON
  `profile.summary`, a text `Summary:` block and SARIF results of kind
  `informational` with level `none`, and never affect a state or the exit code.
  `internal-link-unresolved` and `relationship-unresolved` become notes. `evaluate` returns findings and
  summary entries apart. A declared tag that equals a type, status, trust
  tier or relationship name fails `WayfinderProjectConfig.parse` and binding
  composition, and Bitwild 2026.3 drops `tag-literal-duplication`.
- Bitwild 2026.3 types relationships in the `relationships` frontmatter key
  instead of a `# Relationships` body section. Bitwild 2026.3 declares
  the key in its new `frontmatter_keys`, renames `frontmatter-fields-okf` to
  `frontmatter-fields-declared`, adds `relationship-shape` (error) and the
  `relationship-bundle-relative` and `relationship-unresolved` advisories, and
  drops `relationships-shape` and `relationship-label-extension`.
  `tag-literal-duplication` compares tags with the declared relationship
  names. Relationship names are vocabulary: Bitwild declares eleven and
  `WayfinderProfileBinding.relationships` adds project names. A package
  declaring an OKF key fails to load.
- Bitwild 2026.3 indexes are okf's generated output: `index-current` replaces
  `index-semantic-projection` and `directory-index-present` in Bitwild 2026.3
  and reports each generated index that is missing or differs.
  `ProfileValidator.validate(fix: true)` writes those indexes first and
  reports what it wrote as `ProfileValidationResult.fixed`. It also reports a
  leftover `index.md` the generator no longer writes, such as one in a
  `raw/` tier, so the parent index stops linking to it. Conformance now
  depends on okf's generator output; the configured-fixture goldens fail if an
  okf release changes it, which is the signal to update the guide's pin.
- Add direct-source project bindings in `wayfinder.json`, with strict type,
  tag, actor, and path checks. Version 1 accepts only `source` +
  `applies_to`; the earlier unpublished `bundles` / `implements` draft is not
  a compatibility form. Bitwild's twelve types include OKF's Attested
  Computation.
- Inspect OKF independently before Profile selection. Bitwild's
  `okf-release-binding` checks the root `okf_version`.
- Report a configured project type at the configuration path as supplied, or
  `wayfinder.json` when discovered, instead of the file's absolute path.
- Stop reporting nested `profile.md`, `types.md`, or `actors.md` concepts.
  Bitwild forbids only the legacy root registries.
- Bitwild 2026.3 `log-entry-lead-word` no longer fails a root log without
  entries. The rule requires a lead word on every entry, not that entries
  exist. okf's `missing-log-date` and `empty-log-date` errors still reject
  such a log before Profile validation runs.

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
