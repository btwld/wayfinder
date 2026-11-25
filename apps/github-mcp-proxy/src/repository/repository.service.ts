import { Inject, Injectable, Logger } from '@nestjs/common';
import { BadRequestProxyError, NotFoundProxyError, UpstreamGitHubError } from '../common/errors';
import {
  assertSafeRepoPath,
  assertSafeSessionId,
  normalizeOptionalPrefix,
} from '../common/path-safety';
import { PROXY_CONFIG, type ProxyConfig } from '../config/proxy-config';
import { resolveAndAuthorizeRepoTarget } from '../config/repo-target';
import {
  GITHUB_API_CLIENT,
  type IGitHubApiClient,
} from '../github/github-api.interface';
import { extractGzipTarball } from '../github/tarball';
import {
  classifyOkfFile,
  isBinaryAttachmentPath,
  isPathWithinRoot,
  type OkfFileKind,
} from '../okf/classify';
import { parseFrontmatter } from '../okf/frontmatter';
import { parseWayfinderJson, type ParsedWayfinderConfig } from '../okf/wayfinder-config';
import type {
  PullBundleInput,
  PullFileInput,
  PullTreeInput,
  RepoInfoInput,
  SearchRepositoryInput,
} from '../schemas/proxy.schemas';

export interface SearchHit {
  path: string;
  kind: OkfFileKind;
  title: string | null;
  type: string | null;
  status: string | null;
  tags: string[];
  score: number;
  frontmatter: Record<string, unknown> | null;
  snippets: Array<{ line: number; text: string }>;
}

function decodeBase64ToBuffer(encoded: string): Buffer {
  return Buffer.from(encoded.replace(/\s+/g, ''), 'base64');
}

function extractTags(frontmatter: Record<string, unknown> | null): string[] {
  const raw = frontmatter?.tags;
  if (!Array.isArray(raw)) return [];
  return raw.filter((item): item is string => typeof item === 'string');
}

function extractSnippets(body: string, queryLower: string, maxSnippets = 3): Array<{ line: number; text: string }> {
  const lines = body.split(/\r?\n/);
  const snippets: Array<{ line: number; text: string }> = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].toLowerCase().includes(queryLower)) {
      snippets.push({
        line: i + 1,
        text: lines[i].trim().slice(0, 240),
      });
      if (snippets.length >= maxSnippets) break;
    }
  }
  return snippets;
}

@Injectable()
export class RepositoryService {
  private readonly logger = new Logger(RepositoryService.name);

  constructor(
    @Inject(PROXY_CONFIG) private readonly config: ProxyConfig,
    @Inject(GITHUB_API_CLIENT) private readonly github: IGitHubApiClient,
  ) {}

  async getRepoInfo(input: RepoInfoInput, token?: string) {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    const info = await this.github.getRepo(owner, repo, token);
    return {
      id: info.id,
      owner: info.owner,
      repo: info.name,
      fullName: info.fullName,
      description: info.description,
      private: info.private,
      defaultBranch: info.defaultBranch,
      htmlUrl: info.htmlUrl,
      archived: info.archived,
      pushedAt: info.pushedAt,
      updatedAt: info.updatedAt,
      permissions: info.permissions ?? null,
    };
  }

  async pullTree(input: PullTreeInput, token?: string) {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    const ref = await this.resolveTargetRef(owner, repo, input, token);
    const recursive = input.recursive ?? true;
    const limit = input.limit ?? 1000;

    const commit = await this.github.resolveCommit(owner, repo, ref, token);
    const treeResp = await this.github.getTree(owner, repo, commit.treeSha, recursive, token);

    const pathPrefix = normalizeOptionalPrefix(input.pathPrefix);
    const explicitBundle = normalizeOptionalPrefix(input.bundlePath);

    let bundleRoots: string[] | undefined;
    if (explicitBundle !== undefined) {
      bundleRoots = [explicitBundle];
    } else {
      const wayfinderEntry = treeResp.tree.find(
        (entry) => entry.type === 'blob' && entry.path === 'wayfinder.json',
      );
      if (wayfinderEntry) {
        try {
          const blob = await this.github.getBlob(owner, repo, wayfinderEntry.sha, token);
          const configText =
            blob.encoding === 'base64'
              ? decodeBase64ToBuffer(blob.content).toString('utf8')
              : blob.content;
          const parsedConfig = parseWayfinderJson(configText);
          if (parsedConfig.appliesTo.length > 0) {
            bundleRoots = parsedConfig.appliesTo;
          }
        } catch (error) {
          const isMissingOrInvalidEntry =
            error instanceof NotFoundProxyError ||
            error instanceof BadRequestProxyError ||
            (error instanceof UpstreamGitHubError && error.githubStatus === 404);
          if (!isMissingOrInvalidEntry) {
            throw error;
          }
          this.logger.warn(
            `Falling back to default OKF classification for ${owner}/${repo}@${commit.sha}: ${error.message}`,
          );
        }
      }
    }

    const filtered = treeResp.tree.filter((entry) => {
      if (entry.type !== 'blob') return false;
      if (pathPrefix !== undefined && pathPrefix !== '') {
        return isPathWithinRoot(entry.path, pathPrefix);
      }
      return true;
    });

    const entries = filtered.slice(0, limit).map((entry) => ({
      path: entry.path,
      sha: entry.sha,
      size: entry.size ?? null,
      mode: entry.mode,
      kind: classifyOkfFile(entry.path, { bundleRoots }),
    }));

    return {
      owner,
      repo,
      ref,
      commitSha: commit.sha,
      treeSha: treeResp.sha,
      bundleRoots: bundleRoots ?? null,
      totalCount: filtered.length,
      returnedCount: entries.length,
      truncated: treeResp.truncated || filtered.length > limit,
      entries,
    };
  }

  async pullFile(input: PullFileInput, token?: string) {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    const safePath = assertSafeRepoPath(input.path);
    const ref = await this.resolveTargetRef(owner, repo, input, token);

    const { buffer, sha, size, fetchedVia } = await this.readFileBufferWithBlobFallback(
      owner,
      repo,
      safePath,
      ref,
      token,
    );

    const isBinary = isBinaryAttachmentPath(safePath, buffer);
    const useBase64 = input.encoding === 'base64' || (input.encoding === undefined && isBinary);
    const kind = classifyOkfFile(safePath);

    if (useBase64) {
      return {
        owner,
        repo,
        ref,
        path: safePath,
        sha,
        size,
        encoding: 'base64' as const,
        binary: isBinary,
        kind,
        fetchedVia,
        content: buffer.toString('base64'),
      };
    }

    const text = buffer.toString('utf8');
    const isMarkdown = safePath.endsWith('.md');
    const parsed = isMarkdown ? parseFrontmatter(text) : null;

    return {
      owner,
      repo,
      ref,
      path: safePath,
      sha,
      size,
      encoding: 'utf-8' as const,
      binary: false,
      kind,
      fetchedVia,
      content: text,
      ...(parsed
        ? {
            hasFrontmatter: parsed.hasFrontmatter,
            frontmatter: parsed.frontmatter,
            ...(parsed.frontmatterError ? { frontmatterError: parsed.frontmatterError } : {}),
            body: parsed.body,
          }
        : {}),
    };
  }

  async pullBundle(input: PullBundleInput, token?: string) {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    const ref = await this.resolveTargetRef(owner, repo, input, token);
    const maxFiles = input.maxFiles ?? this.config.limits.maxBundleFiles;
    const maxTotalBytes = input.maxTotalBytes ?? this.config.limits.maxBundleTotalBytes;

    const tarball = await this.github.downloadTarball(owner, repo, ref, token);
    const extracted = await extractGzipTarball(tarball, {
      maxUncompressedBytes: this.config.limits.maxTarballBytes * 3,
    });

    const byPath = new Map(extracted.entries.map((entry) => [entry.path, entry]));
    const wayfinderJsonEntry = byPath.get('wayfinder.json');
    const wayfinderLockEntry = byPath.get('wayfinder.lock');

    const wayfinderConfig: ParsedWayfinderConfig | null = wayfinderJsonEntry
      ? parseWayfinderJson(wayfinderJsonEntry.content.toString('utf8'))
      : null;

    const explicitBundle = normalizeOptionalPrefix(input.bundlePath);
    let bundleRoots: string[];
    if (explicitBundle !== undefined) {
      bundleRoots = [explicitBundle];
    } else if (wayfinderConfig && wayfinderConfig.appliesTo.length > 0) {
      bundleRoots = wayfinderConfig.appliesTo;
    } else if (extracted.entries.some((e) => isPathWithinRoot(e.path, 'knowledge'))) {
      bundleRoots = ['knowledge'];
    } else {
      bundleRoots = [''];
    }

    const documents: Array<{
      path: string;
      kind: OkfFileKind;
      size: number;
      hasFrontmatter: boolean;
      frontmatter: Record<string, unknown> | null;
      frontmatterError?: string;
      body: string;
    }> = [];

    const omittedAttachments: Array<{ path: string; kind: OkfFileKind; size: number }> = [];
    let totalBytes = 0;
    let truncated = extracted.truncated;

    const sortedEntries = [...extracted.entries].sort((a, b) => a.path.localeCompare(b.path));

    for (const entry of sortedEntries) {
      if (!bundleRoots.some((root) => isPathWithinRoot(entry.path, root))) {
        continue;
      }

      const kind = classifyOkfFile(entry.path, { bundleRoots });
      if (kind === 'config') {
        continue;
      }
      if (kind === 'attachment' || isBinaryAttachmentPath(entry.path, entry.content)) {
        omittedAttachments.push({ path: entry.path, kind: 'attachment', size: entry.size });
        continue;
      }
      if (!entry.path.endsWith('.md')) {
        continue;
      }

      if (documents.length >= maxFiles || totalBytes + entry.size > maxTotalBytes) {
        truncated = true;
        continue;
      }

      const text = entry.content.toString('utf8');
      const parsed = parseFrontmatter(text);
      totalBytes += entry.size;

      documents.push({
        path: entry.path,
        kind,
        size: entry.size,
        hasFrontmatter: parsed.hasFrontmatter,
        frontmatter: parsed.frontmatter,
        ...(parsed.frontmatterError ? { frontmatterError: parsed.frontmatterError } : {}),
        body: parsed.body,
      });
    }

    return {
      owner,
      repo,
      ref,
      bundleRoots,
      wayfinderJson: wayfinderConfig
        ? {
            version: wayfinderConfig.version,
            appliesTo: wayfinderConfig.appliesTo,
            profiles: wayfinderConfig.profiles,
            raw: wayfinderConfig.raw,
            ...(wayfinderConfig.parseError ? { parseError: wayfinderConfig.parseError } : {}),
          }
        : null,
      wayfinderLock: wayfinderLockEntry ? wayfinderLockEntry.content.toString('utf8') : null,
      documentCount: documents.length,
      totalBytes,
      truncated,
      omittedAttachments,
      documents,
    };
  }

  async searchRepository(input: SearchRepositoryInput, token?: string) {
    const { owner, repo } = resolveAndAuthorizeRepoTarget(this.config, input);
    const ref = await this.resolveTargetRef(owner, repo, input, token);
    const limit = input.limit ?? 25;

    const effectivePrefix = normalizeOptionalPrefix(input.pathPrefix ?? input.bundlePath);
    const tarball = await this.github.downloadTarball(owner, repo, ref, token);
    const extracted = await extractGzipTarball(tarball, {
      maxUncompressedBytes: this.config.limits.maxTarballBytes * 3,
    });

    const wayfinderJsonEntry = extracted.entries.find((e) => e.path === 'wayfinder.json');
    const wayfinderConfig = wayfinderJsonEntry
      ? parseWayfinderJson(wayfinderJsonEntry.content.toString('utf8'))
      : null;
    const bundleRoots =
      effectivePrefix !== undefined
        ? [effectivePrefix]
        : wayfinderConfig && wayfinderConfig.appliesTo.length > 0
          ? wayfinderConfig.appliesTo
          : undefined;

    const queryLower = input.query?.trim().toLowerCase() || undefined;
    const typeLower = input.type?.trim().toLowerCase() || undefined;
    const tagLower = input.tag?.trim().toLowerCase() || undefined;
    const statusLower = input.status?.trim().toLowerCase() || undefined;

    const markdownEntries = extracted.entries
      .filter((entry) => {
        if (!entry.path.endsWith('.md')) return false;
        if (effectivePrefix !== undefined && effectivePrefix !== '') {
          return isPathWithinRoot(entry.path, effectivePrefix);
        }
        return true;
      })
      .sort((a, b) => a.path.localeCompare(b.path));

    let scannedFiles = 0;
    let scanTruncated = extracted.truncated;
    const allHits: SearchHit[] = [];

    for (const entry of markdownEntries) {
      if (scannedFiles >= this.config.limits.maxSearchFilesScanned) {
        scanTruncated = true;
        break;
      }
      scannedFiles++;

      if (isBinaryAttachmentPath(entry.path, entry.content)) {
        continue;
      }

      const rawText = entry.content.toString('utf8');
      const parsed = parseFrontmatter(rawText);
      const fm = parsed.frontmatter;
      const docType = typeof fm?.type === 'string' ? fm.type : null;
      const docStatus = typeof fm?.status === 'string' ? fm.status : null;
      const docTitle = typeof fm?.title === 'string' ? fm.title : null;
      const docDesc = typeof fm?.description === 'string' ? fm.description : null;
      const docTags = extractTags(fm);

      if (typeLower && docType?.toLowerCase() !== typeLower) {
        continue;
      }
      if (statusLower && docStatus?.toLowerCase() !== statusLower) {
        continue;
      }
      if (tagLower && !docTags.some((t) => t.toLowerCase() === tagLower)) {
        continue;
      }

      let score = 1;
      let snippets: Array<{ line: number; text: string }> = [];

      if (queryLower) {
        let matched = false;
        score = 0;

        if (entry.path.toLowerCase().includes(queryLower)) {
          score += 5;
          matched = true;
        }
        if (docTitle && docTitle.toLowerCase().includes(queryLower)) {
          score += 6;
          matched = true;
        }
        if (docDesc && docDesc.toLowerCase().includes(queryLower)) {
          score += 4;
          matched = true;
        }
        if (parsed.rawFrontmatter && parsed.rawFrontmatter.toLowerCase().includes(queryLower)) {
          score += 2;
          matched = true;
        }
        if (parsed.body.toLowerCase().includes(queryLower)) {
          score += 3;
          matched = true;
          snippets = extractSnippets(parsed.body, queryLower);
        }

        if (!matched) {
          continue;
        }
      }

      allHits.push({
        path: entry.path,
        kind: classifyOkfFile(entry.path, { bundleRoots }),
        title: docTitle,
        type: docType,
        status: docStatus,
        tags: docTags,
        score,
        frontmatter: fm,
        snippets,
      });
    }

    allHits.sort((a, b) => b.score - a.score || a.path.localeCompare(b.path));
    const hits = allHits.slice(0, limit);
    const truncated = scanTruncated || allHits.length > limit;

    return {
      owner,
      repo,
      ref,
      pathPrefix: effectivePrefix ?? null,
      scannedFiles,
      totalMatches: allHits.length,
      returnedCount: hits.length,
      truncated,
      results: hits,
    };
  }

  private async resolveTargetRef(
    owner: string,
    repo: string,
    input: { ref?: string; sessionId?: string },
    token?: string,
  ): Promise<string> {
    if (input.sessionId) {
      return `${this.config.sessions.branchPrefix}${assertSafeSessionId(input.sessionId)}`;
    }
    if (input.ref?.trim()) {
      return input.ref.trim();
    }
    const repoInfo = await this.github.getRepo(owner, repo, token);
    return repoInfo.defaultBranch;
  }

  private async readFileBufferWithBlobFallback(
    owner: string,
    repo: string,
    safePath: string,
    ref: string,
    token?: string,
  ): Promise<{ buffer: Buffer; sha: string; size: number; fetchedVia: 'contents' | 'git-blob' }> {
    const contentResp = await this.github.getContent(owner, repo, safePath, ref, token);

    if (contentResp.kind === 'file' && contentResp.content !== undefined) {
      const buffer =
        contentResp.encoding === 'base64'
          ? decodeBase64ToBuffer(contentResp.content)
          : Buffer.from(contentResp.content, 'utf8');
      return {
        buffer,
        sha: contentResp.sha ?? '',
        size: contentResp.size ?? buffer.length,
        fetchedVia: 'contents',
      };
    }

    let blobSha = contentResp.sha;
    if (!blobSha) {
      const commit = await this.github.resolveCommit(owner, repo, ref, token);
      const tree = await this.github.getTree(owner, repo, commit.treeSha, true, token);
      const entry = tree.tree.find((item) => item.type === 'blob' && item.path === safePath);
      if (!entry) {
        throw new NotFoundProxyError(`File "${safePath}" not found at ref "${ref}"`, {
          path: safePath,
          ref,
        });
      }
      blobSha = entry.sha;
    }

    const blob = await this.github.getBlob(owner, repo, blobSha, token);
    const buffer =
      blob.encoding === 'base64'
        ? decodeBase64ToBuffer(blob.content)
        : Buffer.from(blob.content, 'utf8');

    return {
      buffer,
      sha: blob.sha,
      size: blob.size ?? buffer.length,
      fetchedVia: 'git-blob',
    };
  }
}
