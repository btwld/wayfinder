const supportedProfileRelease = '2026.2';

const standardTypes = <(String, String)>[
  ('Glossary Definition', 'One project or domain term'),
  (
    'Business Rule',
    'One standing business rule, constraint, invariant, or policy',
  ),
  (
    'Question',
    'One named unknown, with what is known, what is missing, and what would close it',
  ),
  ('Request', 'A durable request from any relevant source'),
  (
    'Analysis',
    'An investigation, feasibility study, comparison, or recommendation',
  ),
  (
    'Decision',
    'A durable non-architectural decision with an independent lifecycle',
  ),
  ('Architecture Decision Record', 'An architectural decision in ADR form'),
  ('Architecture Document', 'A durable description of the system architecture'),
  (
    'Specification',
    'A specification the project maintains as durable knowledge, not one a tracker owns the state of',
  ),
  ('Guide', 'Durable operational or engineering guidance'),
  (
    'Interaction Record',
    'An interaction whose combined context is itself durable',
  ),
  ('Knowledge Profile', 'The Concepta Profile and OKF release declaration'),
  (
    'Type Registry',
    'The standard and project-specific types available to the bundle',
  ),
  (
    'Actor Registry',
    'Actor IDs mapped to identity, affiliation, role, and active period',
  ),
];
