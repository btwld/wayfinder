import { createHash } from 'node:crypto';
import * as zlib from 'node:zlib';
import { UpstreamGitHubError } from '../../src/common/errors';
import { encodeGitRefPath } from '../../src/common/path-safety';
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
} from '../../src/github/github-api.interface';

interface FakeCommit {
  sha: string;
  treeSha: string;
  message: string;
  parents: string[];
}

interface FakeRepo {
  info: GitHubRepoInfo;
  branches: Map<string, string>;
  commits: Map<string, FakeCommit>;
  trees: Map<string, Map<string, string>>;
  blobs: Map<string, Buffer>;
  pullRequests: Map<number, GitHubPullRequest>;
  prComments: Map<number, Array<{ id: number; body: string }>>;
  checkRuns: Map<string, GitHubCheckRun[]>;
  nextPrNumber: number;
  nextCommentId: number;
}

export interface RecordedCall {
  method: string;
  repoKey: string;
  token?: string;
  detail?: Record<string, unknown>;
}

function sha1Hex(input: string | Buffer): string {
  return createHash('sha1').update(input).digest('hex');
}

function writeOctal(buf: Buffer, offset: number, length: number, value: number): void {
  const oct = value.toString(8).padStart(length - 1, '0');
  buf.write(oct, offset, length - 1, 'ascii');
  buf[offset + length - 1] = 0;
}

function buildTarHeader(
  name: string,
  size: number,
  typeFlag: string,
  prefix = '',
): Buffer {
  const header = Buffer.alloc(512, 0);
  header.write(name.slice(0, 100), 0, 100, 'utf8');
  writeOctal(header, 100, 8, typeFlag === '5' ? 0o755 : 0o644);
  writeOctal(header, 108, 8, 0);
  writeOctal(header, 116, 8, 0);
  writeOctal(header, 124, 12, size);
  writeOctal(header, 136, 12, Math.floor(Date.now() / 1000));
  header.fill(0x20, 148, 156);
  header.write(typeFlag, 156, 1, 'ascii');
  header.write('ustar', 257, 5, 'ascii');
  header[262] = 0;
  header.write('00', 263, 2, 'ascii');
  if (prefix) {
    header.write(prefix.slice(0, 155), 345, 155, 'utf8');
  }

  let checksum = 0;
  for (let i = 0; i < 512; i++) {
    checksum += header[i];
  }
  const chkStr = checksum.toString(8).padStart(6, '0');
  header.write(chkStr, 148, 6, 'ascii');
  header[154] = 0;
  header[155] = 0x20;
  return header;
}

function buildPaxRecord(key: string, value: string): Buffer {
  const body = `${key}=${value}\n`;
  let len = Buffer.byteLength(body, 'utf8') + 2;
  while (true) {
    const candidate = `${len} ${body}`;
    const byteLen = Buffer.byteLength(candidate, 'utf8');
    if (byteLen === len) {
      return Buffer.from(candidate, 'utf8');
    }
    len = byteLen;
  }
}

export function createTestGzipTarball(
  rootFolder: string,
  files: Array<{ path: string; content: Buffer; forcePax?: boolean }>,
): Buffer {
  const chunks: Buffer[] = [];

  for (const file of files) {
    const fullPath = `${rootFolder}/${file.path}`;
    const nameBytes = Buffer.byteLength(fullPath, 'utf8');
    const hasNonAscii = /[^\x00-\x7f]/.test(fullPath);
    if (file.forcePax || nameBytes > 100 || hasNonAscii) {
      const paxData = Buffer.concat([
        buildPaxRecord('path', fullPath),
        buildPaxRecord('mtime', '1700000000.123'),
      ]);
      const paxHeader = buildTarHeader(`PaxHeaders/${file.path}`.slice(0, 99), paxData.length, 'x');
      chunks.push(paxHeader, paxData);
      const paxPad = (512 - (paxData.length % 512)) % 512;
      if (paxPad > 0) chunks.push(Buffer.alloc(paxPad, 0));
    }

    const header = buildTarHeader(fullPath.slice(0, 100), file.content.length, '0');
    chunks.push(header);
    if (file.content.length > 0) {
      chunks.push(file.content);
      const pad = (512 - (file.content.length % 512)) % 512;
      if (pad > 0) chunks.push(Buffer.alloc(pad, 0));
    }
  }

  chunks.push(Buffer.alloc(1024, 0));
  return zlib.gzipSync(Buffer.concat(chunks));
}

export class FakeGitHubApi implements IGitHubApiClient {
  private readonly repos = new Map<string, FakeRepo>();
  public readonly calls: RecordedCall[] = [];

  public failCreatePrWithDraftUnsupportedOnce = false;
  public failCreatePrWithError: UpstreamGitHubError | null = null;
  public transientMerge405Count = 0;
  public forceMergeableFalse = false;
  public forceTooLargePaths = new Set<string>();
  public forceTooLargeNoShaPaths = new Set<string>();
  public autoDeleteBranchOnMerge = false;
  public downloadTarballCount = 0;
  public onBeforeMarkReady?: (pullRequestNodeId: string) => Promise<void> | void;

  seedRepository(
    owner: string,
    repo: string,
    initialFiles: Record<string, string | Buffer>,
    options?: {
      defaultBranch?: string;
      private?: boolean;
      permissions?: Record<string, boolean>;
    },
  ): { defaultBranch: string; headSha: string } {
    const defaultBranch = options?.defaultBranch ?? 'main';
    const blobs = new Map<string, Buffer>();
    const treeMap = new Map<string, string>();

    for (const [filePath, raw] of Object.entries(initialFiles)) {
      const buf = Buffer.isBuffer(raw) ? raw : Buffer.from(raw, 'utf8');
      const blobSha = sha1Hex(Buffer.concat([Buffer.from('blob:'), buf]));
      blobs.set(blobSha, buf);
      treeMap.set(filePath, blobSha);
    }

    const treeSha = sha1Hex(JSON.stringify([...treeMap.entries()].sort()));
    const commitSha = sha1Hex(`commit:init:${treeSha}`);

    const trees = new Map<string, Map<string, string>>();
    trees.set(treeSha, treeMap);

    const commits = new Map<string, FakeCommit>();
    commits.set(commitSha, {
      sha: commitSha,
      treeSha,
      message: 'Initial commit',
      parents: [],
    });

    const branches = new Map<string, string>();
    branches.set(defaultBranch, commitSha);

    const key = `${owner}/${repo}`.toLowerCase();
    this.repos.set(key, {
      info: {
        id: 1001,
        name: repo,
        fullName: `${owner}/${repo}`,
        owner,
        description: 'Fake Wayfinder GitHub repository',
        private: options?.private ?? false,
        defaultBranch,
        htmlUrl: `https://github.com/${owner}/${repo}`,
        archived: false,
        pushedAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        permissions: options?.permissions ?? { admin: true, push: true, pull: true },
      },
      branches,
      commits,
      trees,
      blobs,
      pullRequests: new Map(),
      prComments: new Map(),
      checkRuns: new Map(),
      nextPrNumber: 1,
      nextCommentId: 1,
    });

    return { defaultBranch, headSha: commitSha };
  }

  seedForkPullRequest(
    owner: string,
    repo: string,
    forkOwner: string,
    headRef: string,
    title = 'External fork PR',
  ): GitHubPullRequest {
    const fakeRepo = this.requireRepo(owner, repo);
    const num = fakeRepo.nextPrNumber++;
    const baseSha = fakeRepo.branches.get(fakeRepo.info.defaultBranch)!;
    const now = new Date().toISOString();
    const pr: GitHubPullRequest = {
      number: num,
      nodeId: `PR_fork_${num}`,
      title,
      body: null,
      state: 'open',
      draft: false,
      merged: false,
      mergeable: true,
      mergeableState: 'clean',
      changedFiles: 1,
      htmlUrl: `https://github.com/${owner}/${repo}/pull/${num}`,
      headRef,
      headSha: sha1Hex(`fork:${forkOwner}:${headRef}`),
      headRepoFullName: `${forkOwner}/${repo}`,
      headOwner: forkOwner,
      baseRef: fakeRepo.info.defaultBranch,
      baseSha,
      createdAt: now,
      updatedAt: now,
      mergedAt: null,
    };
    fakeRepo.pullRequests.set(num, pr);
    return { ...pr };
  }

  setCheckRuns(owner: string, repo: string, commitSha: string, runs: GitHubCheckRun[]): void {
    const fakeRepo = this.requireRepo(owner, repo);
    fakeRepo.checkRuns.set(commitSha, runs);
  }

  getPrComments(owner: string, repo: string, prNumber: number): Array<{ id: number; body: string }> {
    const fakeRepo = this.requireRepo(owner, repo);
    return fakeRepo.prComments.get(prNumber) ?? [];
  }

  getBranchSha(owner: string, repo: string, branch: string): string | undefined {
    const fakeRepo = this.requireRepo(owner, repo);
    return fakeRepo.branches.get(branch);
  }

  async getRepo(owner: string, repo: string, token?: string): Promise<GitHubRepoInfo> {
    this.record('getRepo', owner, repo, token);
    return { ...this.requireRepo(owner, repo).info };
  }

  async resolveCommit(
    owner: string,
    repo: string,
    ref: string,
    token?: string,
  ): Promise<GitHubCommitRef> {
    this.record('resolveCommit', owner, repo, token, { ref });
    const fakeRepo = this.requireRepo(owner, repo);
    const sha = fakeRepo.branches.get(ref) ?? ref;
    const commit = fakeRepo.commits.get(sha);
    if (!commit) {
      throw new UpstreamGitHubError(404, `No commit found for ref: ${ref}`);
    }
    return { sha: commit.sha, treeSha: commit.treeSha, message: commit.message };
  }

  async getBranchRef(
    owner: string,
    repo: string,
    branch: string,
    token?: string,
  ): Promise<GitHubBranchRef | null> {
    this.record('getBranchRef', owner, repo, token, { branch });
    const fakeRepo = this.requireRepo(owner, repo);
    const sha = fakeRepo.branches.get(branch);
    return sha ? { ref: branch, sha } : null;
  }

  async listMatchingBranchRefs(
    owner: string,
    repo: string,
    prefix: string,
    token?: string,
  ): Promise<GitHubBranchRef[]> {
    this.record('listMatchingBranchRefs', owner, repo, token, { prefix });
    const normalized = prefix.replace(/\/+$/, '');
    encodeGitRefPath(normalized);
    const fakeRepo = this.requireRepo(owner, repo);
    const matches: GitHubBranchRef[] = [];
    for (const [ref, sha] of fakeRepo.branches.entries()) {
      if (ref.startsWith(prefix)) {
        matches.push({ ref, sha });
      }
    }
    return matches;
  }

  async createBranchRef(
    owner: string,
    repo: string,
    branch: string,
    sha: string,
    token: string,
  ): Promise<GitHubBranchRef> {
    this.record('createBranchRef', owner, repo, token, { branch, sha });
    const fakeRepo = this.requireRepo(owner, repo);
    if (fakeRepo.branches.has(branch)) {
      throw new UpstreamGitHubError(422, 'Reference already exists');
    }
    if (!fakeRepo.commits.has(sha)) {
      throw new UpstreamGitHubError(422, 'Object does not exist');
    }
    fakeRepo.branches.set(branch, sha);
    return { ref: branch, sha };
  }

  async updateBranchRef(
    owner: string,
    repo: string,
    branch: string,
    sha: string,
    force: boolean,
    token: string,
  ): Promise<GitHubBranchRef> {
    this.record('updateBranchRef', owner, repo, token, { branch, sha, force });
    const fakeRepo = this.requireRepo(owner, repo);
    const current = fakeRepo.branches.get(branch);
    if (!current) {
      throw new UpstreamGitHubError(404, 'Reference does not exist');
    }
    const targetCommit = fakeRepo.commits.get(sha);
    if (!targetCommit) {
      throw new UpstreamGitHubError(422, 'Target commit does not exist');
    }
    if (!force && !this.isAncestor(fakeRepo, current, sha)) {
      throw new UpstreamGitHubError(422, 'Update is not a fast forward');
    }
    fakeRepo.branches.set(branch, sha);
    return { ref: branch, sha };
  }

  async deleteBranchRef(
    owner: string,
    repo: string,
    branch: string,
    token: string,
  ): Promise<boolean> {
    this.record('deleteBranchRef', owner, repo, token, { branch });
    const fakeRepo = this.requireRepo(owner, repo);
    return fakeRepo.branches.delete(branch);
  }

  async getTree(
    owner: string,
    repo: string,
    treeShaOrRef: string,
    recursive: boolean,
    token?: string,
  ): Promise<GitHubTreeResponse> {
    this.record('getTree', owner, repo, token, { treeShaOrRef, recursive });
    const fakeRepo = this.requireRepo(owner, repo);
    let treeSha = treeShaOrRef;
    if (!fakeRepo.trees.has(treeSha)) {
      const resolvedSha = fakeRepo.branches.get(treeShaOrRef) ?? treeShaOrRef;
      const commit = fakeRepo.commits.get(resolvedSha);
      if (!commit) {
        throw new UpstreamGitHubError(404, `Tree ${treeShaOrRef} not found`);
      }
      treeSha = commit.treeSha;
    }

    const treeMap = fakeRepo.trees.get(treeSha)!;
    const entries: GitHubTreeEntry[] = [];
    for (const [filePath, blobSha] of [...treeMap.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
      if (!recursive && filePath.includes('/')) continue;
      const blob = fakeRepo.blobs.get(blobSha);
      entries.push({
        path: filePath,
        mode: '100644',
        type: 'blob',
        sha: blobSha,
        size: blob?.length ?? 0,
      });
    }

    return { sha: treeSha, truncated: false, tree: entries };
  }

  async getContent(
    owner: string,
    repo: string,
    path: string,
    ref: string,
    token?: string,
  ): Promise<GitHubContentFileResult> {
    this.record('getContent', owner, repo, token, { path, ref });
    const fakeRepo = this.requireRepo(owner, repo);
    const commit = await this.resolveCommitInternal(fakeRepo, ref);
    const treeMap = fakeRepo.trees.get(commit.treeSha)!;
    const blobSha = treeMap.get(path);
    if (!blobSha) {
      throw new UpstreamGitHubError(404, `Not Found: ${path}`);
    }
    const buf = fakeRepo.blobs.get(blobSha)!;
    if (this.forceTooLargeNoShaPaths.has(path)) {
      return { kind: 'too_large', path };
    }
    if (this.forceTooLargePaths.has(path) || buf.length > 1024 * 1024) {
      return { kind: 'too_large', path, sha: blobSha, size: buf.length };
    }
    return {
      kind: 'file',
      path,
      sha: blobSha,
      size: buf.length,
      encoding: 'base64',
      content: buf.toString('base64'),
    };
  }

  async getBlob(
    owner: string,
    repo: string,
    blobSha: string,
    token?: string,
  ): Promise<GitHubBlobResult> {
    this.record('getBlob', owner, repo, token, { blobSha });
    const fakeRepo = this.requireRepo(owner, repo);
    const buf = fakeRepo.blobs.get(blobSha);
    if (!buf) {
      throw new UpstreamGitHubError(404, `Blob ${blobSha} not found`);
    }
    return {
      sha: blobSha,
      size: buf.length,
      encoding: 'base64',
      content: buf.toString('base64'),
    };
  }

  async createBlob(
    owner: string,
    repo: string,
    content: string,
    encoding: 'utf-8' | 'base64',
    token: string,
  ): Promise<{ sha: string }> {
    this.record('createBlob', owner, repo, token, { encoding });
    const fakeRepo = this.requireRepo(owner, repo);
    const buf = Buffer.from(content, encoding === 'base64' ? 'base64' : 'utf8');
    const sha = sha1Hex(Buffer.concat([Buffer.from('blob:'), buf]));
    fakeRepo.blobs.set(sha, buf);
    return { sha };
  }

  async createTree(
    owner: string,
    repo: string,
    baseTreeSha: string,
    entries: GitHubTreeInputEntry[],
    token: string,
  ): Promise<{ sha: string }> {
    this.record('createTree', owner, repo, token, { baseTreeSha, count: entries.length });
    const fakeRepo = this.requireRepo(owner, repo);
    const baseTree = fakeRepo.trees.get(baseTreeSha);
    if (!baseTree) {
      throw new UpstreamGitHubError(404, `Base tree ${baseTreeSha} not found`);
    }
    const nextTree = new Map(baseTree);
    for (const entry of entries) {
      if (entry.sha === null) {
        nextTree.delete(entry.path);
      } else {
        nextTree.set(entry.path, entry.sha);
      }
    }
    const sha = sha1Hex(JSON.stringify([...nextTree.entries()].sort()));
    fakeRepo.trees.set(sha, nextTree);
    return { sha };
  }

  async createCommit(
    owner: string,
    repo: string,
    message: string,
    treeSha: string,
    parents: string[],
    token: string,
  ): Promise<{ sha: string; treeSha: string }> {
    this.record('createCommit', owner, repo, token, { message, treeSha, parents });
    const fakeRepo = this.requireRepo(owner, repo);
    const sha = sha1Hex(`commit:${treeSha}:${parents.join(',')}:${message}:${fakeRepo.commits.size}`);
    fakeRepo.commits.set(sha, { sha, treeSha, message, parents });
    this.refreshOpenPrHeadShas(fakeRepo, sha, parents);
    return { sha, treeSha };
  }

  async downloadTarball(
    owner: string,
    repo: string,
    ref: string,
    token?: string,
  ): Promise<Buffer> {
    this.downloadTarballCount++;
    this.record('downloadTarball', owner, repo, token, { ref });
    const fakeRepo = this.requireRepo(owner, repo);
    const commit = await this.resolveCommitInternal(fakeRepo, ref);
    const treeMap = fakeRepo.trees.get(commit.treeSha)!;
    const files: Array<{ path: string; content: Buffer }> = [];
    for (const [filePath, blobSha] of [...treeMap.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
      files.push({
        path: filePath,
        content: fakeRepo.blobs.get(blobSha) ?? Buffer.alloc(0),
      });
    }
    return createTestGzipTarball(`${owner}-${repo}-${commit.sha.slice(0, 7)}`, files);
  }

  async createPullRequest(
    owner: string,
    repo: string,
    input: CreatePullRequestInput,
    token: string,
  ): Promise<GitHubPullRequest> {
    this.record('createPullRequest', owner, repo, token, {
      head: input.head,
      base: input.base,
      draft: input.draft,
    });
    const fakeRepo = this.requireRepo(owner, repo);

    if (this.failCreatePrWithError) {
      const err = this.failCreatePrWithError;
      this.failCreatePrWithError = null;
      throw err;
    }

    if (input.draft && this.failCreatePrWithDraftUnsupportedOnce) {
      this.failCreatePrWithDraftUnsupportedOnce = false;
      throw new UpstreamGitHubError(422, 'Draft pull requests are not supported on this plan');
    }

    const headSha = fakeRepo.branches.get(input.head);
    const baseSha = fakeRepo.branches.get(input.base);
    if (!headSha || !baseSha) {
      throw new UpstreamGitHubError(422, 'Validation Failed: head or base branch does not exist');
    }

    const num = fakeRepo.nextPrNumber++;
    const now = new Date().toISOString();
    const pr: GitHubPullRequest = {
      number: num,
      nodeId: `PR_node_${num}`,
      title: input.title,
      body: input.body ?? null,
      state: 'open',
      draft: Boolean(input.draft),
      merged: false,
      mergeable: true,
      mergeableState: 'clean',
      changedFiles: this.computeChangedFiles(fakeRepo, baseSha, headSha).length,
      htmlUrl: `https://github.com/${owner}/${repo}/pull/${num}`,
      headRef: input.head,
      headSha,
      headRepoFullName: `${owner}/${repo}`,
      headOwner: owner,
      baseRef: input.base,
      baseSha,
      createdAt: now,
      updatedAt: now,
      mergedAt: null,
    };
    fakeRepo.pullRequests.set(num, pr);
    return { ...pr };
  }

  async listPullRequests(
    owner: string,
    repo: string,
    query: ListPullRequestsQuery,
    token?: string,
  ): Promise<{ items: GitHubPullRequest[]; hasNextPage: boolean }> {
    this.record('listPullRequests', owner, repo, token, { ...query });
    const fakeRepo = this.requireRepo(owner, repo);
    const headBranch = query.head?.includes(':') ? query.head.split(':', 2)[1] : query.head;
    const headOwnerFilter = query.head?.includes(':') ? query.head.split(':', 2)[0] : undefined;

    // Mimic GitHub REST PullRequestSimple list shape: omits changed_files & mergeable
    const matching = [...fakeRepo.pullRequests.values()]
      .filter((pr) => {
        if (query.state && query.state !== 'all' && pr.state !== query.state) return false;
        if (headBranch && pr.headRef !== headBranch) return false;
        if (
          headOwnerFilter &&
          pr.headOwner &&
          pr.headOwner.toLowerCase() !== headOwnerFilter.toLowerCase()
        ) {
          return false;
        }
        return true;
      })
      .map((pr) => ({
        ...this.syncPrStats(fakeRepo, pr),
        changedFiles: null,
        mergeable: null,
        mergeableState: null,
      }));

    const perPage = query.perPage ?? 30;
    const page = query.page ?? 1;
    const start = (page - 1) * perPage;
    const items = matching.slice(start, start + perPage);
    return {
      items,
      hasNextPage: start + items.length < matching.length,
    };
  }

  async getPullRequest(
    owner: string,
    repo: string,
    prNumber: number,
    token?: string,
  ): Promise<GitHubPullRequest> {
    this.record('getPullRequest', owner, repo, token, { prNumber });
    const fakeRepo = this.requireRepo(owner, repo);
    const pr = fakeRepo.pullRequests.get(prNumber);
    if (!pr) {
      throw new UpstreamGitHubError(404, `Pull Request #${prNumber} not found`);
    }
    return this.syncPrStats(fakeRepo, pr);
  }

  async listPullRequestFiles(
    owner: string,
    repo: string,
    prNumber: number,
    page: number,
    perPage: number,
    token?: string,
  ): Promise<{ items: GitHubPullRequestFile[]; hasNextPage: boolean }> {
    this.record('listPullRequestFiles', owner, repo, token, { prNumber, page, perPage });
    const fakeRepo = this.requireRepo(owner, repo);
    const pr = fakeRepo.pullRequests.get(prNumber);
    if (!pr) {
      throw new UpstreamGitHubError(404, `Pull Request #${prNumber} not found`);
    }
    const synced = this.syncPrStats(fakeRepo, pr);
    const files = this.computeChangedFiles(fakeRepo, synced.baseSha, synced.headSha);
    const start = (page - 1) * perPage;
    const items = files.slice(start, start + perPage);
    return { items, hasNextPage: start + items.length < files.length };
  }

  async createIssueComment(
    owner: string,
    repo: string,
    issueNumber: number,
    body: string,
    token: string,
  ): Promise<{ id: number; htmlUrl: string }> {
    this.record('createIssueComment', owner, repo, token, { issueNumber, body });
    const fakeRepo = this.requireRepo(owner, repo);
    const id = fakeRepo.nextCommentId++;
    const comments = fakeRepo.prComments.get(issueNumber) ?? [];
    comments.push({ id, body });
    fakeRepo.prComments.set(issueNumber, comments);
    return {
      id,
      htmlUrl: `https://github.com/${owner}/${repo}/pull/${issueNumber}#issuecomment-${id}`,
    };
  }

  async updatePullRequest(
    owner: string,
    repo: string,
    prNumber: number,
    patch: { state?: 'open' | 'closed'; title?: string; body?: string },
    token: string,
  ): Promise<GitHubPullRequest> {
    this.record('updatePullRequest', owner, repo, token, { prNumber, patch });
    const fakeRepo = this.requireRepo(owner, repo);
    const pr = fakeRepo.pullRequests.get(prNumber);
    if (!pr) {
      throw new UpstreamGitHubError(404, `Pull Request #${prNumber} not found`);
    }
    if (patch.state) pr.state = patch.state;
    if (patch.title) pr.title = patch.title;
    if (patch.body !== undefined) pr.body = patch.body;
    pr.updatedAt = new Date().toISOString();
    return this.syncPrStats(fakeRepo, pr);
  }

  async markPullRequestReadyForReview(
    pullRequestNodeId: string,
    token: string,
  ): Promise<{ id: string; isDraft: boolean }> {
    this.record('markPullRequestReadyForReview', '*', '*', token, { pullRequestNodeId });
    if (this.onBeforeMarkReady) {
      await this.onBeforeMarkReady(pullRequestNodeId);
    }
    for (const fakeRepo of this.repos.values()) {
      for (const pr of fakeRepo.pullRequests.values()) {
        if (pr.nodeId === pullRequestNodeId) {
          pr.draft = false;
          pr.updatedAt = new Date().toISOString();
          return { id: pullRequestNodeId, isDraft: false };
        }
      }
    }
    throw new UpstreamGitHubError(404, `PR node ${pullRequestNodeId} not found`);
  }

  async mergePullRequest(
    owner: string,
    repo: string,
    prNumber: number,
    input: MergePullRequestInput,
    token: string,
  ): Promise<{ merged: boolean; sha: string; message: string }> {
    this.record('mergePullRequest', owner, repo, token, { prNumber, ...input });
    const fakeRepo = this.requireRepo(owner, repo);
    const pr = fakeRepo.pullRequests.get(prNumber);
    if (!pr) {
      throw new UpstreamGitHubError(404, `Pull Request #${prNumber} not found`);
    }

    if (this.forceMergeableFalse) {
      pr.mergeable = false;
      pr.mergeableState = 'dirty';
      throw new UpstreamGitHubError(405, 'Pull Request is not mergeable');
    }

    if (this.transientMerge405Count > 0) {
      this.transientMerge405Count--;
      throw new UpstreamGitHubError(405, 'Pull Request is not mergeable');
    }

    const synced = this.syncPrStats(fakeRepo, pr);
    if (synced.draft) {
      throw new UpstreamGitHubError(405, 'Pull Request is still a draft');
    }
    if (input.sha && input.sha !== synced.headSha) {
      throw new UpstreamGitHubError(409, 'Head branch was modified. Review and try the merge again.');
    }

    const headCommit = fakeRepo.commits.get(synced.headSha)!;
    const baseSha = fakeRepo.branches.get(pr.baseRef) ?? pr.baseSha;
    const mergeSha = sha1Hex(`merge:${prNumber}:${synced.headSha}:${baseSha}:${input.mergeMethod}`);
    fakeRepo.commits.set(mergeSha, {
      sha: mergeSha,
      treeSha: headCommit.treeSha,
      message: input.commitTitle ?? `Merge pull request #${prNumber}`,
      parents: [baseSha, synced.headSha],
    });
    fakeRepo.branches.set(pr.baseRef, mergeSha);

    pr.merged = true;
    pr.state = 'closed';
    pr.mergedAt = new Date().toISOString();
    pr.updatedAt = pr.mergedAt;

    if (this.autoDeleteBranchOnMerge) {
      fakeRepo.branches.delete(pr.headRef);
    }

    return {
      merged: true,
      sha: mergeSha,
      message: 'Pull Request successfully merged',
    };
  }

  async listCheckRunsForRef(
    owner: string,
    repo: string,
    ref: string,
    token?: string,
  ): Promise<{ totalCount: number; checkRuns: GitHubCheckRun[] }> {
    this.record('listCheckRunsForRef', owner, repo, token, { ref });
    const fakeRepo = this.requireRepo(owner, repo);
    const commit = await this.resolveCommitInternal(fakeRepo, ref);
    const runs = fakeRepo.checkRuns.get(commit.sha) ?? [];
    return { totalCount: runs.length, checkRuns: [...runs] };
  }

  private syncPrStats(fakeRepo: FakeRepo, pr: GitHubPullRequest): GitHubPullRequest {
    if (pr.state === 'open') {
      const liveHead = fakeRepo.branches.get(pr.headRef) ?? pr.headSha;
      const liveBase = fakeRepo.branches.get(pr.baseRef) ?? pr.baseSha;
      pr.headSha = liveHead;
      pr.baseSha = liveBase;
    }
    pr.changedFiles = this.computeChangedFiles(fakeRepo, pr.baseSha, pr.headSha).length;
    return { ...pr };
  }

  private computeChangedFiles(
    fakeRepo: FakeRepo,
    baseSha: string,
    headSha: string,
  ): GitHubPullRequestFile[] {
    const baseCommit = fakeRepo.commits.get(baseSha);
    const headCommit = fakeRepo.commits.get(headSha);
    if (!baseCommit || !headCommit) return [];
    const baseTree = fakeRepo.trees.get(baseCommit.treeSha) ?? new Map<string, string>();
    const headTree = fakeRepo.trees.get(headCommit.treeSha) ?? new Map<string, string>();

    const allPaths = new Set([...baseTree.keys(), ...headTree.keys()]);
    const changed: GitHubPullRequestFile[] = [];

    for (const filePath of [...allPaths].sort()) {
      const bSha = baseTree.get(filePath);
      const hSha = headTree.get(filePath);
      if (bSha === hSha) continue;
      changed.push({
        filename: filePath,
        status: !bSha ? 'added' : !hSha ? 'removed' : 'modified',
        additions: hSha ? 1 : 0,
        deletions: bSha ? 1 : 0,
        changes: 1,
        sha: hSha ?? null,
      });
    }
    return changed;
  }

  private refreshOpenPrHeadShas(fakeRepo: FakeRepo, newSha: string, parents: string[]): void {
    for (const pr of fakeRepo.pullRequests.values()) {
      if (pr.state === 'open' && parents.includes(pr.headSha)) {
        pr.headSha = newSha;
        pr.updatedAt = new Date().toISOString();
      }
    }
  }

  private isAncestor(fakeRepo: FakeRepo, ancestorSha: string, targetSha: string): boolean {
    const visited = new Set<string>();
    const queue = [targetSha];
    while (queue.length > 0) {
      const current = queue.shift()!;
      if (current === ancestorSha) return true;
      if (visited.has(current)) continue;
      visited.add(current);
      const commit = fakeRepo.commits.get(current);
      if (commit) {
        queue.push(...commit.parents);
      }
    }
    return false;
  }

  private async resolveCommitInternal(fakeRepo: FakeRepo, ref: string): Promise<FakeCommit> {
    const sha = fakeRepo.branches.get(ref) ?? ref;
    const commit = fakeRepo.commits.get(sha);
    if (!commit) {
      throw new UpstreamGitHubError(404, `No commit found for ref: ${ref}`);
    }
    return commit;
  }

  private requireRepo(owner: string, repo: string): FakeRepo {
    const fakeRepo = this.repos.get(`${owner}/${repo}`.toLowerCase());
    if (!fakeRepo) {
      throw new UpstreamGitHubError(404, `Not Found: ${owner}/${repo}`);
    }
    return fakeRepo;
  }

  private record(
    method: string,
    owner: string,
    repo: string,
    token: string | undefined,
    detail?: Record<string, unknown>,
  ): void {
    this.calls.push({
      method,
      repoKey: `${owner}/${repo}`,
      token,
      ...(detail ? { detail } : {}),
    });
  }
}
