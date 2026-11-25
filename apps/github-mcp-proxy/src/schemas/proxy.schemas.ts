import { z } from 'zod';

const ownerField = z
  .string()
  .min(1)
  .optional()
  .describe('GitHub repository owner (defaults to GITHUB_OWNER)');

const repoField = z
  .string()
  .min(1)
  .optional()
  .describe('GitHub repository name (defaults to GITHUB_REPO)');

const refField = z
  .string()
  .min(1)
  .optional()
  .describe('Git branch, tag, or commit SHA (mutually exclusive with sessionId)');

const sessionIdOptionalField = z
  .string()
  .min(1)
  .optional()
  .describe('Write session ID (mutually exclusive with ref)');

const sessionIdRequiredField = z
  .string()
  .min(1)
  .describe('Write session identifier (maps to branch wayfinder/session/<sessionId>)');

export const RepoTargetSchema = z
  .object({
    owner: ownerField,
    repo: repoField,
  })
  .describe('Target GitHub repository parameters');

const refOrSessionShape = {
  owner: ownerField,
  repo: repoField,
  ref: refField,
  sessionId: sessionIdOptionalField,
};

function noBothRefAndSession(v: { ref?: string; sessionId?: string }): boolean {
  return !(v.ref && v.sessionId);
}

const REF_OR_SESSION_MSG = {
  message: 'Specify either ref or sessionId, not both',
};

export const FileWriteOperationSchema = z
  .object({
    path: z.string().min(1).describe('POSIX relative path within the repository'),
    content: z
      .string()
      .optional()
      .describe('File content (UTF-8 string or base64 depending on encoding); omit when delete=true'),
    encoding: z
      .enum(['utf-8', 'base64'])
      .optional()
      .describe('Content encoding: utf-8 (default) or base64'),
    delete: z
      .boolean()
      .optional()
      .describe('Set true to delete the file at path instead of writing content'),
  })
  .refine(
    (op) => (op.delete === true ? op.content === undefined : op.content !== undefined),
    {
      message: 'Specify either content (when writing) or delete=true (when deleting), not both',
    },
  )
  .describe('Single file write or delete operation');

export type FileWriteOperationInput = z.infer<typeof FileWriteOperationSchema>;

export const StartSessionSchema = z
  .object({
    owner: ownerField,
    repo: repoField,
    sessionId: z
      .string()
      .min(1)
      .optional()
      .describe('Optional custom session ID (generated automatically if omitted)'),
    baseBranch: z
      .string()
      .min(1)
      .optional()
      .describe('Base branch name (defaults to repository default branch)'),
    title: z.string().min(1).optional().describe('Pull request title'),
    description: z.string().optional().describe('Pull request body description'),
    draft: z
      .boolean()
      .optional()
      .describe('Open PR as draft when supported by the GitHub plan (default true)'),
    files: z
      .array(FileWriteOperationSchema)
      .optional()
      .describe('Optional initial files to commit immediately and open the PR'),
    commitMessage: z
      .string()
      .min(1)
      .optional()
      .describe('Optional commit message when initial files are provided'),
  })
  .describe('Start a PR-backed Wayfinder write session');

export type StartSessionInput = z.infer<typeof StartSessionSchema>;

const sessionWriteFields = {
  owner: ownerField,
  repo: repoField,
  sessionId: z
    .string()
    .min(1)
    .optional()
    .describe('Session ID (optional only when autoStart=true)'),
  autoStart: z
    .boolean()
    .optional()
    .describe('Automatically create the session branch and PR when sessionId is omitted or missing'),
  baseBranch: z
    .string()
    .min(1)
    .optional()
    .describe('Base branch when autoStart creates a new session or lazily opens a PR'),
  title: z.string().min(1).optional().describe('PR title when lazily opening the session PR'),
  description: z
    .string()
    .optional()
    .describe('PR body description when lazily opening the session PR'),
  draft: z
    .boolean()
    .optional()
    .describe('Open PR as draft when lazily opening the session PR (default true)'),
  expectedHeadSha: z
    .string()
    .min(1)
    .optional()
    .describe('Optimistic concurrency check: expected current head commit SHA'),
  commitMessage: z.string().min(1).optional().describe('Commit message for this atomic write'),
  files: z
    .array(FileWriteOperationSchema)
    .min(1)
    .describe('1..N atomic file write or delete operations'),
};

export const SessionWriteSchema = z
  .object(sessionWriteFields)
  .refine((v) => Boolean(v.sessionId || v.autoStart), {
    message: 'sessionId is required unless autoStart is true',
  })
  .describe('Atomically write/delete files on a session branch');

export type SessionWriteInput = z.infer<typeof SessionWriteSchema>;

export const ListSessionsSchema = z
  .object({
    owner: ownerField,
    repo: repoField,
    state: z
      .enum(['open', 'closed', 'all'])
      .optional()
      .describe('Filter by PR state (default open)'),
    limit: z
      .number()
      .int()
      .min(1)
      .max(100)
      .optional()
      .describe('Maximum sessions per page (1-100, default 25)'),
    page: z.number().int().min(1).optional().describe('1-based page number (default 1)'),
  })
  .describe('List PR-backed Wayfinder sessions');

export type ListSessionsInput = z.infer<typeof ListSessionsSchema>;

export const GetSessionSchema = z
  .object({
    owner: ownerField,
    repo: repoField,
    sessionId: sessionIdRequiredField,
  })
  .describe('Inspect a PR-backed Wayfinder session');

export type GetSessionInput = z.infer<typeof GetSessionSchema>;

const commitSessionBodyShape = {
  owner: ownerField,
  repo: repoField,
  expectedHeadSha: z
    .string()
    .min(1)
    .optional()
    .describe('Optimistic concurrency check: expected head commit SHA before merge'),
  mergeMethod: z
    .enum(['squash', 'merge', 'rebase'])
    .optional()
    .describe('GitHub PR merge method (default squash)'),
  commitTitle: z.string().min(1).optional().describe('Custom merge commit title'),
  commitMessage: z.string().optional().describe('Custom merge commit message'),
  deleteBranch: z
    .boolean()
    .optional()
    .describe('Delete session branch after merge (default true)'),
  requireChecks: z
    .boolean()
    .optional()
    .describe('Verify GitHub check runs on headSha are passing before merging'),
  requiredCheckNames: z
    .array(z.string().min(1))
    .optional()
    .describe('Optional specific check-run names required when requireChecks=true'),
};

export const CommitSessionSchema = z
  .object({
    ...commitSessionBodyShape,
    sessionId: sessionIdRequiredField,
  })
  .describe('Ready, verify, merge, and clean up a PR-backed session');

export type CommitSessionInput = z.infer<typeof CommitSessionSchema>;

const closeSessionBodyShape = {
  owner: ownerField,
  repo: repoField,
  reason: z.string().min(1).optional().describe('Optional closing comment posted on the PR'),
  deleteBranch: z
    .boolean()
    .optional()
    .describe('Delete session branch after closing PR (default true)'),
};

export const CloseSessionSchema = z
  .object({
    ...closeSessionBodyShape,
    sessionId: sessionIdRequiredField,
  })
  .describe('Close a session PR without merging and delete the branch');

export type CloseSessionInput = z.infer<typeof CloseSessionSchema>;

export const RepoInfoSchema = RepoTargetSchema;
export type RepoInfoInput = z.infer<typeof RepoInfoSchema>;

export const PullTreeSchema = z
  .object({
    ...refOrSessionShape,
    pathPrefix: z.string().optional().describe('Filter tree entries by relative path prefix'),
    bundlePath: z
      .string()
      .optional()
      .describe('Optional bundle root path used for OKF classification'),
    recursive: z.boolean().optional().describe('Recursively list tree entries (default true)'),
    limit: z
      .number()
      .int()
      .min(1)
      .max(5000)
      .optional()
      .describe('Maximum entries returned (1-5000, default 1000)'),
  })
  .refine(noBothRefAndSession, REF_OR_SESSION_MSG)
  .describe('List repository tree with Wayfinder OKF file classification');

export type PullTreeInput = z.infer<typeof PullTreeSchema>;

export const PullFileSchema = z
  .object({
    ...refOrSessionShape,
    path: z.string().min(1).describe('POSIX relative path to file'),
    encoding: z
      .enum(['utf-8', 'base64'])
      .optional()
      .describe('Preferred return encoding (default utf-8 for text, base64 for binary)'),
  })
  .refine(noBothRefAndSession, REF_OR_SESSION_MSG)
  .describe('Read a single file with YAML frontmatter extraction');

export type PullFileInput = z.infer<typeof PullFileSchema>;

export const PullBundleSchema = z
  .object({
    ...refOrSessionShape,
    bundlePath: z
      .string()
      .optional()
      .describe('Optional bundle path override (defaults to wayfinder.json applies_to roots)'),
    maxFiles: z
      .number()
      .int()
      .min(1)
      .max(2000)
      .optional()
      .describe('Maximum bundle Markdown documents to return (default 500)'),
    maxTotalBytes: z
      .number()
      .int()
      .min(1024)
      .max(50 * 1024 * 1024)
      .optional()
      .describe('Maximum cumulative content bytes to return (default 10 MiB)'),
  })
  .refine(noBothRefAndSession, REF_OR_SESSION_MSG)
  .describe('Pull wayfinder.json, wayfinder.lock, and Markdown bundle documents via tarball');

export type PullBundleInput = z.infer<typeof PullBundleSchema>;

export const SearchRepositorySchema = z
  .object({
    ...refOrSessionShape,
    query: z.string().optional().describe('Case-insensitive substring search query'),
    type: z.string().optional().describe('Filter by OKF frontmatter type'),
    tag: z.string().optional().describe('Filter by OKF frontmatter tag'),
    status: z.string().optional().describe('Filter by OKF frontmatter status'),
    pathPrefix: z
      .string()
      .optional()
      .describe('Relative path prefix to scope search (defaults to bundlePath)'),
    bundlePath: z.string().optional().describe('Fallback bundle path prefix when pathPrefix omitted'),
    limit: z
      .number()
      .int()
      .min(1)
      .max(200)
      .optional()
      .describe('Maximum search hits to return (1-200, default 25)'),
  })
  .refine(noBothRefAndSession, REF_OR_SESSION_MSG)
  .describe('Live search across repository/session Markdown documents and OKF frontmatter');

export type SearchRepositoryInput = z.infer<typeof SearchRepositorySchema>;
