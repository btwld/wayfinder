import { normalizeOptionalPrefix } from '../common/path-safety';

export interface ParsedWayfinderProfile {
  name: string;
  source?: {
    git?: string;
    ref?: string;
    path?: string;
  };
  appliesTo: string[];
}

export interface ParsedWayfinderConfig {
  version: number | null;
  profiles: ParsedWayfinderProfile[];
  appliesTo: string[];
  raw: Record<string, unknown> | null;
  parseError?: string;
}

export function parseWayfinderJson(rawJson: string): ParsedWayfinderConfig {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawJson);
  } catch (error) {
    return {
      version: null,
      profiles: [],
      appliesTo: [],
      raw: null,
      parseError: error instanceof Error ? error.message : String(error),
    };
  }

  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return {
      version: null,
      profiles: [],
      appliesTo: [],
      raw: null,
      parseError: 'wayfinder.json must be a JSON object',
    };
  }

  const record = parsed as Record<string, unknown>;
  const version = typeof record.version === 'number' ? record.version : null;
  const profilesObj =
    record.profiles && typeof record.profiles === 'object' && !Array.isArray(record.profiles)
      ? (record.profiles as Record<string, unknown>)
      : {};

  const profiles: ParsedWayfinderProfile[] = [];
  const allAppliesTo = new Set<string>();

  for (const [name, value] of Object.entries(profilesObj)) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) continue;
    const entry = value as Record<string, unknown>;
    const rawAppliesTo = Array.isArray(entry.applies_to) ? entry.applies_to : [];
    const normalizedAppliesTo: string[] = [];

    for (const rawPath of rawAppliesTo) {
      if (typeof rawPath !== 'string') continue;
      try {
        const normalized = normalizeOptionalPrefix(rawPath);
        if (normalized !== undefined) {
          normalizedAppliesTo.push(normalized);
          allAppliesTo.add(normalized);
        }
      } catch {
        // Ignore invalid/escaping paths in config inspection so read endpoints remain resilient
      }
    }

    const source =
      entry.source && typeof entry.source === 'object' && !Array.isArray(entry.source)
        ? (entry.source as Record<string, unknown>)
        : undefined;

    profiles.push({
      name,
      ...(source
        ? {
            source: {
              ...(typeof source.git === 'string' ? { git: source.git } : {}),
              ...(typeof source.ref === 'string' ? { ref: source.ref } : {}),
              ...(typeof source.path === 'string' ? { path: source.path } : {}),
            },
          }
        : {}),
      appliesTo: normalizedAppliesTo,
    });
  }

  return {
    version,
    profiles,
    appliesTo: [...allAppliesTo],
    raw: record,
  };
}
