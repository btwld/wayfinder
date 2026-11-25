# Wayfinder GitHub MCP Proxy & Test API

Stateless NestJS 11 + `@nest-mcp/server` proxy exposing Wayfinder OKF bundle inspection, live search, and PR-backed write sessions directly over the GitHub REST v3 and GraphQL v4 APIs—with zero local `git` binary and zero persistent disk.

## Runtime Targets

1. **Standalone HTTP / Cloud Run (`src/main.ts`)**
   ```bash
   npm ci
   npm run build
   npm start
   ```
2. **Firebase Cloud Functions v2 (`src/index.ts`, `firebase.json`)**
   Exports `wayfinderGithubMcp` and `createFirebaseMcpFunction` using `onRequest` from `firebase-functions/v2/https`.

## Endpoints

- `GET /health` — Public health and non-secret runtime metadata.
- `POST|GET|DELETE /mcp` — Stateless Streamable HTTP MCP transport (`enableJsonResponse: true` by default).
- `GET /api/repo` — Repository metadata and permissions.
- `GET /api/tree` — Recursive tree listing with Wayfinder OKF classification (`concept`, `index`, `log`, `config`, `attachment`, `other`).
- `GET /api/file` — File read (with Git Blobs API fallback for >1 MB files) and YAML frontmatter parsing.
- `GET /api/bundle` — Single-tarball bundle fetch (`wayfinder.json`, `wayfinder.lock`, and Markdown bundle documents; omits binary attachments).
- `GET /api/search` — Live text and OKF frontmatter search (`type`, `tag`, `status`, `pathPrefix`) across `ref` or uncommitted `sessionId`.
- `GET /api/sessions` / `POST /api/sessions` — List or start PR-backed write sessions (`wayfinder/session/<sessionId>`).
- `GET /api/sessions/:sessionId` — Inspect PR/session state and changed files.
- `POST /api/sessions/write` & `POST /api/sessions/:sessionId/write` — Atomic multi-file write/delete commits (supports `autoStart` and `expectedHeadSha`).
- `POST /api/sessions/:sessionId/commit` — Refuses empty sessions, verifies optional `requireChecks`, marks Draft PRs ready via GraphQL, merges with transient 405 retry, and deletes the session branch.
- `POST /api/sessions/:sessionId/close` — Optionally comments `reason`, closes PR without merging, and deletes the session branch.

## Security Configuration

- **Repo allowlist (`ALLOWED_REPOS`):** Locks `owner/repo` to an explicit comma-separated allowlist (defaulting to `GITHUB_OWNER/GITHUB_REPO` when set, otherwise deny-all).
- **Authentication (`PROXY_AUTH_MODE`):** Supports `api-key` (`x-api-key` or `Authorization: ApiKey ...`), `oauth` (`McpAuthModule` JWKS or introspection), `firebase` (Firebase Auth JWTs via `McpAuthModule`), or explicit `none` (`ALLOW_UNAUTHENTICATED_ACCESS=true`). Defaults to fail-closed (`unconfigured` -> `401`) when no credentials are configured.
- **Per-request GitHub token override:** Disabled by default. When `ALLOW_REQUEST_TOKEN_OVERRIDE=true`, reads ONLY `x-github-token` (never `Authorization: Bearer`).
- **CORS (`CORS_ORIGINS`):** Disabled unless explicit origins are configured.

## Local Verification

```bash
npm run typecheck
npm test
npm run build
```
