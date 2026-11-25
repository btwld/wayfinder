export const GITHUB_API_CLIENT = Symbol('GITHUB_API_CLIENT');

export interface GitHubRepoInfo {
  id: number;
  name: string;
  fullName: string;
  owner: string;
  description: string | null;
  private: boolean;
  defaultBranch: string;
  htmlUrl: string;
  archived: boolean;
  pushedAt: string | null;
  updatedAt: string | null;
  permissions?: Record<string, boolean>;
}

export interface GitHubCommitRef {
  sha: string;
  treeSha: string;
  message: string;
}

export interface GitHubBranchRef {
  ref: string;
  sha: string;
}

export interface GitHubTreeEntry {
  path: string;
  mode: string;
  type: 'blob' | 'tree' | 'commit';
  sha: string;
  size?: number;
}

export interface GitHubTreeResponse {
  sha: string;
  truncated: boolean;
  tree: GitHubTreeEntry[];
}

export interface GitHubContentFileResult {
  kind: 'file' | 'too_large';
  path: string;
  sha?: string;
  size?: number;
  encoding?: string;
  content?: string;
}

export interface GitHubBlobResult {
  sha: string;
  size: number;
  encoding: 'base64' | 'utf-8';
  content: string;
}

export interface GitHubTreeInputEntry {
  path: string;
  mode: '100644' | '100755' | '040000' | '160000' | '120000';
  type: 'blob' | 'tree' | 'commit';
  sha: string | null;
}

export interface GitHubPullRequest {
  number: number;
  nodeId: string;
  title: string;
  body: string | null;
  state: 'open' | 'closed';
  draft: boolean;
  merged: boolean;
  mergeable: boolean | null;
  mergeableState: string | null;
  changedFiles: number | null;
  htmlUrl: string;
  headRef: string;
  headSha: string;
  headRepoFullName?: string | null;
  headOwner?: string | null;
  baseRef: string;
  baseSha: string;
  createdAt: string;
  updatedAt: string;
  mergedAt: string | null;
}

export interface GitHubPullRequestFile {
  filename: string;
  status: string;
  additions: number;
  deletions: number;
  changes: number;
  sha: string | null;
}

export interface GitHubCheckRun {
  id: number;
  name: string;
  status: string;
  conclusion: string | null;
  htmlUrl: string | null;
}

export interface CreatePullRequestInput {
  title: string;
  head: string;
  base: string;
  body?: string;
  draft?: boolean;
}

export interface ListPullRequestsQuery {
  state?: 'open' | 'closed' | 'all';
  head?: string;
  perPage?: number;
  page?: number;
}

export interface MergePullRequestInput {
  mergeMethod: 'squash' | 'merge' | 'rebase';
  commitTitle?: string;
  commitMessage?: string;
  sha?: string;
}

export interface IGitHubApiClient {
  getRepo(owner: string, repo: string, token?: string): Promise<GitHubRepoInfo>;
  resolveCommit(owner: string, repo: string, ref: string, token?: string): Promise<GitHubCommitRef>;
  getBranchRef(owner: string, repo: string, branch: string, token?: string): Promise<GitHubBranchRef | null>;
  listMatchingBranchRefs(owner: string, repo: string, prefix: string, token?: string): Promise<GitHubBranchRef[]>;
  createBranchRef(owner: string, repo: string, branch: string, sha: string, token: string): Promise<GitHubBranchRef>;
  updateBranchRef(owner: string, repo: string, branch: string, sha: string, force: boolean, token: string): Promise<GitHubBranchRef>;
  deleteBranchRef(owner: string, repo: string, branch: string, token: string): Promise<boolean>;

  getTree(owner: string, repo: string, treeShaOrRef: string, recursive: boolean, token?: string): Promise<GitHubTreeResponse>;
  getContent(owner: string, repo: string, path: string, ref: string, token?: string): Promise<GitHubContentFileResult>;
  getBlob(owner: string, repo: string, blobSha: string, token?: string): Promise<GitHubBlobResult>;
  createBlob(owner: string, repo: string, content: string, encoding: 'utf-8' | 'base64', token: string): Promise<{ sha: string }>;
  createTree(owner: string, repo: string, baseTreeSha: string, entries: GitHubTreeInputEntry[], token: string): Promise<{ sha: string }>;
  createCommit(owner: string, repo: string, message: string, treeSha: string, parents: string[], token: string): Promise<{ sha: string; treeSha: string }>;
  downloadTarball(owner: string, repo: string, ref: string, token?: string): Promise<Buffer>;

  createPullRequest(owner: string, repo: string, input: CreatePullRequestInput, token: string): Promise<GitHubPullRequest>;
  listPullRequests(owner: string, repo: string, query: ListPullRequestsQuery, token?: string): Promise<{ items: GitHubPullRequest[]; hasNextPage: boolean }>;
  getPullRequest(owner: string, repo: string, prNumber: number, token?: string): Promise<GitHubPullRequest>;
  listPullRequestFiles(owner: string, repo: string, prNumber: number, page: number, perPage: number, token?: string): Promise<{ items: GitHubPullRequestFile[]; hasNextPage: boolean }>;
  createIssueComment(owner: string, repo: string, issueNumber: number, body: string, token: string): Promise<{ id: number; htmlUrl: string }>;
  updatePullRequest(owner: string, repo: string, prNumber: number, patch: { state?: 'open' | 'closed'; title?: string; body?: string }, token: string): Promise<GitHubPullRequest>;
  markPullRequestReadyForReview(pullRequestNodeId: string, token: string): Promise<{ id: string; isDraft: boolean }>;
  mergePullRequest(owner: string, repo: string, prNumber: number, input: MergePullRequestInput, token: string): Promise<{ merged: boolean; sha: string; message: string }>;
  listCheckRunsForRef(owner: string, repo: string, ref: string, token?: string): Promise<{ totalCount: number; checkRuns: GitHubCheckRun[] }>;
}
