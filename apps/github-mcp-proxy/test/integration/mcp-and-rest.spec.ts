import { MetricsService, type BearerTokenVerifier } from '@nest-mcp/server';
import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { afterEach, describe, expect, it } from 'vitest';
import { createProxyApp } from '../../src/app.factory';
import { loadProxyConfig } from '../../src/config/proxy-config';
import { FakeGitHubApi } from '../fakes/fake-github-api';

function seedStandardRepo(fakeGitHub: FakeGitHubApi) {
  const bigMarkdown = [
    '---',
    'type: Concept',
    'title: "Large Doc: Blobs Fallback"',
    'status: verified',
    'tags: [large, blobs]',
    'relationships:',
    '  - relationship: relates-to',
    '    resource: /concepts/alpha.md',
    '---',
    '',
    '# Large Document',
    'A'.repeat(1024 * 1024 + 32),
  ].join('\n');

  fakeGitHub.seedRepository('btwld', 'wayfinder', {
    'wayfinder.json': JSON.stringify({
      version: 1,
      profiles: {
        bitwild: {
          source: { git: 'https://github.com/btwld/wayfinder', ref: 'main', path: 'profiles/bitwild' },
          applies_to: ['./knowledge'],
        },
      },
    }),
    'wayfinder.lock': 'version: 1\nlocked: true\n',
    'knowledge/index.md': '---\nokf_version: "0.2"\n---\n# Knowledge Index\n',
    'knowledge/log.md': '# Knowledge Log\n',
    'knowledge/concepts/alpha.md': [
      '---',
      'type: Decision',
      'title: "Cache: Strategy"',
      'status: active',
      'tags: [architecture, cache]',
      'relationships:',
      '  - relationship: depends-on',
      '    resource: /concepts/beta.md',
      '---',
      '',
      'Use deterministic cache keys.',
    ].join('\n'),
    'knowledge/assets/diagram.png': Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00, 0x01]),
    'knowledge/large-doc.md': bigMarkdown,
    'README.md': '# Repo README\nOutside bundle.\n',
  });
  fakeGitHub.forceTooLargePaths.add('knowledge/large-doc.md');
}

describe('MCP Streamable HTTP + REST API integration', () => {
  const appsToClose: INestApplication[] = [];

  afterEach(async () => {
    while (appsToClose.length > 0) {
      const app = appsToClose.pop()!;
      await app.close();
    }
  });

  async function bootApp(
    envOverrides: Record<string, string>,
    fakeGitHub: FakeGitHubApi,
    bearerVerifier?: BearerTokenVerifier,
  ) {
    const config = loadProxyConfig({
      GITHUB_OWNER: 'btwld',
      GITHUB_REPO: 'wayfinder',
      GITHUB_TOKEN: 'server-gh-token',
      SESSION_MERGE_RETRY_INITIAL_DELAY_MS: '5',
      SESSION_MERGE_RETRY_MAX_DELAY_MS: '10',
      ...envOverrides,
    });
    const ctx = await createProxyApp({
      config,
      githubApiClient: fakeGitHub,
      bearerVerifier,
      logger: false,
    });
    await ctx.app.init();
    appsToClose.push(ctx.app);
    return ctx;
  }

  it('serves Streamable HTTP /mcp tools, resource templates, and REST /api/* with API key auth', async () => {
    const fakeGitHub = new FakeGitHubApi();
    seedStandardRepo(fakeGitHub);

    const { app } = await bootApp(
      {
        PROXY_AUTH_MODE: 'api-key',
        PROXY_API_KEYS: 'secret-api-key',
      },
      fakeGitHub,
    );
    const server = app.getHttpServer();

    // /health is public
    const health = await request(server).get('/health').expect(200);
    expect(health.body).toMatchObject({
      status: 'ok',
      stateless: true,
      authMode: 'api-key',
    });

    // Unauthenticated REST & MCP fail with 401
    await request(server).get('/api/repo').expect(401);
    await request(server)
      .post('/mcp')
      .set('Accept', 'application/json, text/event-stream')
      .send({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} })
      .expect(401);

    // MCP initialize + tools/list
    const initRes = await request(server)
      .post('/mcp')
      .set('x-api-key', 'secret-api-key')
      .set('Accept', 'application/json, text/event-stream')
      .send({
        jsonrpc: '2.0',
        id: 1,
        method: 'initialize',
        params: {
          protocolVersion: '2025-03-26',
          capabilities: {},
          clientInfo: { name: 'vitest', version: '1.0.0' },
        },
      })
      .expect(200);
    expect(initRes.body.result.serverInfo.name).toBe('wayfinder-github-mcp-proxy');

    const toolsList = await request(server)
      .post('/mcp')
      .set('x-api-key', 'secret-api-key')
      .set('Accept', 'application/json, text/event-stream')
      .send({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} })
      .expect(200);
    const toolNames = (toolsList.body.result.tools as Array<{ name: string }>).map((t) => t.name);
    expect(toolNames).toEqual(
      expect.arrayContaining([
        'repo_info',
        'pull_tree',
        'pull_file',
        'pull_bundle',
        'search_repository',
        'start_session',
        'session_write',
        'list_sessions',
        'get_session',
        'commit_session',
        'close_session',
      ]),
    );

    // REST: repo, tree, file (>1MB blob fallback + yaml frontmatter), bundle (single tarball)
    const repoRes = await request(server)
      .get('/api/repo')
      .set('x-api-key', 'secret-api-key')
      .expect(200);
    expect(repoRes.body.defaultBranch).toBe('main');

    const treeRes = await request(server)
      .get('/api/tree')
      .set('x-api-key', 'secret-api-key')
      .expect(200);
    const kindsByPath = Object.fromEntries(
      (treeRes.body.entries as Array<{ path: string; kind: string }>).map((e) => [e.path, e.kind]),
    );
    expect(kindsByPath['wayfinder.json']).toBe('config');
    expect(kindsByPath['knowledge/index.md']).toBe('index');
    expect(kindsByPath['knowledge/log.md']).toBe('log');
    expect(kindsByPath['knowledge/concepts/alpha.md']).toBe('concept');
    expect(kindsByPath['knowledge/assets/diagram.png']).toBe('attachment');
    expect(kindsByPath['README.md']).toBe('other');

    const largeFileRes = await request(server)
      .get('/api/file')
      .query({ path: 'knowledge/large-doc.md' })
      .set('x-api-key', 'secret-api-key')
      .expect(200);
    expect(largeFileRes.body.fetchedVia).toBe('git-blob');
    expect(largeFileRes.body.frontmatter.title).toBe('Large Doc: Blobs Fallback');
    expect(largeFileRes.body.frontmatter.relationships).toHaveLength(1);

    const downloadsBefore = fakeGitHub.downloadTarballCount;
    const bundleRes = await request(server)
      .get('/api/bundle')
      .set('x-api-key', 'secret-api-key')
      .expect(200);
    expect(fakeGitHub.downloadTarballCount - downloadsBefore).toBe(1);
    expect(bundleRes.body.bundleRoots).toEqual(['knowledge']);
    expect(bundleRes.body.wayfinderLock).toContain('locked: true');
    expect(bundleRes.body.omittedAttachments.map((a: { path: string }) => a.path)).toEqual([
      'knowledge/assets/diagram.png',
    ]);
    expect(bundleRes.body.documents.some((d: { path: string }) => d.path === 'README.md')).toBe(false);

    // Mutually exclusive ref + sessionId rejected
    await request(server)
      .get('/api/file')
      .query({ path: 'knowledge/index.md', ref: 'main', sessionId: 's1' })
      .set('x-api-key', 'secret-api-key')
      .expect(400);

    // Start session & write via MCP tool, then search uncommitted session branch via REST & read MCP resource templates
    const mcpWrite = await request(server)
      .post('/mcp')
      .set('x-api-key', 'secret-api-key')
      .set('Accept', 'application/json, text/event-stream')
      .send({
        jsonrpc: '2.0',
        id: 3,
        method: 'tools/call',
        params: {
          name: 'session_write',
          arguments: {
            sessionId: 'mcp-sess-1',
            autoStart: true,
            files: [
              {
                path: 'knowledge/concepts/gamma.md',
                content: '---\ntype: Decision\ntitle: "Gamma Uncommitted"\nstatus: draft\ntags: [experimental]\n---\nFresh session concept.\n',
              },
            ],
          },
        },
      })
      .expect(200);
    const writePayload = JSON.parse(mcpWrite.body.result.content[0].text);
    expect(writePayload.prNumber).toBe(1);

    // Search uncommitted session branch
    const searchRes = await request(server)
      .get('/api/search')
      .query({ sessionId: 'mcp-sess-1', type: 'Decision', tag: 'experimental', query: 'Fresh session' })
      .set('x-api-key', 'secret-api-key')
      .expect(200);
    expect(searchRes.body.totalMatches).toBe(1);
    expect(searchRes.body.results[0].path).toBe('knowledge/concepts/gamma.md');

    // Read MCP resource templates
    const sessionResource = await request(server)
      .post('/mcp')
      .set('x-api-key', 'secret-api-key')
      .set('Accept', 'application/json, text/event-stream')
      .send({
        jsonrpc: '2.0',
        id: 4,
        method: 'resources/read',
        params: { uri: 'wayfinder-github://btwld/wayfinder/sessions/mcp-sess-1' },
      })
      .expect(200);
    const sessionDoc = JSON.parse(sessionResource.body.result.contents[0].text);
    expect(sessionDoc.sessionId).toBe('mcp-sess-1');
    expect(sessionDoc.state).toBe('open');

    const bundleResource = await request(server)
      .post('/mcp')
      .set('x-api-key', 'secret-api-key')
      .set('Accept', 'application/json, text/event-stream')
      .send({
        jsonrpc: '2.0',
        id: 5,
        method: 'resources/read',
        params: {
          uri: `wayfinder-github://btwld/wayfinder/bundle/${encodeURIComponent('wayfinder/session/mcp-sess-1')}`,
        },
      })
      .expect(200);
    const bundleDoc = JSON.parse(bundleResource.body.result.contents[0].text);
    expect(
      bundleDoc.documents.some((d: { path: string }) => d.path === 'knowledge/concepts/gamma.md'),
    ).toBe(true);

    // Commit session via REST
    const commitRes = await request(server)
      .post('/api/sessions/mcp-sess-1/commit')
      .set('x-api-key', 'secret-api-key')
      .send({ mergeMethod: 'squash' })
      .expect(201);
    expect(commitRes.body.merged).toBe(true);
    expect(commitRes.body.branchDeleted).toBe(true);

    // Bodyless POSTs (no JSON body, no Content-Type), query coercion, listSessions, base64 write + binary read, and 403 no-sha blob fallback
    await request(server)
      .post('/api/sessions')
      .set('x-api-key', 'secret-api-key')
      .expect(201);

    const listRest = await request(server)
      .get('/api/sessions')
      .query({ state: 'open', limit: '5', page: '1' })
      .set('x-api-key', 'secret-api-key')
      .expect(200);
    expect(listRest.body.sessions).toHaveLength(1);
    const bodylessSessionId = listRest.body.sessions[0].sessionId as string;

    const mcpList = await request(server)
      .post('/mcp')
      .set('x-api-key', 'secret-api-key')
      .set('Accept', 'application/json, text/event-stream')
      .send({
        jsonrpc: '2.0',
        id: 6,
        method: 'tools/call',
        params: { name: 'list_sessions', arguments: { state: 'open' } },
      })
      .expect(200);
    const mcpListData = JSON.parse(mcpList.body.result.content[0].text);
    expect(mcpListData.sessions.map((s: { sessionId: string }) => s.sessionId)).toContain(
      bodylessSessionId,
    );

    // Binary base64 write via REST and read back
    const pngBytes = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00, 0x02]);
    await request(server)
      .post(`/api/sessions/${bodylessSessionId}/write`)
      .set('x-api-key', 'secret-api-key')
      .send({
        files: [
          {
            path: 'knowledge/assets/icon.png',
            encoding: 'base64',
            content: pngBytes.toString('base64'),
          },
        ],
      })
      .expect(201);

    const binaryRead = await request(server)
      .get('/api/file')
      .query({ sessionId: bodylessSessionId, path: 'knowledge/assets/icon.png' })
      .set('x-api-key', 'secret-api-key')
      .expect(200);
    expect(binaryRead.body.encoding).toBe('base64');
    expect(binaryRead.body.binary).toBe(true);
    expect(binaryRead.body.content).toBe(pngBytes.toString('base64'));

    // Bodyless POST close
    const bodylessClose = await request(server)
      .post(`/api/sessions/${bodylessSessionId}/close`)
      .set('x-api-key', 'secret-api-key')
      .expect(201);
    expect(bodylessClose.body.state).toBe('closed');
    expect(bodylessClose.body.branchDeleted).toBe(true);

    // Bodyless POST commit
    await request(server)
      .post('/api/sessions/write')
      .set('x-api-key', 'secret-api-key')
      .send({
        sessionId: 'bodyless-commit',
        autoStart: true,
        files: [{ path: 'knowledge/bodyless.md', content: '# Bodyless\n' }],
      })
      .expect(201);
    const bodylessCommit = await request(server)
      .post('/api/sessions/bodyless-commit/commit')
      .set('x-api-key', 'secret-api-key')
      .expect(201);
    expect(bodylessCommit.body.merged).toBe(true);

    // Query coercion (recursive=false, limit=2) and 403 too_large (no sha) tree-lookup fallback
    const nonRecursiveTree = await request(server)
      .get('/api/tree')
      .query({ recursive: 'false', limit: '2' })
      .set('x-api-key', 'secret-api-key')
      .expect(200);
    expect(nonRecursiveTree.body.returnedCount).toBeLessThanOrEqual(2);
    expect(
      (nonRecursiveTree.body.entries as Array<{ path: string }>).every(
        (e) => !e.path.includes('/'),
      ),
    ).toBe(true);

    fakeGitHub.forceTooLargeNoShaPaths.add('knowledge/concepts/alpha.md');
    const noShaBlobRead = await request(server)
      .get('/api/file')
      .query({ path: 'knowledge/concepts/alpha.md' })
      .set('x-api-key', 'secret-api-key')
      .expect(200);
    expect(noShaBlobRead.body.fetchedVia).toBe('git-blob');
    expect(noShaBlobRead.body.frontmatter.title).toBe('Cache: Strategy');
  });

  it('enforces ALLOWED_REPOS, x-github-token override, non-Bearer passthrough, and records MCP metrics', async () => {
    const fakeGitHub = new FakeGitHubApi();
    seedStandardRepo(fakeGitHub);
    fakeGitHub.seedRepository('other', 'forbidden-repo', { 'README.md': 'secret' });

    const { app } = await bootApp(
      {
        PROXY_AUTH_MODE: 'api-key',
        PROXY_API_KEYS: 'k1',
        ALLOW_REQUEST_TOKEN_OVERRIDE: 'true',
      },
      fakeGitHub,
    );
    const server = app.getHttpServer();

    // Disallowed repo blocked on REST
    await request(server)
      .get('/api/repo')
      .query({ owner: 'other', repo: 'forbidden-repo' })
      .set('x-api-key', 'k1')
      .expect(403);

    // Disallowed repo blocked on MCP and recorded as failed metric via ProxyMcpExceptionFilter
    const mcpErr = await request(server)
      .post('/mcp')
      .set('x-api-key', 'k1')
      .set('Accept', 'application/json, text/event-stream')
      .send({
        jsonrpc: '2.0',
        id: 10,
        method: 'tools/call',
        params: {
          name: 'repo_info',
          arguments: { owner: 'other', repo: 'forbidden-repo' },
        },
      })
      .expect(200);
    expect(mcpErr.body.result.isError).toBe(true);
    expect(mcpErr.body.result.content[0].text).toContain('FORBIDDEN');

    const metrics = app.get(MetricsService);
    const repoInfoMetrics = metrics.getToolMetrics('repo_info');
    expect(repoInfoMetrics?.errorCount).toBeGreaterThanOrEqual(1);

    // x-github-token overrides server token; Authorization: ApiKey/Bearer is NEVER passed to GitHub
    fakeGitHub.calls.length = 0;
    await request(server)
      .get('/api/repo')
      .set('Authorization', 'ApiKey k1')
      .set('x-github-token', 'caller-gh-token')
      .expect(200);
    expect(fakeGitHub.calls.at(-1)?.token).toBe('caller-gh-token');
  });

  it('supports Firebase auth mode and avoids CORS credentials collision on /.well-known/*', async () => {
    const fakeGitHub = new FakeGitHubApi();
    seedStandardRepo(fakeGitHub);

    const fbVerifier: BearerTokenVerifier = {
      async verify(token: string) {
        if (token !== 'valid-firebase-id-token') return null;
        return {
          token,
          clientId: 'firebase-client',
          scopes: [],
          expiresAt: Math.floor(Date.now() / 1000) + 3600,
          extra: { sub: 'firebase-uid-1' },
        };
      },
    };

    const { app } = await bootApp(
      {
        PROXY_AUTH_MODE: 'firebase',
        FIREBASE_AUTH_PROJECT_ID: 'wayfinder-test-proj',
        MCP_AUTH_RESOURCE: 'https://proxy.example.com/mcp',
        CORS_ORIGINS: 'https://allowed.example.com',
      },
      fakeGitHub,
      fbVerifier,
    );
    const server = app.getHttpServer();

    await request(server).get('/api/repo').expect(401);
    await request(server)
      .get('/api/repo')
      .set('Authorization', 'Bearer valid-firebase-id-token')
      .expect(200);

    const wk = await request(server)
      .get('/.well-known/oauth-protected-resource')
      .set('Origin', 'https://allowed.example.com')
      .expect(200);
    expect(wk.headers['access-control-allow-credentials']).toBeUndefined();
    expect(wk.body.authorization_servers).toEqual([
      'https://securetoken.google.com/wayfinder-test-proj',
    ]);
  });

  it('supports OAuth bearer verification on both /mcp and /api/* and never leaks Bearer to GitHub', async () => {
    const fakeGitHub = new FakeGitHubApi();
    seedStandardRepo(fakeGitHub);

    const mockVerifier: BearerTokenVerifier = {
      async verify(token: string) {
        if (token !== 'valid-oauth-jwt') return null;
        return {
          token,
          clientId: 'client-1',
          scopes: ['wayfinder:read'],
          expiresAt: Math.floor(Date.now() / 1000) + 3600,
          extra: { sub: 'user-1' },
        };
      },
    };

    const { app } = await bootApp(
      {
        PROXY_AUTH_MODE: 'oauth',
        MCP_AUTH_RESOURCE: 'https://proxy.example.com/mcp',
        MCP_AUTH_AUTHORIZATION_SERVERS: 'https://auth.example.com',
        MCP_AUTH_JWKS_URI: 'https://auth.example.com/.well-known/jwks.json',
      },
      fakeGitHub,
      mockVerifier,
    );
    const server = app.getHttpServer();

    await request(server).get('/api/repo').expect(401);

    fakeGitHub.calls.length = 0;
    await request(server)
      .get('/api/repo')
      .set('Authorization', 'Bearer valid-oauth-jwt')
      .expect(200);
    // GitHub received the configured server token, NEVER 'valid-oauth-jwt'
    expect(fakeGitHub.calls.at(-1)?.token).toBe('server-gh-token');

    const mcpOk = await request(server)
      .post('/mcp')
      .set('Authorization', 'Bearer valid-oauth-jwt')
      .set('Accept', 'application/json, text/event-stream')
      .send({
        jsonrpc: '2.0',
        id: 20,
        method: 'tools/call',
        params: { name: 'repo_info', arguments: {} },
      })
      .expect(200);
    expect(mcpOk.body.result.content[0].text).toContain('btwld/wayfinder');
  });

  it('enforces explicit CORS_ORIGINS allowlist and fails closed when auth is unconfigured', async () => {
    const fakeGitHub = new FakeGitHubApi();
    seedStandardRepo(fakeGitHub);

    // Fail-closed when no auth configured on both REST and /mcp
    const unconfigured = await bootApp({}, fakeGitHub);
    await request(unconfigured.app.getHttpServer()).get('/health').expect(200);
    await request(unconfigured.app.getHttpServer()).get('/api/repo').expect(401);
    await request(unconfigured.app.getHttpServer())
      .post('/mcp')
      .set('Accept', 'application/json, text/event-stream')
      .send({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} })
      .expect(401);

    // Explicit CORS_ORIGINS
    const corsCtx = await bootApp(
      {
        ALLOW_UNAUTHENTICATED_ACCESS: 'true',
        CORS_ORIGINS: 'https://allowed.example.com',
      },
      fakeGitHub,
    );
    const corsServer = corsCtx.app.getHttpServer();

    const allowedRes = await request(corsServer)
      .get('/health')
      .set('Origin', 'https://allowed.example.com')
      .expect(200);
    expect(allowedRes.headers['access-control-allow-origin']).toBe('https://allowed.example.com');

    await request(corsServer)
      .get('/health')
      .set('Origin', 'https://evil.example.com')
      .expect(403);
  });
});
