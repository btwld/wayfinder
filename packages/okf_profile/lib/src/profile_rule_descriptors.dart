import 'package:okf/okf.dart';

/// Read-only metadata describing one deterministic Concepta Profile rule,
/// mirroring okf's `okfSpecRuleDescriptors`.
///
/// A descriptor is the single authority for its rule's finding ID, severity,
/// and normative Profile clause reference: every finding is built from the
/// descriptor of the rule that reports it, so none of the three can drift.
/// Descriptors carry no prose — the Profile document owns each rule's
/// statement, and restating it here would be a second copy to drift.
/// Execution stays fixed inside the closed validator; a descriptor cannot
/// alter validation.
final class ProfileRuleDescriptor {
  const ProfileRuleDescriptor.error(String slug, this.rule)
      : id = 'concepta-profile/$slug',
        severity = OkfFindingSeverity.error;

  const ProfileRuleDescriptor.advisory(String slug, this.rule)
      : id = 'concepta-profile/$slug',
        severity = OkfFindingSeverity.advisory;

  /// Stable `concepta-profile/<rule-slug>` finding ID.
  final String id;

  /// Severity emitted when the condition is found.
  final OkfFindingSeverity severity;

  /// The normative Concepta Profile clause reference the rule assesses.
  final String rule;
}

// Release dispatch and declaration.
const profileDeclarationPresent =
    ProfileRuleDescriptor.error('profile-declaration-present', '§11');
const profileDeclarationReadable =
    ProfileRuleDescriptor.error('profile-declaration-readable', '§11');
const profileDeclarationFields =
    ProfileRuleDescriptor.error('profile-declaration-fields', '§11');
const okfReleaseBinding =
    ProfileRuleDescriptor.error('okf-release-binding', '§11');

// Concept rules.
const profileDeclarationKind =
    ProfileRuleDescriptor.error('profile-declaration-kind', '§11');
const conceptBaselineFields =
    ProfileRuleDescriptor.error('concept-baseline-fields', '§5.1');
const frontmatterFieldsOkf =
    ProfileRuleDescriptor.error('frontmatter-fields-okf', '§5.1');
const statusValue = ProfileRuleDescriptor.error('status-value', '§5.1');
const tagLiteralDuplication =
    ProfileRuleDescriptor.error('tag-literal-duplication', '§5.1');
const generationProvenanceRecommended =
    ProfileRuleDescriptor.advisory('generation-provenance-recommended', '§5.1');
const typeRegistryPresent =
    ProfileRuleDescriptor.error('type-registry-present', '§5.2');
const typeRegistryKind =
    ProfileRuleDescriptor.error('type-registry-kind', '§5.2');
const typeRegistryColumns =
    ProfileRuleDescriptor.error('type-registry-columns', '§6.1.1');
const typeRegistryStandards =
    ProfileRuleDescriptor.error('type-registry-standards', '§5.2');
const typeRegistryOrder =
    ProfileRuleDescriptor.error('type-registry-order', '§5.2');
const usedTypeRegistered =
    ProfileRuleDescriptor.error('used-type-registered', '§5.2');
const registeredTypeExtension =
    ProfileRuleDescriptor.advisory('registered-type-extension', '§5.2');
const actorRegistryRequired =
    ProfileRuleDescriptor.error('actor-registry-required', '§3.5, §6.1.1');
const actorRegistryKind =
    ProfileRuleDescriptor.error('actor-registry-kind', '§3.5, §6.1.1');
const actorRegistryColumns =
    ProfileRuleDescriptor.error('actor-registry-columns', '§6.1.1');
const actorRowComplete =
    ProfileRuleDescriptor.error('actor-row-complete', '§3.5, §6.1.1');
const actorSideValue =
    ProfileRuleDescriptor.error('actor-side-value', '§6.1.1');
const actorActiveInterval =
    ProfileRuleDescriptor.error('actor-active-interval', '§6.1.1');
const actorActiveOverlap =
    ProfileRuleDescriptor.error('actor-active-overlap', '§6.1.1');
const usedActorRegistered =
    ProfileRuleDescriptor.error('used-actor-registered', '§3.5, §6.1.1');
const sourceEntryShape =
    ProfileRuleDescriptor.error('source-entry-shape', '§6.1');
const sourceIdUnique = ProfileRuleDescriptor.error('source-id-unique', '§6.1');
const sourceAttributionJoin =
    ProfileRuleDescriptor.error('source-attribution-join', '§6.1');
const relationshipsShape =
    ProfileRuleDescriptor.error('relationships-shape', '§7.2');
const relationshipLabelExtension =
    ProfileRuleDescriptor.advisory('relationship-label-extension', '§7.2');
const linkGraphUnavailable =
    ProfileRuleDescriptor.error('link-graph-unavailable', '§7.1');
const internalLinkBundleRelative =
    ProfileRuleDescriptor.advisory('internal-link-bundle-relative', '§7.1');
const internalLinkUnresolved = ProfileRuleDescriptor.advisory(
    'internal-link-unresolved', '§7.1, §14.1–§14.2');

// Structure rules.
const rawDirectoryPlacement =
    ProfileRuleDescriptor.error('raw-directory-placement', '§3.4');
const rawDirectoryMarkdown =
    ProfileRuleDescriptor.error('raw-directory-markdown', '§3.4');
const rootStructureFiles =
    ProfileRuleDescriptor.error('root-structure-files', '§3.5');
const directoryIndexPresent =
    ProfileRuleDescriptor.error('directory-index-present', '§3.1, §3.4, §9');
const conceptAreaNameCollision =
    ProfileRuleDescriptor.advisory('concept-area-name-collision', '§14.1');
const indexSemanticProjection =
    ProfileRuleDescriptor.error('index-semantic-projection', '§9');
const logEntryLeadWord =
    ProfileRuleDescriptor.error('log-entry-lead-word', '§10');

/// Every finding the closed Concepta Profile validator can emit.
const List<ProfileRuleDescriptor> profileRuleDescriptors = [
  profileDeclarationPresent,
  profileDeclarationReadable,
  profileDeclarationFields,
  okfReleaseBinding,
  profileDeclarationKind,
  conceptBaselineFields,
  frontmatterFieldsOkf,
  statusValue,
  tagLiteralDuplication,
  generationProvenanceRecommended,
  typeRegistryPresent,
  typeRegistryKind,
  typeRegistryColumns,
  typeRegistryStandards,
  typeRegistryOrder,
  usedTypeRegistered,
  registeredTypeExtension,
  actorRegistryRequired,
  actorRegistryKind,
  actorRegistryColumns,
  actorRowComplete,
  actorSideValue,
  actorActiveInterval,
  actorActiveOverlap,
  usedActorRegistered,
  sourceEntryShape,
  sourceIdUnique,
  sourceAttributionJoin,
  relationshipsShape,
  relationshipLabelExtension,
  linkGraphUnavailable,
  internalLinkBundleRelative,
  internalLinkUnresolved,
  rawDirectoryPlacement,
  rawDirectoryMarkdown,
  rootStructureFiles,
  directoryIndexPresent,
  conceptAreaNameCollision,
  indexSemanticProjection,
  logEntryLeadWord,
];
