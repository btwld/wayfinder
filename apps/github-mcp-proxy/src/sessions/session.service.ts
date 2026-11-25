import { randomBytes } from 'node:crypto';
import { Inject, Injectable } from '@nestjs/common';
import {
  BadRequestProxyError,
  ConflictProxyError,
  NotFoundProxyError,
  UnprocessableProxyError,
  UpstreamGitHubError,
} from '../common/errors';
import {
  assertSafeRepoPath,
  assertSafeSessionId,
  assertSafeWriteBatch,
} from '../common/path-safety';
import { PROXY_CONFIG, type ProxyConfig } from '../config/proxy-config';
import { resolveAndAuthorizeRepoTarget } from '../config/repo-target';
import {
  GITHUB_API_CLIENT,
  type GitHubCheckRun,
  type GitHubPullRequest,
  type GitHubPullRequestFile,
  type GitHubTreeInputEntry,
  type IGitHubApiClient,
} from '../github/github-api.interface';
import type {
  CloseSessionInput,
  CommitSessionInput,
  FileWriteOperationInput,
  GetSessionInput,
  ListSessionsInput,
  SessionWriteInput,
  StartSessionInput,
} from '../schemas/proxy.schemas';

export interface SessionSummary {
  sessionId: string;
  owner: string;
  repo: string;
  branch: string;
  state: 'pending' | 'open' | 'closed' | 'merged';
  headSha: string;
  baseBranch: string | null;
  baseSha: string | null;
  prNumber: number | null;
  prUrl: string | null;
  title: string | null;
  draft: boolean;
  mergeable: boolean | null;
  mergeableState: string | null;
  changedFiles: number | null;
  createdAt?: string;
  updatedAt?: string;
  mergedAt?: string | null;
}

export interface SessionDetails extends SessionSummary {
  description: string | null;
  files: GitHubPullRequestFile[];
  filesTruncated: boolean;
}

const PASSING_CHECK_CONCLUSIONS = new Set(['success', 'neutral', 'skipped']);

function generateSessionId(): string {
  const now = new Date();
  const y = now.getUTCFullYear();
  const m = String(now.getUTCMonth() + 1).padStart(2, '0');
  const d = String(now.getUTCDate()).padStart(2, '0');
  return `${y}${m}${d}-${randomBytes(4).toString('hex')}`;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isBranchAlreadyExistsError(error: unknown): boolean {
  if (!(error instanceof UpstreamGitHubError)) return false;
  return (
    error.githubStatus === 422 &&
    error.message.toLowerCase().includes('reference already exists')
  );
}

function isNonFastForwardError(error: unknown): boolean {
  if (!(error instanceof UpstreamGitHubError)) return false;
  const msg = error.message.toLowerCase();
  return (
    error.githubStatus === 422 &&
    (msg.includes('not a fast forward') || msg.includes('reference cannot be updated'))
  );
}

function isDraftUnsupportedError(error: unknown): boolean {
  if (!(error instanceof UpstreamGitHubError)) return false;
  if (error.githubStatus !== 422 && error.githubStatus !== 403) return false;
  const msg = error.message.toLowerCase();
  const details = JSON.stringify(error.githubErrors ?? []).toLowerCase();
  return (
    msg.includes('draft') ||
    details.includes('draft') ||
    msg.includes('plan') ||
    msg.includes('upgrade')
  );
}

function isTransientMerge405(error: unknown): boolean {
  if (!(error instanceof UpstreamGitHubError)) return false;
  if (error.githubStatus !== 405) return false;
  const msg = error.message.toLowerCase();
  return (
    msg.includes('not mergeable') ||
    msg.includes('still being computed') ||
    msg.includes('try again')
  );
}

async function runWithConcurrency<T, R>(
  items: T[],
  limit: number,
  worker: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let nextIndex = 0;

  async function runWorker(): Promise<void> {
    while (nextIndex < items.length) {
      const idx = nextIndex++;
      results[idx] = await worker(items[idx]);
    }
  }

  const workerCount = Math.min(limit, items.length);
  await Promise.all(Array.from({ length: workerCount }, () => runWorker()));
  return results;
}

@Injectable()
export class SessionService {
  constructor(
    @Inject(PROXY_CONFIG) private readonly config: ProxyConfig,
    @Inject(GITHUB_API_CLIENT) private readonly github: IGitHubApiClient,
  ) {}

  branchForSession(sessionId: string): string {
    return `${this.config.sessions.branchPrefix}${assertSafeSessionId(sessionId)}`;
  }

  extractSessionIdFromBranch(branch: string): string | null {
    const prefix = this.config.sessions.branchPrefix;
    return branch.startsWith(prefix) ? branch.slice(prefix.length) : null;
  }

  async startSession(input: StartSessionInput, token: string): Promise<SessionSummary> {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    const sessionId = input.sessionId
      ? assertSafeSessionId(input.sessionId)
      : generateSessionId();
    const branch = this.branchForSession(sessionId);

    const files = input.files ?? [];
    if (files.length > 0) {
      assertSafeWriteBatch(files);
    }

    const repoInfo = await this.github.getRepo(owner, repo, token);
    const requestedBaseBranch = input.baseBranch?.trim();
    const baseBranch = requestedBaseBranch || repoInfo.defaultBranch;

    if (files.length === 0) {
      if (
        (requestedBaseBranch && requestedBaseBranch !== repoInfo.defaultBranch) ||
        input.title !== undefined ||
        input.description !== undefined ||
        input.draft === false
      ) {
        throw new BadRequestProxyError(
          'Lazy start_session without initial files cannot set non-default baseBranch or custom PR metadata (title, description, draft=false); pass initial files or supply them on the first session_write.',
        );
      }
    }

    const baseCommit = await this.github.resolveCommit(owner, repo, baseBranch, token);

    try {
      await this.github.createBranchRef(owner, repo, branch, baseCommit.sha, token);
    } catch (error) {
      if (isBranchAlreadyExistsError(error)) {
        throw new ConflictProxyError(
          `Session "${sessionId}" branch "${branch}" already exists`,
          { sessionId, branch },
        );
      }
      throw error;
    }

    if (files.length === 0) {
      return {
        sessionId,
        owner,
        repo,
        branch,
        state: 'pending',
        headSha: baseCommit.sha,
        baseBranch,
        baseSha: baseCommit.sha,
        prNumber: null,
        prUrl: null,
        title: null,
        draft: true,
        mergeable: null,
        mergeableState: null,
        changedFiles: 0,
      };
    }

    try {
      const commitResult = await this.commitFilesToBranch(
        owner,
        repo,
        branch,
        baseCommit.sha,
        baseCommit.treeSha,
        files,
        input.commitMessage ?? `wayfinder: start session ${sessionId}`,
        token,
      );

      const pr = await this.openPullRequestWithDraftFallback(
        owner,
        repo,
        {
          title: input.title ?? this.defaultPrTitle(sessionId),
          head: branch,
          base: baseBranch,
          body: input.description ?? this.defaultPrBody(sessionId),
          draft: input.draft ?? true,
        },
        token,
      );

      return {
        sessionId,
        owner,
        repo,
        branch,
        state: 'open',
        headSha: commitResult.commitSha,
        baseBranch,
        baseSha: baseCommit.sha,
        prNumber: pr.number,
        prUrl: pr.htmlUrl,
        title: pr.title,
        draft: pr.draft,
        mergeable: pr.mergeable,
        mergeableState: pr.mergeableState,
        changedFiles: pr.changedFiles,
        createdAt: pr.createdAt,
        updatedAt: pr.updatedAt,
        mergedAt: pr.mergedAt,
      };
    } catch (error) {
      await this.rollbackOrphanBranch(owner, repo, branch, token);
      throw error;
    }
  }

  async sessionWrite(input: SessionWriteInput, token: string) {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    assertSafeWriteBatch(input.files);

    const sessionId = input.sessionId
      ? assertSafeSessionId(input.sessionId)
      : input.autoStart
        ? generateSessionId()
        : (() => {
            throw new BadRequestProxyError('sessionId is required unless autoStart is true');
          })();

    const branch = this.branchForSession(sessionId);
    let existingBranch = await this.github.getBranchRef(owner, repo, branch, token);
    let createdBranch = false;
    let resolvedBaseBranch = input.baseBranch?.trim();

    if (!existingBranch) {
      if (!input.autoStart) {
        throw new NotFoundProxyError(
          `Session "${sessionId}" not found (branch "${branch}" does not exist)`,
          { sessionId, branch },
        );
      }

      const repoInfo = await this.github.getRepo(owner, repo, token);
      resolvedBaseBranch = resolvedBaseBranch || repoInfo.defaultBranch;
      const baseCommit = await this.github.resolveCommit(owner, repo, resolvedBaseBranch, token);

      if (input.expectedHeadSha && input.expectedHeadSha !== baseCommit.sha) {
        throw new ConflictProxyError(
          `Expected head SHA ${input.expectedHeadSha}, but base branch "${resolvedBaseBranch}" is at ${baseCommit.sha}`,
          { expectedHeadSha: input.expectedHeadSha, actualHeadSha: baseCommit.sha },
        );
      }

      try {
        existingBranch = await this.github.createBranchRef(
          owner,
          repo,
          branch,
          baseCommit.sha,
          token,
        );
        createdBranch = true;
      } catch (error) {
        if (isBranchAlreadyExistsError(error)) {
          throw new ConflictProxyError(
            `Session "${sessionId}" branch "${branch}" was created concurrently`,
            { sessionId, branch },
          );
        }
        throw error;
      }
    }

    const previousHeadSha = existingBranch.sha;
    if (input.expectedHeadSha && input.expectedHeadSha !== previousHeadSha) {
      throw new ConflictProxyError(
        `Optimistic concurrency failure: expected head SHA ${input.expectedHeadSha}, got ${previousHeadSha}`,
        { expectedHeadSha: input.expectedHeadSha, actualHeadSha: previousHeadSha, sessionId },
      );
    }

    try {
      const headCommit = await this.github.resolveCommit(owner, repo, previousHeadSha, token);
      const commitMessage =
        input.commitMessage ?? `wayfinder: write ${input.files.length} change(s) in ${sessionId}`;

      const commitResult = await this.commitFilesToBranch(
        owner,
        repo,
        branch,
        previousHeadSha,
        headCommit.treeSha,
        input.files,
        commitMessage,
        token,
      );

      let pr = await this.findSessionPullRequest(owner, repo, branch, 'open', token);
      if (!pr) {
        const baseBranch = resolvedBaseBranch || (await this.github.getRepo(owner, repo, token)).defaultBranch;
        pr = await this.openPullRequestWithDraftFallback(
          owner,
          repo,
          {
            title: input.title ?? this.defaultPrTitle(sessionId),
            head: branch,
            base: baseBranch,
            body: input.description ?? this.defaultPrBody(sessionId),
            draft: input.draft ?? true,
          },
          token,
        );
      }

      const writtenPaths = input.files.filter((f) => !f.delete).map((f) => assertSafeRepoPath(f.path));
      const deletedPaths = input.files.filter((f) => f.delete).map((f) => assertSafeRepoPath(f.path));

      return {
        sessionId,
        owner,
        repo,
        branch,
        autoStarted: createdBranch,
        previousHeadSha,
        commitSha: commitResult.commitSha,
        treeSha: commitResult.treeSha,
        commitMessage,
        prNumber: pr.number,
        prUrl: pr.htmlUrl,
        draft: pr.draft,
        writtenPaths,
        deletedPaths,
      };
    } catch (error) {
      if (createdBranch) {
        await this.rollbackOrphanBranch(owner, repo, branch, token);
      }
      throw error;
    }
  }

  async listSessions(input: ListSessionsInput, token?: string) {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    const state = input.state ?? 'open';
    const limit = input.limit ?? 25;
    const page = input.page ?? 1;

    const allSessions: SessionSummary[] = [];
    const openBranchesWithPr = new Set<string>();
    const seenPrHeadShasByBranch = new Map<string, Set<string>>();
    const expectedRepoSlug = `${owner}/${repo}`.toLowerCase();
    let truncated = false;
    let ghPage = 1;

    while (ghPage <= this.config.limits.maxListSessionPages) {
      const result = await this.github.listPullRequests(
        owner,
        repo,
        { state, perPage: 100, page: ghPage },
        token,
      );

      for (const pr of result.items) {
        if (
          pr.headRepoFullName &&
          pr.headRepoFullName.toLowerCase() !== expectedRepoSlug
        ) {
          continue;
        }
        if (
          !pr.headRepoFullName &&
          pr.headOwner &&
          pr.headOwner.toLowerCase() !== owner.toLowerCase()
        ) {
          continue;
        }
        const sessionId = this.extractSessionIdFromBranch(pr.headRef);
        if (!sessionId) continue;
        if (pr.state === 'open') {
          openBranchesWithPr.add(pr.headRef);
        }
        let shas = seenPrHeadShasByBranch.get(pr.headRef);
        if (!shas) {
          shas = new Set<string>();
          seenPrHeadShasByBranch.set(pr.headRef, shas);
        }
        shas.add(pr.headSha);
        allSessions.push(this.prToSessionSummary(sessionId, owner, repo, pr));
      }

      if (!result.hasNextPage) {
        break;
      }
      ghPage++;
      if (ghPage > this.config.limits.maxListSessionPages) {
        truncated = true;
      }
    }

    if (state === 'open' || state === 'all') {
      const refs = await this.github.listMatchingBranchRefs(
        owner,
        repo,
        this.config.sessions.branchPrefix,
        token,
      );
      const candidates = refs.filter((branchRef) => {
        if (openBranchesWithPr.has(branchRef.ref)) return false;
        if (seenPrHeadShasByBranch.get(branchRef.ref)?.has(branchRef.sha)) return false;
        return this.extractSessionIdFromBranch(branchRef.ref) !== null;
      });

      const pendingBranches =
        state === 'open' && candidates.length > 0
          ? (
              await runWithConcurrency(candidates, 6, async (branchRef) => {
                const closedPr = await this.findSessionPullRequest(
                  owner,
                  repo,
                  branchRef.ref,
                  'closed',
                  token,
                );
                if (closedPr && closedPr.headSha === branchRef.sha) {
                  return null;
                }
                return branchRef;
              })
            ).filter((b): b is NonNullable<typeof b> => b !== null)
          : candidates;

      for (const branchRef of pendingBranches) {
        const sessionId = this.extractSessionIdFromBranch(branchRef.ref)!;
        allSessions.push({
          sessionId,
          owner,
          repo,
          branch: branchRef.ref,
          state: 'pending',
          headSha: branchRef.sha,
          baseBranch: null,
          baseSha: null,
          prNumber: null,
          prUrl: null,
          title: null,
          draft: true,
          mergeable: null,
          mergeableState: null,
          changedFiles: 0,
        });
      }
    }

    const totalFound = allSessions.length;
    const startIndex = (page - 1) * limit;
    const sessions = allSessions.slice(startIndex, startIndex + limit);

    const indicesToHydrate = sessions
      .map((s, idx) =>
        s.prNumber !== null && (s.changedFiles === null || s.mergeable === null)
          ? idx
          : -1,
      )
      .filter((idx) => idx !== -1);

    if (indicesToHydrate.length > 0) {
      await runWithConcurrency(indicesToHydrate, 6, async (idx) => {
        const entry = sessions[idx];
        const hydrated = await this.github.getPullRequest(owner, repo, entry.prNumber!, token);
        sessions[idx] = this.prToSessionSummary(entry.sessionId, owner, repo, hydrated);
      });
    }

    const hasMore = startIndex + sessions.length < totalFound || truncated;

    return {
      owner,
      repo,
      state,
      page,
      limit,
      totalFound,
      totalReturned: sessions.length,
      hasMore,
      truncated,
      sessions,
    };
  }

  async getSession(input: GetSessionInput, token?: string): Promise<SessionDetails> {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    const sessionId = assertSafeSessionId(input.sessionId);
    const branch = this.branchForSession(sessionId);

    const openPr = await this.findSessionPullRequest(owner, repo, branch, 'open', token);
    if (openPr) {
      const pr = await this.github.getPullRequest(owner, repo, openPr.number, token);
      const filesRes = await this.github.listPullRequestFiles(owner, repo, pr.number, 1, 100, token);
      return {
        ...this.prToSessionSummary(sessionId, owner, repo, pr),
        description: pr.body,
        files: filesRes.items,
        filesTruncated: filesRes.hasNextPage,
      };
    }

    const [branchRef, closedPr] = await Promise.all([
      this.github.getBranchRef(owner, repo, branch, token),
      this.findSessionPullRequest(owner, repo, branch, 'closed', token),
    ]);

    if (branchRef && (!closedPr || closedPr.headSha !== branchRef.sha)) {
      return {
        sessionId,
        owner,
        repo,
        branch,
        state: 'pending',
        headSha: branchRef.sha,
        baseBranch: null,
        baseSha: null,
        prNumber: null,
        prUrl: null,
        title: null,
        description: null,
        draft: true,
        mergeable: null,
        mergeableState: null,
        changedFiles: 0,
        files: [],
        filesTruncated: false,
      };
    }

    if (closedPr) {
      const pr = await this.github.getPullRequest(owner, repo, closedPr.number, token);
      const filesRes = await this.github.listPullRequestFiles(owner, repo, pr.number, 1, 100, token);
      return {
        ...this.prToSessionSummary(sessionId, owner, repo, pr),
        description: pr.body,
        files: filesRes.items,
        filesTruncated: filesRes.hasNextPage,
      };
    }

    throw new NotFoundProxyError(`Session "${sessionId}" not found`, { sessionId, branch });
  }

  async commitSession(input: CommitSessionInput, token: string) {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    const sessionId = assertSafeSessionId(input.sessionId);
    const branch = this.branchForSession(sessionId);

    const prCandidate = await this.findSessionPullRequest(owner, repo, branch, 'open', token);
    if (!prCandidate) {
      const branchRef = await this.github.getBranchRef(owner, repo, branch, token);
      if (branchRef) {
        throw new UnprocessableProxyError(
          `Session "${sessionId}" has no committed changes (empty pending session cannot be committed)`,
          { sessionId, branch },
        );
      }
      throw new NotFoundProxyError(`Open session "${sessionId}" not found`, { sessionId, branch });
    }

    let pr = await this.github.getPullRequest(owner, repo, prCandidate.number, token);
    const verifiedHeadSha = pr.headSha;

    if (input.expectedHeadSha && input.expectedHeadSha !== verifiedHeadSha) {
      throw new ConflictProxyError(
        `Optimistic concurrency failure: expected head SHA ${input.expectedHeadSha}, got ${verifiedHeadSha}`,
        { expectedHeadSha: input.expectedHeadSha, actualHeadSha: verifiedHeadSha, sessionId },
      );
    }

    const prFiles = await this.github.listPullRequestFiles(owner, repo, pr.number, 1, 100, token);
    if (pr.changedFiles === 0 || verifiedHeadSha === pr.baseSha || prFiles.items.length === 0) {
      throw new UnprocessableProxyError(
        `Session "${sessionId}" PR #${pr.number} has 0 changed files and cannot be merged`,
        { sessionId, prNumber: pr.number },
      );
    }

    const requireChecks = input.requireChecks ?? this.config.sessions.requireChecksDefault;
    let checkSummary: Array<{ name: string; status: string; conclusion: string | null }> | undefined;

    if (requireChecks) {
      const requiredNames =
        input.requiredCheckNames && input.requiredCheckNames.length > 0
          ? input.requiredCheckNames
          : this.config.sessions.requiredCheckNames;
      checkSummary = await this.verifyCommitChecks(
        owner,
        repo,
        verifiedHeadSha,
        requiredNames,
        token,
      );
    }

    if (pr.draft) {
      await this.github.markPullRequestReadyForReview(pr.nodeId, token);
      pr = await this.github.getPullRequest(owner, repo, pr.number, token);
      if (pr.headSha !== verifiedHeadSha) {
        throw new ConflictProxyError(
          `Session "${sessionId}" advanced from ${verifiedHeadSha} to ${pr.headSha} while readying draft pull request; retry commit_session with latest head SHA`,
          { expectedHeadSha: verifiedHeadSha, actualHeadSha: pr.headSha, sessionId },
        );
      }
    }

    const mergeMethod = input.mergeMethod ?? 'squash';
    const mergeResult = await this.mergeWithTransientRetry(
      owner,
      repo,
      pr,
      {
        mergeMethod,
        commitTitle: input.commitTitle,
        commitMessage: input.commitMessage,
        sha: verifiedHeadSha,
      },
      token,
    );

    const deleteBranch = input.deleteBranch ?? true;
    let branchDeleted = false;
    if (deleteBranch) {
      branchDeleted = await this.github.deleteBranchRef(owner, repo, branch, token);
    }

    return {
      sessionId,
      owner,
      repo,
      branch,
      prNumber: pr.number,
      prUrl: pr.htmlUrl,
      merged: mergeResult.merged,
      mergeSha: mergeResult.sha,
      mergeMethod,
      message: mergeResult.message,
      headSha: verifiedHeadSha,
      branchDeleted,
      checksVerified: requireChecks,
      ...(checkSummary ? { checks: checkSummary } : {}),
    };
  }

  async closeSession(input: CloseSessionInput, token: string) {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    const sessionId = assertSafeSessionId(input.sessionId);
    const branch = this.branchForSession(sessionId);

    const openPr = await this.findSessionPullRequest(owner, repo, branch, 'open', token);
    const branchRef = await this.github.getBranchRef(owner, repo, branch, token);

    if (!openPr && !branchRef) {
      throw new NotFoundProxyError(`Session "${sessionId}" not found`, { sessionId, branch });
    }

    const deleteBranch = input.deleteBranch ?? true;
    if (!openPr && !deleteBranch) {
      throw new BadRequestProxyError(
        `Cannot close pending session "${sessionId}" without a pull request when deleteBranch=false`,
        { sessionId, branch },
      );
    }

    let commentPosted = false;
    let closedPr: GitHubPullRequest | null = null;

    if (openPr) {
      if (input.reason?.trim()) {
        await this.github.createIssueComment(
          owner,
          repo,
          openPr.number,
          input.reason.trim(),
          token,
        );
        commentPosted = true;
      }
      closedPr = await this.github.updatePullRequest(
        owner,
        repo,
        openPr.number,
        { state: 'closed' },
        token,
      );
    }

    const branchDeleted = deleteBranch
      ? await this.github.deleteBranchRef(owner, repo, branch, token)
      : false;

    return {
      sessionId,
      owner,
      repo,
      branch,
      state: 'closed' as const,
      prNumber: closedPr?.number ?? null,
      prUrl: closedPr?.htmlUrl ?? null,
      commentPosted,
      branchDeleted,
    };
  }

  private async commitFilesToBranch(
    owner: string,
    repo: string,
    branch: string,
    parentCommitSha: string,
    baseTreeSha: string,
    files: FileWriteOperationInput[],
    commitMessage: string,
    token: string,
  ): Promise<{ commitSha: string; treeSha: string }> {
    const treeEntries = await runWithConcurrency<FileWriteOperationInput, GitHubTreeInputEntry>(
      files,
      6,
      async (op) => {
        const safePath = assertSafeRepoPath(op.path);
        if (op.delete) {
          return {
            path: safePath,
            mode: '100644',
            type: 'blob',
            sha: null,
          };
        }
        const blob = await this.github.createBlob(
          owner,
          repo,
          op.content ?? '',
          op.encoding ?? 'utf-8',
          token,
        );
        return {
          path: safePath,
          mode: '100644',
          type: 'blob',
          sha: blob.sha,
        };
      },
    );

    const newTree = await this.github.createTree(owner, repo, baseTreeSha, treeEntries, token);
    const newCommit = await this.github.createCommit(
      owner,
      repo,
      commitMessage,
      newTree.sha,
      [parentCommitSha],
      token,
    );

    try {
      await this.github.updateBranchRef(owner, repo, branch, newCommit.sha, false, token);
    } catch (error) {
      if (isNonFastForwardError(error)) {
        throw new ConflictProxyError(
          `Branch "${branch}" advanced concurrently; retry with the latest head SHA`,
          { branch, parentCommitSha },
        );
      }
      throw error;
    }

    return {
      commitSha: newCommit.sha,
      treeSha: newCommit.treeSha,
    };
  }

  private async openPullRequestWithDraftFallback(
    owner: string,
    repo: string,
    input: { title: string; head: string; base: string; body?: string; draft: boolean },
    token: string,
  ): Promise<GitHubPullRequest> {
    try {
      return await this.github.createPullRequest(owner, repo, input, token);
    } catch (error) {
      if (input.draft && isDraftUnsupportedError(error)) {
        return this.github.createPullRequest(
          owner,
          repo,
          { ...input, draft: false },
          token,
        );
      }
      throw error;
    }
  }

  private async rollbackOrphanBranch(
    owner: string,
    repo: string,
    branch: string,
    token: string,
  ): Promise<void> {
    try {
      await this.github.deleteBranchRef(owner, repo, branch, token);
    } catch {
      // Best-effort cleanup so original error surfaces intact
    }
  }

  private async findSessionPullRequest(
    owner: string,
    repo: string,
    branch: string,
    state: 'open' | 'closed' | 'all',
    token?: string,
  ): Promise<GitHubPullRequest | null> {
    const res = await this.github.listPullRequests(
      owner,
      repo,
      { state, head: `${owner}:${branch}`, perPage: 10, page: 1 },
      token,
    );
    return res.items[0] ?? null;
  }

  private async verifyCommitChecks(
    owner: string,
    repo: string,
    headSha: string,
    requiredNames: string[],
    token: string,
  ): Promise<Array<{ name: string; status: string; conclusion: string | null }>> {
    const { checkRuns } = await this.github.listCheckRunsForRef(owner, repo, headSha, token);

    const latestByName = new Map<string, GitHubCheckRun>();
    for (const run of checkRuns) {
      const existing = latestByName.get(run.name);
      if (!existing || run.id > existing.id) {
        latestByName.set(run.name, run);
      }
    }

    if (requiredNames.length > 0) {
      const missing: string[] = [];
      const failing: string[] = [];

      for (const name of requiredNames) {
        const run = latestByName.get(name);
        if (!run) {
          missing.push(name);
          continue;
        }
        if (run.status !== 'completed' || !PASSING_CHECK_CONCLUSIONS.has(run.conclusion ?? '')) {
          failing.push(`${name}(${run.status}/${run.conclusion ?? 'none'})`);
        }
      }

      if (missing.length > 0 || failing.length > 0) {
        throw new ConflictProxyError(
          `Required check runs are not passing on ${headSha}`,
          { headSha, missing, failing },
        );
      }

      return requiredNames.map((name) => {
        const run = latestByName.get(name)!;
        return { name: run.name, status: run.status, conclusion: run.conclusion };
      });
    }

    const latestRuns = [...latestByName.values()];
    if (latestRuns.length === 0) {
      throw new ConflictProxyError(
        `requireChecks=true but no check runs were found for commit ${headSha}`,
        { headSha },
      );
    }

    const failing = latestRuns.filter(
      (run) => run.status !== 'completed' || !PASSING_CHECK_CONCLUSIONS.has(run.conclusion ?? ''),
    );
    if (failing.length > 0) {
      throw new ConflictProxyError(
        `Check runs have not passed on ${headSha}: ${failing.map((r) => `${r.name}(${r.status}/${r.conclusion ?? 'none'})`).join(', ')}`,
        {
          headSha,
          failing: failing.map((r) => ({
            name: r.name,
            status: r.status,
            conclusion: r.conclusion,
          })),
        },
      );
    }

    return latestRuns.map((run) => ({
      name: run.name,
      status: run.status,
      conclusion: run.conclusion,
    }));
  }

  private async mergeWithTransientRetry(
    owner: string,
    repo: string,
    pr: GitHubPullRequest,
    input: {
      mergeMethod: 'squash' | 'merge' | 'rebase';
      commitTitle?: string;
      commitMessage?: string;
      sha: string;
    },
    token: string,
  ): Promise<{ merged: boolean; sha: string; message: string }> {
    const maxAttempts = this.config.sessions.mergeRetryMaxAttempts;
    let delayMs = this.config.sessions.mergeRetryInitialDelayMs;
    const maxDelayMs = this.config.sessions.mergeRetryMaxDelayMs;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await this.github.mergePullRequest(owner, repo, pr.number, input, token);
      } catch (error) {
        if (!isTransientMerge405(error) || attempt === maxAttempts) {
          if (error instanceof UpstreamGitHubError && error.githubStatus === 405) {
            throw new ConflictProxyError(
              `Pull request #${pr.number} is not mergeable: ${error.message}`,
              { prNumber: pr.number },
            );
          }
          throw error;
        }

        const latest = await this.github.getPullRequest(owner, repo, pr.number, token);
        if (latest.mergeable === false) {
          throw new ConflictProxyError(
            `Pull request #${pr.number} has merge conflicts (mergeableState=${latest.mergeableState ?? 'dirty'})`,
            { prNumber: pr.number, mergeableState: latest.mergeableState },
          );
        }

        await sleep(delayMs);
        delayMs = Math.min(delayMs * 2, maxDelayMs);
      }
    }

    throw new ConflictProxyError(`Pull request #${pr.number} could not be merged`);
  }

  private prToSessionSummary(
    sessionId: string,
    owner: string,
    repo: string,
    pr: GitHubPullRequest,
  ): SessionSummary {
    const state: SessionSummary['state'] = pr.merged
      ? 'merged'
      : pr.state === 'closed'
        ? 'closed'
        : 'open';

    return {
      sessionId,
      owner,
      repo,
      branch: pr.headRef,
      state,
      headSha: pr.headSha,
      baseBranch: pr.baseRef,
      baseSha: pr.baseSha,
      prNumber: pr.number,
      prUrl: pr.htmlUrl,
      title: pr.title,
      draft: pr.draft,
      mergeable: pr.mergeable,
      mergeableState: pr.mergeableState,
      changedFiles: pr.changedFiles,
      createdAt: pr.createdAt,
      updatedAt: pr.updatedAt,
      mergedAt: pr.mergedAt,
    };
  }

  private defaultPrTitle(sessionId: string): string {
    return `Wayfinder session: ${sessionId}`;
  }

  private defaultPrBody(sessionId: string): string {
    return `Automated PR-backed Wayfinder write session \`${sessionId}\`.`;
  }
}
