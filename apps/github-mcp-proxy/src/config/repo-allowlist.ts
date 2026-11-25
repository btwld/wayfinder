import { BadRequestProxyError, ForbiddenProxyError } from '../common/errors';

const REPO_SLUG_RE = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

export function normalizeRepoSlug(owner: string, repo: string): string {
  const cleanOwner = owner.trim();
  const cleanRepo = repo.trim();
  if (!cleanOwner || !cleanRepo) {
    throw new BadRequestProxyError('Both owner and repo must be non-empty');
  }
  const slug = `${cleanOwner}/${cleanRepo}`;
  if (!REPO_SLUG_RE.test(slug) || cleanOwner === '.' || cleanOwner === '..' || cleanRepo === '.' || cleanRepo === '..') {
    throw new BadRequestProxyError(`Invalid repository slug: ${slug}`);
  }
  return slug.toLowerCase();
}

export class RepoAllowlist {
  private readonly allowedSet: Set<string>;
  private readonly orderedList: string[];

  constructor(entries: string[]) {
    const seen = new Set<string>();
    const list: string[] = [];
    for (const raw of entries) {
      const trimmed = raw.trim();
      if (!trimmed) continue;
      if (trimmed.includes('*') || !REPO_SLUG_RE.test(trimmed)) {
        throw new Error(`Invalid ALLOWED_REPOS entry "${trimmed}". Expected "owner/repo" without wildcards.`);
      }
      const normalized = trimmed.toLowerCase();
      if (!seen.has(normalized)) {
        seen.add(normalized);
        list.push(normalized);
      }
    }
    this.allowedSet = seen;
    this.orderedList = list;
  }

  static fromEnv(
    allowedReposRaw: string | undefined,
    defaultOwner: string | undefined,
    defaultRepo: string | undefined,
  ): RepoAllowlist {
    const explicit = (allowedReposRaw ?? '')
      .split(',')
      .map((entry) => entry.trim())
      .filter(Boolean);

    if (explicit.length > 0) {
      return new RepoAllowlist(explicit);
    }

    if (defaultOwner?.trim() && defaultRepo?.trim()) {
      return new RepoAllowlist([`${defaultOwner.trim()}/${defaultRepo.trim()}`]);
    }

    return new RepoAllowlist([]);
  }

  isAllowed(owner: string, repo: string): boolean {
    try {
      return this.allowedSet.has(normalizeRepoSlug(owner, repo));
    } catch {
      return false;
    }
  }

  assertAllowed(owner: string, repo: string): void {
    const normalized = normalizeRepoSlug(owner, repo);
    if (!this.allowedSet.has(normalized)) {
      throw new ForbiddenProxyError(
        `Repository "${owner}/${repo}" is not in ALLOWED_REPOS`,
        {
          repository: normalized,
          allowedReposCount: this.orderedList.length,
        },
      );
    }
  }

  list(): string[] {
    return [...this.orderedList];
  }

  get size(): number {
    return this.orderedList.length;
  }
}
