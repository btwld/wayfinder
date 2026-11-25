import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  BadRequestProxyError,
  UpstreamGitHubError,
} from '../../src/common/errors';
import { loadProxyConfig } from '../../src/config/proxy-config';
import { GitHubApiClient } from '../../src/github/github-api.client';

describe('GitHubApiClient (HTTP / fetch contracts)', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  function makeClient(envOverrides: Record<string, string> = {}) {
    const config = loadProxyConfig({
      GITHUB_OWNER: 'btwld',
      GITHUB_REPO: 'wayfinder',
      GITHUB_TOKEN: 'ghp_unit',
      GITHUB_RETRY_MAX_ATTEMPTS: '3',
      GITHUB_RETRY_INITIAL_DELAY_MS: '5',
      GITHUB_RETRY_MAX_DELAY_MS: '10',
      ...envOverrides,
    });
    return new GitHubApiClient(config);
  }

  it('strips trailing slash on listMatchingBranchRefs and filters sibling prefixes', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify([
          { ref: 'refs/heads/wayfinder/session/s1', object: { sha: 'sha-1' } },
          { ref: 'refs/heads/wayfinder/session-other/x', object: { sha: 'sha-2' } },
        ]),
        { status: 200, headers: { 'content-type': 'application/json' } },
      ),
    );
    vi.stubGlobal('fetch', fetchMock);

    const client = makeClient();
    const refs = await client.listMatchingBranchRefs(
      'btwld',
      'wayfinder',
      'wayfinder/session/',
      'ghp_unit',
    );

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [calledUrl] = fetchMock.mock.calls[0];
    expect(String(calledUrl)).toMatch(/\/git\/matching-refs\/heads\/wayfinder\/session$/);
    expect(refs).toEqual([{ ref: 'wayfinder/session/s1', sha: 'sha-1' }]);
  });

  it('treats 200 encoding=none and 403 too_large as too_large while preserving empty 0-byte files', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            type: 'file',
            path: 'knowledge/big.md',
            sha: 'blob-big',
            size: 2_500_000,
            encoding: 'none',
            content: '',
          }),
          { status: 200, headers: { 'content-type': 'application/json' } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            type: 'file',
            path: 'knowledge/empty.md',
            sha: 'blob-empty',
            size: 0,
            encoding: 'base64',
            content: '',
          }),
          { status: 200, headers: { 'content-type': 'application/json' } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            message: 'This API returns blobs up to 1 MB in size.',
            errors: [{ code: 'too_large', field: 'data', resource: 'Blob' }],
          }),
          { status: 403, headers: { 'content-type': 'application/json' } },
        ),
      );
    vi.stubGlobal('fetch', fetchMock);

    const client = makeClient();
    const largeRes = await client.getContent('btwld', 'wayfinder', 'knowledge/big.md', 'main');
    expect(largeRes).toEqual({
      kind: 'too_large',
      path: 'knowledge/big.md',
      sha: 'blob-big',
      size: 2_500_000,
    });

    const emptyRes = await client.getContent('btwld', 'wayfinder', 'knowledge/empty.md', 'main');
    expect(emptyRes).toEqual({
      kind: 'file',
      path: 'knowledge/empty.md',
      sha: 'blob-empty',
      size: 0,
      encoding: 'base64',
      content: '',
    });

    const forbiddenLarge = await client.getContent('btwld', 'wayfinder', 'knowledge/huge.bin', 'main');
    expect(forbiddenLarge).toEqual({
      kind: 'too_large',
      path: 'knowledge/huge.bin',
    });
  });

  it('enforces maxTarballBytes incrementally on chunked streams and wraps stream errors as 502', async () => {
    let cancelled = false;
    const chunkedStream = new ReadableStream<Uint8Array>({
      pull(controller) {
        controller.enqueue(new Uint8Array(600));
      },
      cancel() {
        cancelled = true;
      },
    });

    const errorStream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.error(new DOMException('The operation was aborted due to timeout', 'TimeoutError'));
      },
    });

    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(chunkedStream, { status: 200 }))
      .mockResolvedValueOnce(new Response(errorStream, { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    const client = makeClient({ MAX_TARBALL_BYTES: '1024', GITHUB_RETRY_MAX_ATTEMPTS: '1' });

    await expect(client.downloadTarball('btwld', 'wayfinder', 'main')).rejects.toThrow(
      BadRequestProxyError,
    );
    expect(cancelled).toBe(true);

    await expect(client.downloadTarball('btwld', 'wayfinder', 'main')).rejects.toThrow(
      UpstreamGitHubError,
    );
  });

  it('retries idempotent GETs on transient 502/503/504 and never retries POST mutations', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ message: 'Bad Gateway' }), { status: 502 }))
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            id: 1,
            name: 'wayfinder',
            full_name: 'btwld/wayfinder',
            owner: { login: 'btwld' },
            description: null,
            private: false,
            default_branch: 'main',
            html_url: 'https://github.com/btwld/wayfinder',
            archived: false,
            pushed_at: null,
            updated_at: null,
          }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(new Response(JSON.stringify({ message: 'Bad Gateway' }), { status: 502 }));
    vi.stubGlobal('fetch', fetchMock);

    const client = makeClient();
    const repo = await client.getRepo('btwld', 'wayfinder');
    expect(repo.fullName).toBe('btwld/wayfinder');
    expect(fetchMock).toHaveBeenCalledTimes(2);

    await expect(
      client.createBlob('btwld', 'wayfinder', 'hello', 'utf-8', 'ghp_unit'),
    ).rejects.toThrow(UpstreamGitHubError);
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it('uses filter=latest on check-runs, parses Link rel=next, handles delete 404/422, and derives GHE GraphQL URL', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ total_count: 0, check_runs: [] }), { status: 200 }),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify([]), {
          status: 200,
          headers: { link: '<https://api.github.com/items?page=2>; rel="next"' },
        }),
      )
      .mockResolvedValueOnce(new Response(null, { status: 404 }))
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ message: 'Reference does not exist' }), { status: 422 }),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            data: { markPullRequestReadyForReview: { pullRequest: { id: 'PR_1', isDraft: false } } },
          }),
          { status: 200 },
        ),
      );
    vi.stubGlobal('fetch', fetchMock);

    const client = makeClient({ GITHUB_API_BASE_URL: 'https://ghe.example.com/api/v3' });

    await client.listCheckRunsForRef('btwld', 'wayfinder', 'wayfinder/session/s1');
    expect(String(fetchMock.mock.calls[0][0])).toContain(
      '/commits/wayfinder/session/s1/check-runs?filter=latest&per_page=100',
    );

    const prs = await client.listPullRequests('btwld', 'wayfinder', { state: 'open' });
    expect(prs.hasNextPage).toBe(true);

    expect(await client.deleteBranchRef('btwld', 'wayfinder', 'wayfinder/session/a', 't')).toBe(false);
    expect(await client.deleteBranchRef('btwld', 'wayfinder', 'wayfinder/session/b', 't')).toBe(false);

    const ready = await client.markPullRequestReadyForReview('PR_1', 't');
    expect(ready).toEqual({ id: 'PR_1', isDraft: false });
    expect(fetchMock.mock.calls[4][0]).toBe('https://ghe.example.com/api/graphql');
  });
});
