import { describe, expect, it } from 'vitest';
import {
  BadRequestProxyError,
  ForbiddenProxyError,
} from '../../src/common/errors';
import {
  assertSafeRepoPath,
  assertSafeSessionId,
  assertSafeWriteBatch,
  encodeGitRefPath,
} from '../../src/common/path-safety';
import { resolveGithubToken } from '../../src/common/token-extractor';
import { loadProxyConfig } from '../../src/config/proxy-config';
import { RepoAllowlist } from '../../src/config/repo-allowlist';

describe('Path safety and ref encoding', () => {
  it('rejects traversal, .git (case-insensitive), NUL bytes, backslashes, and leading slashes', () => {
    const unsafe = [
      '',
      '../secret.md',
      'knowledge/../../etc/passwd',
      './knowledge/a.md',
      '/knowledge/a.md',
      'knowledge/a.md/',
      'knowledge\\a.md',
      '.git/config',
      'knowledge/.GIT/HEAD',
      '.Git',
      'knowledge/bad\0file.md',
      'knowledge//double.md',
    ];

    for (const candidate of unsafe) {
      expect(() => assertSafeRepoPath(candidate)).toThrow(BadRequestProxyError);
    }

    expect(assertSafeRepoPath('knowledge/reporting/include-pdf.md')).toBe(
      'knowledge/reporting/include-pdf.md',
    );
  });

  it('rejects duplicate paths and invalid write/delete combinations in batch', () => {
    expect(() =>
      assertSafeWriteBatch([
        { path: 'knowledge/a.md', content: 'one' },
        { path: 'knowledge/a.md', content: 'two' },
      ]),
    ).toThrow(BadRequestProxyError);

    expect(() =>
      assertSafeWriteBatch([{ path: 'knowledge/a.md', content: 'one', delete: true }]),
    ).toThrow(BadRequestProxyError);

    expect(() => assertSafeWriteBatch([{ path: 'knowledge/a.md' }])).toThrow(
      BadRequestProxyError,
    );
  });

  it('encodes Git ref segments without turning "/" into "%2F"', () => {
    expect(encodeGitRefPath('wayfinder/session/s-1')).toBe('wayfinder/session/s-1');
    expect(encodeGitRefPath('feature/my branch+1')).toBe('feature/my%20branch%2B1');
  });

  it('validates session IDs safely', () => {
    expect(assertSafeSessionId('sess-2026_01.a')).toBe('sess-2026_01.a');
    expect(() => assertSafeSessionId('../evil')).toThrow(BadRequestProxyError);
    expect(() => assertSafeSessionId('bad.lock')).toThrow(BadRequestProxyError);
  });
});

describe('RepoAllowlist & ProxyConfig security defaults', () => {
  it('defaults allowlist to GITHUB_OWNER/GITHUB_REPO when ALLOWED_REPOS is omitted', () => {
    const config = loadProxyConfig({
      GITHUB_TOKEN: 'ghp_server',
      GITHUB_OWNER: 'btwld',
      GITHUB_REPO: 'wayfinder',
    });
    expect(config.github.allowedRepos.isAllowed('btwld', 'wayfinder')).toBe(true);
    expect(config.github.allowedRepos.isAllowed('BTWLD', 'Wayfinder')).toBe(true);
    expect(() => config.github.allowedRepos.assertAllowed('evil', 'other')).toThrow(
      ForbiddenProxyError,
    );
  });

  it('denies all repos when neither ALLOWED_REPOS nor GITHUB_OWNER/GITHUB_REPO is set', () => {
    const config = loadProxyConfig({ GITHUB_TOKEN: 'ghp_server' });
    expect(config.github.allowedRepos.size).toBe(0);
    expect(() => config.github.allowedRepos.assertAllowed('btwld', 'wayfinder')).toThrow(
      ForbiddenProxyError,
    );
  });

  it('rejects wildcard entries in RepoAllowlist', () => {
    expect(() => new RepoAllowlist(['btwld/*'])).toThrow();
  });

  it('fails closed when no auth is configured unless explicitly opted out', () => {
    const failClosed = loadProxyConfig({});
    expect(failClosed.auth.mode).toBe('unconfigured');

    const optedOut = loadProxyConfig({ ALLOW_UNAUTHENTICATED_ACCESS: 'true' });
    expect(optedOut.auth.mode).toBe('none');
  });

  it('reads GitHub token override ONLY from x-github-token and NEVER from Authorization: Bearer', () => {
    const disabledConfig = loadProxyConfig({
      GITHUB_TOKEN: 'server-token',
      ALLOW_REQUEST_TOKEN_OVERRIDE: 'false',
    });

    expect(
      resolveGithubToken(
        { headers: { authorization: 'Bearer proxy-jwt-should-not-leak' } },
        disabledConfig,
      ),
    ).toBe('server-token');

    expect(() =>
      resolveGithubToken({ headers: { 'x-github-token': 'user-gh-token' } }, disabledConfig),
    ).toThrow(ForbiddenProxyError);

    const enabledConfig = loadProxyConfig({
      GITHUB_TOKEN: 'server-token',
      ALLOW_REQUEST_TOKEN_OVERRIDE: 'true',
    });

    expect(
      resolveGithubToken(
        {
          headers: {
            authorization: 'Bearer proxy-jwt-should-not-leak',
            'x-github-token': 'user-gh-token',
          },
        },
        enabledConfig,
      ),
    ).toBe('user-gh-token');

    expect(
      resolveGithubToken(
        { headers: { authorization: 'Bearer proxy-jwt-should-not-leak' } },
        enabledConfig,
      ),
    ).toBe('server-token');
  });
});
