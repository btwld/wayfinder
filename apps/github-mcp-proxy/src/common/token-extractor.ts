import type { ProxyConfig } from '../config/proxy-config';
import {
  BadRequestProxyError,
  ForbiddenProxyError,
  UnauthorizedProxyError,
} from './errors';

export type HeaderMap = Record<string, string | string[] | undefined>;

export function extractRequestHeaders(request: unknown): HeaderMap {
  if (!request || typeof request !== 'object') {
    return {};
  }
  const candidate = request as {
    headers?: HeaderMap;
    raw?: { headers?: HeaderMap };
  };
  return candidate.headers ?? candidate.raw?.headers ?? {};
}

export function getHeaderValue(headers: HeaderMap, headerName: string): string | undefined {
  const target = headerName.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() !== target) continue;
    if (Array.isArray(value)) {
      return value[0];
    }
    return value;
  }
  return undefined;
}

/**
 * Resolves the GitHub API token for a request.
 *
 * Security rule: ONLY reads `x-github-token` (when ALLOW_REQUEST_TOKEN_OVERRIDE=true)
 * and NEVER reads `Authorization: Bearer ...` so proxy auth tokens are never leaked
 * to GitHub or conflated with GitHub credentials.
 */
export function resolveGithubToken(
  requestOrHeaders: unknown,
  config: ProxyConfig,
): string | undefined {
  const headers =
    requestOrHeaders &&
    typeof requestOrHeaders === 'object' &&
    'headers' in (requestOrHeaders as Record<string, unknown>)
      ? extractRequestHeaders(requestOrHeaders)
      : ((requestOrHeaders as HeaderMap | undefined) ?? {});

  const overrideHeader = getHeaderValue(headers, 'x-github-token');
  if (overrideHeader !== undefined) {
    if (!config.github.allowRequestTokenOverride) {
      throw new ForbiddenProxyError(
        'Request GitHub token override (x-github-token) is disabled',
      );
    }
    const trimmed = overrideHeader.trim();
    if (!trimmed) {
      throw new BadRequestProxyError('x-github-token header must not be empty');
    }
    return trimmed;
  }

  return config.github.token;
}

export function requireGithubToken(
  requestOrHeaders: unknown,
  config: ProxyConfig,
): string {
  const token = resolveGithubToken(requestOrHeaders, config);
  if (!token) {
    throw new UnauthorizedProxyError(
      'GitHub token required for this operation. Configure GITHUB_TOKEN or supply x-github-token when enabled.',
    );
  }
  return token;
}
