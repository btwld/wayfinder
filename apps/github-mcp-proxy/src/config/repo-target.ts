import { BadRequestProxyError } from '../common/errors';
import type { ProxyConfig } from './proxy-config';

export interface ResolvedRepoTarget {
  owner: string;
  repo: string;
}

export function resolveAndAuthorizeRepoTarget(
  config: ProxyConfig,
  input: { owner?: string; repo?: string },
): ResolvedRepoTarget {
  const owner = (input.owner ?? config.github.defaultOwner)?.trim();
  const repo = (input.repo ?? config.github.defaultRepo)?.trim();

  if (!owner || !repo) {
    throw new BadRequestProxyError(
      'Repository owner and repo are required (pass owner/repo or configure GITHUB_OWNER and GITHUB_REPO)',
    );
  }

  config.github.allowedRepos.assertAllowed(owner, repo);
  return { owner, repo };
}
