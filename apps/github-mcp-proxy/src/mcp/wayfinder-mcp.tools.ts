import type { McpExecutionContext } from '@nest-mcp/common';
import { Tool } from '@nest-mcp/server';
import { Inject, Injectable, UseFilters } from '@nestjs/common';
import { ProxyMcpExceptionFilter } from '../common/errors';
import { requireGithubToken, resolveGithubToken } from '../common/token-extractor';
import { PROXY_CONFIG, type ProxyConfig } from '../config/proxy-config';
import { RepositoryService } from '../repository/repository.service';
import {
  CloseSessionSchema,
  CommitSessionSchema,
  GetSessionSchema,
  ListSessionsSchema,
  PullBundleSchema,
  PullFileSchema,
  PullTreeSchema,
  RepoInfoSchema,
  SearchRepositorySchema,
  SessionWriteSchema,
  StartSessionSchema,
  type CloseSessionInput,
  type CommitSessionInput,
  type GetSessionInput,
  type ListSessionsInput,
  type PullBundleInput,
  type PullFileInput,
  type PullTreeInput,
  type RepoInfoInput,
  type SearchRepositoryInput,
  type SessionWriteInput,
  type StartSessionInput,
} from '../schemas/proxy.schemas';
import { SessionService } from '../sessions/session.service';

@Injectable()
@UseFilters(ProxyMcpExceptionFilter)
export class WayfinderMcpTools {
  constructor(
    @Inject(PROXY_CONFIG) private readonly config: ProxyConfig,
    private readonly repositoryService: RepositoryService,
    private readonly sessionService: SessionService,
  ) {}

  @Tool({
    name: 'repo_info',
    description: 'Inspect GitHub repository metadata, default branch, and caller permissions',
    parameters: RepoInfoSchema,
    annotations: { readOnlyHint: true, openWorldHint: true },
  })
  async repoInfo(args: RepoInfoInput, ctx: McpExecutionContext) {
    const token = resolveGithubToken(ctx.request, this.config);
    return this.repositoryService.getRepoInfo(args, token);
  }

  @Tool({
    name: 'pull_tree',
    description:
      'List repository or session branch tree entries with Wayfinder OKF file classification',
    parameters: PullTreeSchema,
    annotations: { readOnlyHint: true, openWorldHint: true },
  })
  async pullTree(args: PullTreeInput, ctx: McpExecutionContext) {
    const token = resolveGithubToken(ctx.request, this.config);
    return this.repositoryService.pullTree(args, token);
  }

  @Tool({
    name: 'pull_file',
    description:
      'Read a single repository or session file (with Git Blobs API fallback for >1 MB files) and YAML frontmatter extraction',
    parameters: PullFileSchema,
    annotations: { readOnlyHint: true, openWorldHint: true },
  })
  async pullFile(args: PullFileInput, ctx: McpExecutionContext) {
    const token = resolveGithubToken(ctx.request, this.config);
    return this.repositoryService.pullFile(args, token);
  }

  @Tool({
    name: 'pull_bundle',
    description:
      'Pull wayfinder.json, wayfinder.lock, and Markdown bundle documents in a single tarball fetch (omitting binary attachments)',
    parameters: PullBundleSchema,
    annotations: { readOnlyHint: true, openWorldHint: true },
  })
  async pullBundle(args: PullBundleInput, ctx: McpExecutionContext) {
    const token = resolveGithubToken(ctx.request, this.config);
    return this.repositoryService.pullBundle(args, token);
  }

  @Tool({
    name: 'search_repository',
    description:
      'Search Markdown documents and OKF frontmatter across a repository ref or uncommitted write session',
    parameters: SearchRepositorySchema,
    annotations: { readOnlyHint: true, openWorldHint: true },
  })
  async searchRepository(args: SearchRepositoryInput, ctx: McpExecutionContext) {
    const token = resolveGithubToken(ctx.request, this.config);
    return this.repositoryService.searchRepository(args, token);
  }

  @Tool({
    name: 'start_session',
    description:
      'Start a PR-backed Wayfinder write session branch (lazily opening the PR on first write unless initial files are supplied)',
    parameters: StartSessionSchema,
    annotations: { destructiveHint: false, openWorldHint: true },
  })
  async startSession(args: StartSessionInput, ctx: McpExecutionContext) {
    const token = requireGithubToken(ctx.request, this.config);
    return this.sessionService.startSession(args, token);
  }

  @Tool({
    name: 'session_write',
    description:
      'Atomically commit 1..N file writes and deletions to a session branch (supports autoStart and optimistic expectedHeadSha)',
    parameters: SessionWriteSchema,
    annotations: { destructiveHint: false, openWorldHint: true },
  })
  async sessionWrite(args: SessionWriteInput, ctx: McpExecutionContext) {
    const token = requireGithubToken(ctx.request, this.config);
    return this.sessionService.sessionWrite(args, token);
  }

  @Tool({
    name: 'list_sessions',
    description: 'List PR-backed and pending Wayfinder write sessions with pagination metadata',
    parameters: ListSessionsSchema,
    annotations: { readOnlyHint: true, openWorldHint: true },
  })
  async listSessions(args: ListSessionsInput, ctx: McpExecutionContext) {
    const token = resolveGithubToken(ctx.request, this.config);
    return this.sessionService.listSessions(args, token);
  }

  @Tool({
    name: 'get_session',
    description: 'Inspect a PR-backed Wayfinder write session, mergeability, and changed files',
    parameters: GetSessionSchema,
    annotations: { readOnlyHint: true, openWorldHint: true },
  })
  async getSession(args: GetSessionInput, ctx: McpExecutionContext) {
    const token = resolveGithubToken(ctx.request, this.config);
    return this.sessionService.getSession(args, token);
  }

  @Tool({
    name: 'commit_session',
    description:
      'Verify optional check runs, mark a draft PR ready for review, merge the session PR, and delete the session branch',
    parameters: CommitSessionSchema,
    annotations: { destructiveHint: false, openWorldHint: true },
  })
  async commitSession(args: CommitSessionInput, ctx: McpExecutionContext) {
    const token = requireGithubToken(ctx.request, this.config);
    return this.sessionService.commitSession(args, token);
  }

  @Tool({
    name: 'close_session',
    description:
      'Optionally post a closing comment, close the session PR without merging, and delete the session branch',
    parameters: CloseSessionSchema,
    annotations: { destructiveHint: true, openWorldHint: true },
  })
  async closeSession(args: CloseSessionInput, ctx: McpExecutionContext) {
    const token = requireGithubToken(ctx.request, this.config);
    return this.sessionService.closeSession(args, token);
  }
}
