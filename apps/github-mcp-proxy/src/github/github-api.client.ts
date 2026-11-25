import { Inject, Injectable } from '@nestjs/common';
import { BadRequestProxyError, UpstreamGitHubError } from '../common/errors';
import { encodeContentPath, encodeGitRefPath } from '../common/path-safety';
import { PROXY_CONFIG, type ProxyConfig } from '../config/proxy-config';
import type {
  CreatePullRequestInput,
  GitHubBlobResult,
  GitHubBranchRef,
  GitHubCheckRun,
  GitHubCommitRef,
  GitHubContentFileResult,
  GitHubPullRequest,
  GitHubPullRequestFile,
  GitHubRepoInfo,
  GitHubTreeEntry,
  GitHubTreeInputEntry,
  GitHubTreeResponse,
  IGitHubApiClient,
  ListPullRequestsQuery,
  MergePullRequestInput,
} from './github-api.interface';

interface RawGitHubErrorBody {
  message?: string;
  errors?: Array<{ message?: string; code?: string; field?: string; resource?: string }>;
  documentation_url?: string;
}

interface RawPullRequest {
  number: number;
  node_id: string;
  title: string;
  body: string | null;
  state: 'open' | 'closed';
  draft?: boolean;
  merged?: boolean;
  mergeable?: boolean | null;
  mergeable_state?: string | null;
  changed_files?: number;
  html_url: string;
  head: {
    ref: string;
    sha: string;
    repo?: { full_name?: string | null } | null;
    user?: { login?: string | null } | null;
  };
  base: { ref: string; sha: string };
  created_at: string;
  updated_at: string;
  merged_at: string | null;
}

const TRANSIENT_GET_STATUSES = new Set([502, 503, 504]);

function mapPullRequest(raw: RawPullRequest): GitHubPullRequest {
  return {
    number: raw.number,
    nodeId: raw.node_id,
    title: raw.title,
    body: raw.body,
    state: raw.state,
    draft: Boolean(raw.draft),
    merged: Boolean(raw.merged ?? raw.merged_at),
    mergeable: raw.mergeable ?? null,
    mergeableState: raw.mergeable_state ?? null,
    changedFiles: typeof raw.changed_files === 'number' ? raw.changed_files : null,
    htmlUrl: raw.html_url,
    headRef: raw.head.ref,
    headSha: raw.head.sha,
    headRepoFullName: raw.head.repo?.full_name ?? null,
    headOwner: raw.head.user?.login ?? null,
    baseRef: raw.base.ref,
    baseSha: raw.base.sha,
    createdAt: raw.created_at,
    updatedAt: raw.updated_at,
    mergedAt: raw.merged_at,
  };
}

function hasNextLink(linkHeader: string | null): boolean {
  if (!linkHeader) return false;
  return /<[^>]+>;\s*rel="next"/i.test(linkHeader);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function cancelBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // Ignore stream cancellation errors on teardown
  }
}

@Injectable()
export class GitHubApiClient implements IGitHubApiClient {
  private readonly graphqlUrl: string;

  constructor(@Inject(PROXY_CONFIG) private readonly config: ProxyConfig) {
    const base = this.config.github.apiBaseUrl;
    if (base.endsWith('/api/v3')) {
      this.graphqlUrl = `${base.slice(0, -'/api/v3'.length)}/api/graphql`;
    } else {
      this.graphqlUrl = `${base}/graphql`;
    }
  }

  async getRepo(owner: string, repo: string, token?: string): Promise<GitHubRepoInfo> {
    const { data } = await this.requestJson<{
      id: number;
      name: string;
      full_name: string;
      owner: { login: string };
      description: string | null;
      private: boolean;
      default_branch: string;
      html_url: string;
      archived: boolean;
      pushed_at: string | null;
      updated_at: string | null;
      permissions?: Record<string, boolean>;
    }>(`/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}`, { token });

    return {
      id: data.id,
      name: data.name,
      fullName: data.full_name,
      owner: data.owner.login,
      description: data.description,
      private: data.private,
      defaultBranch: data.default_branch,
      htmlUrl: data.html_url,
      archived: data.archived,
      pushedAt: data.pushed_at,
      updatedAt: data.updated_at,
      permissions: data.permissions,
    };
  }

  async resolveCommit(
    owner: string,
    repo: string,
    ref: string,
    token?: string,
  ): Promise<GitHubCommitRef> {
    const encodedRef = encodeGitRefPath(ref);
    const { data } = await this.requestJson<{
      sha: string;
      commit: {
        message: string;
        tree: { sha: string };
      };
    }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/commits/${encodedRef}`,
      { token },
    );

    return {
      sha: data.sha,
      treeSha: data.commit.tree.sha,
      message: data.commit.message,
    };
  }

  async getBranchRef(
    owner: string,
    repo: string,
    branch: string,
    token?: string,
  ): Promise<GitHubBranchRef | null> {
    const encoded = encodeGitRefPath(branch);
    const url = `${this.config.github.apiBaseUrl}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/git/ref/heads/${encoded}`;
    const response = await this.rawFetch(url, { method: 'GET', token });
    if (response.status === 404) {
      await cancelBody(response);
      return null;
    }
    const data = await this.parseJsonOrThrow<{
      ref: string;
      object: { sha: string };
    }>(response);
    return {
      ref: data.ref.replace(/^refs\/heads\//, ''),
      sha: data.object.sha,
    };
  }

  async listMatchingBranchRefs(
    owner: string,
    repo: string,
    prefix: string,
    token?: string,
  ): Promise<GitHubBranchRef[]> {
    const normalized = prefix.replace(/\/+$/, '');
    const encoded = encodeGitRefPath(normalized);
    const { data } = await this.requestJson<
      Array<{ ref: string; object: { sha: string } }>
    >(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/git/matching-refs/heads/${encoded}`,
      { token },
    );
    return data
      .map((item) => ({
        ref: item.ref.replace(/^refs\/heads\//, ''),
        sha: item.object.sha,
      }))
      .filter((item) => item.ref.startsWith(prefix));
  }

  async createBranchRef(
    owner: string,
    repo: string,
    branch: string,
    sha: string,
    token: string,
  ): Promise<GitHubBranchRef> {
    const { data } = await this.requestJson<{ ref: string; object: { sha: string } }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/git/refs`,
      {
        method: 'POST',
        token,
        body: {
          ref: `refs/heads/${branch}`,
          sha,
        },
      },
    );
    return {
      ref: data.ref.replace(/^refs\/heads\//, ''),
      sha: data.object.sha,
    };
  }

  async updateBranchRef(
    owner: string,
    repo: string,
    branch: string,
    sha: string,
    force: boolean,
    token: string,
  ): Promise<GitHubBranchRef> {
    const encoded = encodeGitRefPath(branch);
    const { data } = await this.requestJson<{ ref: string; object: { sha: string } }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/git/refs/heads/${encoded}`,
      {
        method: 'PATCH',
        token,
        body: { sha, force },
      },
    );
    return {
      ref: data.ref.replace(/^refs\/heads\//, ''),
      sha: data.object.sha,
    };
  }

  async deleteBranchRef(
    owner: string,
    repo: string,
    branch: string,
    token: string,
  ): Promise<boolean> {
    const encoded = encodeGitRefPath(branch);
    const url = `${this.config.github.apiBaseUrl}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/git/refs/heads/${encoded}`;
    const response = await this.rawFetch(url, { method: 'DELETE', token });
    if (response.status === 204 || response.status === 200) {
      await cancelBody(response);
      return true;
    }
    if (response.status === 404) {
      await cancelBody(response);
      return false;
    }
    const errBody = await this.safeReadErrorBody(response);
    if (
      response.status === 422 &&
      (errBody.message ?? '').toLowerCase().includes('reference does not exist')
    ) {
      return false;
    }
    throw new UpstreamGitHubError(
      response.status,
      errBody.message ?? `GitHub API DELETE failed with HTTP ${response.status}`,
      errBody.errors,
      errBody.documentation_url,
    );
  }

  async getTree(
    owner: string,
    repo: string,
    treeShaOrRef: string,
    recursive: boolean,
    token?: string,
  ): Promise<GitHubTreeResponse> {
    const encoded = encodeGitRefPath(treeShaOrRef);
    const query = recursive ? '?recursive=1' : '';
    const { data } = await this.requestJson<{
      sha: string;
      truncated: boolean;
      tree: GitHubTreeEntry[];
    }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/git/trees/${encoded}${query}`,
      { token },
    );
    return {
      sha: data.sha,
      truncated: Boolean(data.truncated),
      tree: data.tree ?? [],
    };
  }

  async getContent(
    owner: string,
    repo: string,
    path: string,
    ref: string,
    token?: string,
  ): Promise<GitHubContentFileResult> {
    const encodedPath = encodeContentPath(path);
    const qs = new URLSearchParams({ ref });
    const url = `${this.config.github.apiBaseUrl}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/contents/${encodedPath}?${qs.toString()}`;
    const response = await this.rawFetch(url, { method: 'GET', token });

    if (response.status === 403) {
      const errBody = await this.safeReadErrorBody(response);
      const isTooLarge =
        errBody.errors?.some((e) => e.code === 'too_large') ||
        (errBody.message ?? '').toLowerCase().includes('too large');
      if (isTooLarge) {
        return { kind: 'too_large', path };
      }
      throw new UpstreamGitHubError(
        response.status,
        errBody.message ?? 'GitHub API returned 403 Forbidden',
        errBody.errors,
        errBody.documentation_url,
      );
    }

    const data = await this.parseJsonOrThrow<
      | {
          type?: string;
          path: string;
          sha?: string;
          size?: number;
          encoding?: string;
          content?: string;
        }
      | Array<unknown>
    >(response);

    if (Array.isArray(data)) {
      throw new BadRequestProxyError(`Path "${path}" refers to a directory, not a file`);
    }
    if (data.type && data.type !== 'file') {
      throw new BadRequestProxyError(
        `Path "${path}" has unsupported GitHub content type "${data.type}"`,
      );
    }
    if (
      (data.content === undefined ||
        data.encoding === 'none' ||
        (data.content === '' && (data.size ?? 0) > 0)) &&
      data.sha
    ) {
      return {
        kind: 'too_large',
        path: data.path ?? path,
        sha: data.sha,
        size: data.size,
      };
    }

    return {
      kind: 'file',
      path: data.path ?? path,
      sha: data.sha,
      size: data.size,
      encoding: data.encoding,
      content: data.content,
    };
  }

  async getBlob(
    owner: string,
    repo: string,
    blobSha: string,
    token?: string,
  ): Promise<GitHubBlobResult> {
    const { data } = await this.requestJson<{
      sha: string;
      size: number;
      encoding: 'base64' | 'utf-8';
      content: string;
    }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/git/blobs/${encodeURIComponent(blobSha)}`,
      { token },
    );
    return data;
  }

  async createBlob(
    owner: string,
    repo: string,
    content: string,
    encoding: 'utf-8' | 'base64',
    token: string,
  ): Promise<{ sha: string }> {
    const { data } = await this.requestJson<{ sha: string }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/git/blobs`,
      {
        method: 'POST',
        token,
        body: { content, encoding },
      },
    );
    return { sha: data.sha };
  }

  async createTree(
    owner: string,
    repo: string,
    baseTreeSha: string,
    entries: GitHubTreeInputEntry[],
    token: string,
  ): Promise<{ sha: string }> {
    const { data } = await this.requestJson<{ sha: string }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/git/trees`,
      {
        method: 'POST',
        token,
        body: {
          base_tree: baseTreeSha,
          tree: entries,
        },
      },
    );
    return { sha: data.sha };
  }

  async createCommit(
    owner: string,
    repo: string,
    message: string,
    treeSha: string,
    parents: string[],
    token: string,
  ): Promise<{ sha: string; treeSha: string }> {
    const { data } = await this.requestJson<{ sha: string; tree: { sha: string } }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/git/commits`,
      {
        method: 'POST',
        token,
        body: {
          message,
          tree: treeSha,
          parents,
        },
      },
    );
    return { sha: data.sha, treeSha: data.tree.sha };
  }

  async downloadTarball(
    owner: string,
    repo: string,
    ref: string,
    token?: string,
  ): Promise<Buffer> {
    const encodedRef = encodeGitRefPath(ref);
    const url = `${this.config.github.apiBaseUrl}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/tarball/${encodedRef}`;
    const response = await this.rawFetch(url, { method: 'GET', token });
    if (!response.ok) {
      const errBody = await this.safeReadErrorBody(response);
      throw new UpstreamGitHubError(
        response.status,
        errBody.message ?? `GitHub tarball download failed with HTTP ${response.status}`,
        errBody.errors,
        errBody.documentation_url,
      );
    }

    const maxBytes = this.config.limits.maxTarballBytes;
    const contentLength = response.headers.get('content-length');
    if (contentLength) {
      const bytes = Number(contentLength);
      if (Number.isFinite(bytes) && bytes > maxBytes) {
        await cancelBody(response);
        throw new BadRequestProxyError(
          `Repository tarball (${bytes} bytes) exceeds limit (${maxBytes} bytes)`,
        );
      }
    }

    if (!response.body) {
      let arrayBuffer: ArrayBuffer;
      try {
        arrayBuffer = await response.arrayBuffer();
      } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        throw new UpstreamGitHubError(502, `GitHub tarball read error: ${msg}`);
      }
      const buffer = Buffer.from(arrayBuffer);
      if (buffer.length > maxBytes) {
        throw new BadRequestProxyError(
          `Repository tarball (${buffer.length} bytes) exceeds limit (${maxBytes} bytes)`,
        );
      }
      return buffer;
    }

    const reader = response.body.getReader();
    const chunks: Buffer[] = [];
    let totalBytes = 0;

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (!value) continue;
        totalBytes += value.byteLength;
        if (totalBytes > maxBytes) {
          await reader.cancel().catch(() => {});
          throw new BadRequestProxyError(
            `Repository tarball exceeds limit (${maxBytes} bytes)`,
          );
        }
        chunks.push(Buffer.from(value));
      }
    } catch (error) {
      if (error instanceof BadRequestProxyError) {
        throw error;
      }
      await reader.cancel().catch(() => {});
      const msg = error instanceof Error ? error.message : String(error);
      throw new UpstreamGitHubError(502, `GitHub tarball stream error: ${msg}`);
    }

    return Buffer.concat(chunks, totalBytes);
  }

  async createPullRequest(
    owner: string,
    repo: string,
    input: CreatePullRequestInput,
    token: string,
  ): Promise<GitHubPullRequest> {
    const { data } = await this.requestJson<RawPullRequest>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/pulls`,
      {
        method: 'POST',
        token,
        body: {
          title: input.title,
          head: input.head,
          base: input.base,
          body: input.body,
          draft: input.draft,
        },
      },
    );
    return mapPullRequest(data);
  }

  async listPullRequests(
    owner: string,
    repo: string,
    query: ListPullRequestsQuery,
    token?: string,
  ): Promise<{ items: GitHubPullRequest[]; hasNextPage: boolean }> {
    const qs = new URLSearchParams();
    if (query.state) qs.set('state', query.state);
    if (query.head) qs.set('head', query.head);
    if (query.perPage) qs.set('per_page', String(query.perPage));
    if (query.page) qs.set('page', String(query.page));

    const { data, headers } = await this.requestJson<RawPullRequest[]>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/pulls?${qs.toString()}`,
      { token },
    );

    return {
      items: data.map(mapPullRequest),
      hasNextPage: hasNextLink(headers.get('link')),
    };
  }

  async getPullRequest(
    owner: string,
    repo: string,
    prNumber: number,
    token?: string,
  ): Promise<GitHubPullRequest> {
    const { data } = await this.requestJson<RawPullRequest>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/pulls/${prNumber}`,
      { token },
    );
    return mapPullRequest(data);
  }

  async listPullRequestFiles(
    owner: string,
    repo: string,
    prNumber: number,
    page: number,
    perPage: number,
    token?: string,
  ): Promise<{ items: GitHubPullRequestFile[]; hasNextPage: boolean }> {
    const qs = new URLSearchParams({
      page: String(page),
      per_page: String(perPage),
    });
    const { data, headers } = await this.requestJson<
      Array<{
        filename: string;
        status: string;
        additions: number;
        deletions: number;
        changes: number;
        sha: string | null;
      }>
    >(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/pulls/${prNumber}/files?${qs.toString()}`,
      { token },
    );

    return {
      items: data.map((item) => ({
        filename: item.filename,
        status: item.status,
        additions: item.additions,
        deletions: item.deletions,
        changes: item.changes,
        sha: item.sha,
      })),
      hasNextPage: hasNextLink(headers.get('link')),
    };
  }

  async createIssueComment(
    owner: string,
    repo: string,
    issueNumber: number,
    body: string,
    token: string,
  ): Promise<{ id: number; htmlUrl: string }> {
    const { data } = await this.requestJson<{ id: number; html_url: string }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/issues/${issueNumber}/comments`,
      {
        method: 'POST',
        token,
        body: { body },
      },
    );
    return { id: data.id, htmlUrl: data.html_url };
  }

  async updatePullRequest(
    owner: string,
    repo: string,
    prNumber: number,
    patch: { state?: 'open' | 'closed'; title?: string; body?: string },
    token: string,
  ): Promise<GitHubPullRequest> {
    const { data } = await this.requestJson<RawPullRequest>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/pulls/${prNumber}`,
      {
        method: 'PATCH',
        token,
        body: patch,
      },
    );
    return mapPullRequest(data);
  }

  async markPullRequestReadyForReview(
    pullRequestNodeId: string,
    token: string,
  ): Promise<{ id: string; isDraft: boolean }> {
    const mutation = `
      mutation MarkPullRequestReady($pullRequestId: ID!) {
        markPullRequestReadyForReview(input: { pullRequestId: $pullRequestId }) {
          pullRequest {
            id
            isDraft
          }
        }
      }
    `;
    const response = await this.rawFetch(this.graphqlUrl, {
      method: 'POST',
      token,
      body: {
        query: mutation,
        variables: { pullRequestId: pullRequestNodeId },
      },
    });
    const payload = await this.parseJsonOrThrow<{
      data?: {
        markPullRequestReadyForReview?: {
          pullRequest?: { id: string; isDraft: boolean };
        };
      };
      errors?: Array<{ message?: string; type?: string }>;
    }>(response);

    if (payload.errors && payload.errors.length > 0) {
      throw new UpstreamGitHubError(
        422,
        payload.errors.map((e) => e.message ?? 'GraphQL error').join('; '),
        payload.errors,
      );
    }

    const pr = payload.data?.markPullRequestReadyForReview?.pullRequest;
    if (!pr) {
      throw new UpstreamGitHubError(
        502,
        'GitHub GraphQL markPullRequestReadyForReview returned no pullRequest',
      );
    }
    return pr;
  }

  async mergePullRequest(
    owner: string,
    repo: string,
    prNumber: number,
    input: MergePullRequestInput,
    token: string,
  ): Promise<{ merged: boolean; sha: string; message: string }> {
    const { data } = await this.requestJson<{
      merged: boolean;
      sha: string;
      message: string;
    }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/pulls/${prNumber}/merge`,
      {
        method: 'PUT',
        token,
        body: {
          merge_method: input.mergeMethod,
          ...(input.commitTitle ? { commit_title: input.commitTitle } : {}),
          ...(input.commitMessage ? { commit_message: input.commitMessage } : {}),
          ...(input.sha ? { sha: input.sha } : {}),
        },
      },
    );
    return data;
  }

  async listCheckRunsForRef(
    owner: string,
    repo: string,
    ref: string,
    token?: string,
  ): Promise<{ totalCount: number; checkRuns: GitHubCheckRun[] }> {
    const encodedRef = encodeGitRefPath(ref);
    const { data } = await this.requestJson<{
      total_count: number;
      check_runs: Array<{
        id: number;
        name: string;
        status: string;
        conclusion: string | null;
        html_url: string | null;
      }>;
    }>(
      `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/commits/${encodedRef}/check-runs?filter=latest&per_page=100`,
      { token },
    );

    return {
      totalCount: data.total_count,
      checkRuns: (data.check_runs ?? []).map((run) => ({
        id: run.id,
        name: run.name,
        status: run.status,
        conclusion: run.conclusion,
        htmlUrl: run.html_url,
      })),
    };
  }

  private async requestJson<T>(
    path: string,
    options: { method?: string; token?: string; body?: unknown },
  ): Promise<{ data: T; headers: Headers }> {
    const url = `${this.config.github.apiBaseUrl}${path}`;
    const response = await this.rawFetch(url, options);
    const data = await this.parseJsonOrThrow<T>(response);
    return { data, headers: response.headers };
  }

  private async rawFetch(
    url: string,
    options: { method?: string; token?: string; body?: unknown },
  ): Promise<Response> {
    const method = (options.method ?? 'GET').toUpperCase();
    const headers: Record<string, string> = {
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'wayfinder-github-mcp-proxy',
    };

    if (options.token) {
      headers.Authorization = `Bearer ${options.token}`;
    }

    let serializedBody: string | undefined;
    if (options.body !== undefined) {
      headers['Content-Type'] = 'application/json';
      serializedBody = JSON.stringify(options.body);
    }

    const maxAttempts = method === 'GET' ? Math.max(1, this.config.github.retryMaxAttempts) : 1;
    let delayMs = this.config.github.retryInitialDelayMs;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        const response = await fetch(url, {
          method,
          headers,
          body: serializedBody,
          signal: AbortSignal.timeout(this.config.github.requestTimeoutMs),
        });

        if (
          method === 'GET' &&
          TRANSIENT_GET_STATUSES.has(response.status) &&
          attempt < maxAttempts
        ) {
          await cancelBody(response);
          await sleep(delayMs);
          delayMs = Math.min(delayMs * 2, this.config.github.retryMaxDelayMs);
          continue;
        }

        return response;
      } catch (error) {
        if (attempt < maxAttempts) {
          await sleep(delayMs);
          delayMs = Math.min(delayMs * 2, this.config.github.retryMaxDelayMs);
          continue;
        }
        const msg = error instanceof Error ? error.message : String(error);
        throw new UpstreamGitHubError(502, `GitHub API network error: ${msg}`);
      }
    }

    throw new UpstreamGitHubError(502, 'GitHub API network error');
  }

  private async parseJsonOrThrow<T>(response: Response): Promise<T> {
    if (!response.ok) {
      const errBody = await this.safeReadErrorBody(response);
      throw new UpstreamGitHubError(
        response.status,
        errBody.message ?? `GitHub API returned HTTP ${response.status}`,
        errBody.errors,
        errBody.documentation_url,
      );
    }
    try {
      return (await response.json()) as T;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      throw new UpstreamGitHubError(502, `GitHub API response read error: ${msg}`);
    }
  }

  private async safeReadErrorBody(response: Response): Promise<RawGitHubErrorBody> {
    try {
      const text = await response.text();
      if (!text) return {};
      const parsed = JSON.parse(text) as RawGitHubErrorBody;
      return parsed && typeof parsed === 'object' ? parsed : { message: text };
    } catch {
      return {};
    }
  }
}
