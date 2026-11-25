import { RepoAllowlist } from './repo-allowlist';

export const PROXY_CONFIG = Symbol('PROXY_CONFIG');

export type ProxyAuthMode = 'api-key' | 'oauth' | 'firebase' | 'none' | 'unconfigured';

export interface ProxyConfig {
  port: number;
  host: string;
  github: {
    apiBaseUrl: string;
    token?: string;
    defaultOwner?: string;
    defaultRepo?: string;
    allowRequestTokenOverride: boolean;
    allowedRepos: RepoAllowlist;
    requestTimeoutMs: number;
    retryMaxAttempts: number;
    retryInitialDelayMs: number;
    retryMaxDelayMs: number;
  };
  mcp: {
    endpoint: string;
    enableJsonResponse: boolean;
    stateless: true;
  };
  auth: {
    mode: ProxyAuthMode;
    apiKeys: string[];
    oauth?: {
      resource: string;
      authorizationServers: string[];
      jwksUri?: string;
      issuer?: string;
      audience?: string;
      introspectionEndpoint?: string;
      introspectionClientId?: string;
      introspectionClientSecret?: string;
      requiredScopes?: string[];
      validateAudience: boolean;
    };
    firebase?: {
      projectId: string;
      resource: string;
      requiredScopes?: string[];
    };
  };
  cors: {
    origins: string[];
  };
  sessions: {
    branchPrefix: string;
    requireChecksDefault: boolean;
    requiredCheckNames: string[];
    mergeRetryMaxAttempts: number;
    mergeRetryInitialDelayMs: number;
    mergeRetryMaxDelayMs: number;
  };
  limits: {
    maxTarballBytes: number;
    maxBundleFiles: number;
    maxBundleTotalBytes: number;
    maxSearchFilesScanned: number;
    maxListSessionPages: number;
  };
  resilience: {
    timeoutMs: number;
    rateLimitMax: number;
    rateLimitWindow: string;
  };
}

function splitCsv(raw: string | undefined): string[] {
  return (raw ?? '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function parsePositiveInt(raw: string | undefined, fallback: number, name: string): number {
  if (raw === undefined || raw.trim() === '') return fallback;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`Configuration "${name}" must be a positive integer, got "${raw}"`);
  }
  return parsed;
}

function normalizeEndpoint(raw: string | undefined, fallback: string): string {
  const value = (raw ?? fallback).trim();
  if (!value) return fallback;
  return value.startsWith('/') ? value : `/${value}`;
}

export function loadProxyConfig(env: NodeJS.ProcessEnv = process.env): ProxyConfig {
  const defaultOwner = env.GITHUB_OWNER?.trim() || undefined;
  const defaultRepo = env.GITHUB_REPO?.trim() || undefined;
  const allowedRepos = RepoAllowlist.fromEnv(env.ALLOWED_REPOS, defaultOwner, defaultRepo);

  const apiKeys = [
    ...splitCsv(env.PROXY_API_KEYS),
    ...(env.PROXY_API_KEY?.trim() ? [env.PROXY_API_KEY.trim()] : []),
  ];

  const jwksUri = env.MCP_AUTH_JWKS_URI?.trim() || undefined;
  const introspectionEndpoint = env.MCP_AUTH_INTROSPECTION_ENDPOINT?.trim() || undefined;
  const firebaseProjectId = env.FIREBASE_AUTH_PROJECT_ID?.trim() || undefined;
  const allowUnauthenticated = env.ALLOW_UNAUTHENTICATED_ACCESS === 'true';

  const rawAuthMode = (env.PROXY_AUTH_MODE ?? 'auto').trim().toLowerCase();
  let mode: ProxyAuthMode;

  if (rawAuthMode === 'auto' || rawAuthMode === '') {
    if (apiKeys.length > 0) {
      mode = 'api-key';
    } else if (jwksUri || introspectionEndpoint) {
      mode = 'oauth';
    } else if (firebaseProjectId) {
      mode = 'firebase';
    } else if (allowUnauthenticated) {
      mode = 'none';
    } else {
      mode = 'unconfigured';
    }
  } else if (
    rawAuthMode === 'api-key' ||
    rawAuthMode === 'oauth' ||
    rawAuthMode === 'firebase' ||
    rawAuthMode === 'none'
  ) {
    mode = rawAuthMode;
  } else {
    throw new Error(
      `Unsupported PROXY_AUTH_MODE "${rawAuthMode}". Expected auto, api-key, oauth, firebase, or none.`,
    );
  }

  const endpoint = normalizeEndpoint(env.MCP_ENDPOINT, '/mcp');
  const port = parsePositiveInt(env.PORT, 8080, 'PORT');
  const defaultResource = env.MCP_AUTH_RESOURCE?.trim() || `http://localhost:${port}${endpoint}`;
  const requiredScopes = splitCsv(env.MCP_AUTH_REQUIRED_SCOPES);

  let oauthConfig: ProxyConfig['auth']['oauth'];
  let firebaseConfig: ProxyConfig['auth']['firebase'];

  if (mode === 'api-key' && apiKeys.length === 0) {
    throw new Error('PROXY_AUTH_MODE=api-key requires PROXY_API_KEYS or PROXY_API_KEY');
  }

  if (mode === 'oauth') {
    const authorizationServers = splitCsv(env.MCP_AUTH_AUTHORIZATION_SERVERS);
    const issuer = env.MCP_AUTH_ISSUER?.trim() || authorizationServers[0];
    if (authorizationServers.length === 0 && !issuer) {
      throw new Error(
        'PROXY_AUTH_MODE=oauth requires MCP_AUTH_AUTHORIZATION_SERVERS or MCP_AUTH_ISSUER',
      );
    }
    if (!jwksUri && !introspectionEndpoint) {
      throw new Error(
        'PROXY_AUTH_MODE=oauth requires MCP_AUTH_JWKS_URI or MCP_AUTH_INTROSPECTION_ENDPOINT',
      );
    }
    oauthConfig = {
      resource: defaultResource,
      authorizationServers: authorizationServers.length > 0 ? authorizationServers : [issuer!],
      jwksUri,
      issuer,
      audience: env.MCP_AUTH_AUDIENCE?.trim() || undefined,
      introspectionEndpoint,
      introspectionClientId: env.MCP_AUTH_INTROSPECTION_CLIENT_ID?.trim() || undefined,
      introspectionClientSecret: env.MCP_AUTH_INTROSPECTION_CLIENT_SECRET?.trim() || undefined,
      requiredScopes: requiredScopes.length > 0 ? requiredScopes : undefined,
      validateAudience: env.MCP_AUTH_VALIDATE_AUDIENCE !== 'false',
    };
  }

  if (mode === 'firebase') {
    if (!firebaseProjectId) {
      throw new Error('PROXY_AUTH_MODE=firebase requires FIREBASE_AUTH_PROJECT_ID');
    }
    firebaseConfig = {
      projectId: firebaseProjectId,
      resource: defaultResource,
      requiredScopes: requiredScopes.length > 0 ? requiredScopes : undefined,
    };
  }

  return {
    port,
    host: env.HOST?.trim() || '0.0.0.0',
    github: {
      apiBaseUrl: (env.GITHUB_API_BASE_URL?.trim() || 'https://api.github.com').replace(/\/+$/, ''),
      token: env.GITHUB_TOKEN?.trim() || undefined,
      defaultOwner,
      defaultRepo,
      allowRequestTokenOverride: env.ALLOW_REQUEST_TOKEN_OVERRIDE === 'true',
      allowedRepos,
      requestTimeoutMs: parsePositiveInt(
        env.GITHUB_REQUEST_TIMEOUT_MS,
        20_000,
        'GITHUB_REQUEST_TIMEOUT_MS',
      ),
      retryMaxAttempts: parsePositiveInt(
        env.GITHUB_RETRY_MAX_ATTEMPTS ?? env.MCP_RETRY_MAX_ATTEMPTS,
        2,
        'GITHUB_RETRY_MAX_ATTEMPTS',
      ),
      retryInitialDelayMs: parsePositiveInt(
        env.GITHUB_RETRY_INITIAL_DELAY_MS ?? env.MCP_RETRY_INITIAL_DELAY_MS,
        200,
        'GITHUB_RETRY_INITIAL_DELAY_MS',
      ),
      retryMaxDelayMs: parsePositiveInt(
        env.GITHUB_RETRY_MAX_DELAY_MS ?? env.MCP_RETRY_MAX_DELAY_MS,
        2_000,
        'GITHUB_RETRY_MAX_DELAY_MS',
      ),
    },
    mcp: {
      endpoint,
      enableJsonResponse: env.MCP_ENABLE_JSON_RESPONSE !== 'false',
      stateless: true,
    },
    auth: {
      mode,
      apiKeys,
      oauth: oauthConfig,
      firebase: firebaseConfig,
    },
    cors: {
      origins: splitCsv(env.CORS_ORIGINS),
    },
    sessions: {
      branchPrefix: 'wayfinder/session/',
      requireChecksDefault: env.SESSION_REQUIRE_CHECKS_DEFAULT === 'true',
      requiredCheckNames: splitCsv(env.SESSION_REQUIRED_CHECK_NAMES),
      mergeRetryMaxAttempts: parsePositiveInt(
        env.SESSION_MERGE_RETRY_MAX_ATTEMPTS,
        5,
        'SESSION_MERGE_RETRY_MAX_ATTEMPTS',
      ),
      mergeRetryInitialDelayMs: parsePositiveInt(
        env.SESSION_MERGE_RETRY_INITIAL_DELAY_MS,
        500,
        'SESSION_MERGE_RETRY_INITIAL_DELAY_MS',
      ),
      mergeRetryMaxDelayMs: parsePositiveInt(
        env.SESSION_MERGE_RETRY_MAX_DELAY_MS,
        4_000,
        'SESSION_MERGE_RETRY_MAX_DELAY_MS',
      ),
    },
    limits: {
      maxTarballBytes: parsePositiveInt(
        env.MAX_TARBALL_BYTES,
        50 * 1024 * 1024,
        'MAX_TARBALL_BYTES',
      ),
      maxBundleFiles: parsePositiveInt(env.MAX_BUNDLE_FILES, 500, 'MAX_BUNDLE_FILES'),
      maxBundleTotalBytes: parsePositiveInt(
        env.MAX_BUNDLE_TOTAL_BYTES,
        10 * 1024 * 1024,
        'MAX_BUNDLE_TOTAL_BYTES',
      ),
      maxSearchFilesScanned: parsePositiveInt(
        env.MAX_SEARCH_FILES_SCANNED,
        1_000,
        'MAX_SEARCH_FILES_SCANNED',
      ),
      maxListSessionPages: parsePositiveInt(
        env.MAX_LIST_SESSION_PAGES,
        10,
        'MAX_LIST_SESSION_PAGES',
      ),
    },
    resilience: {
      timeoutMs: parsePositiveInt(env.MCP_TIMEOUT_MS, 30_000, 'MCP_TIMEOUT_MS'),
      rateLimitMax: parsePositiveInt(env.MCP_RATE_LIMIT_MAX, 120, 'MCP_RATE_LIMIT_MAX'),
      rateLimitWindow: env.MCP_RATE_LIMIT_WINDOW?.trim() || '1m',
    },
  };
}
