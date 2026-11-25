import type { McpExecutionContext, ResourceReadResult } from '@nest-mcp/common';
import { ResourceTemplate } from '@nest-mcp/server';
import { Inject, Injectable, UseFilters } from '@nestjs/common';
import { ProxyMcpExceptionFilter } from '../common/errors';
import { resolveGithubToken } from '../common/token-extractor';
import { PROXY_CONFIG, type ProxyConfig } from '../config/proxy-config';
import { RepositoryService } from '../repository/repository.service';
import { SessionService } from '../sessions/session.service';

@Injectable()
@UseFilters(ProxyMcpExceptionFilter)
export class WayfinderMcpResources {
  constructor(
    @Inject(PROXY_CONFIG) private readonly config: ProxyConfig,
    private readonly sessionService: SessionService,
    private readonly repositoryService: RepositoryService,
  ) {}

  @ResourceTemplate({
    uriTemplate: 'wayfinder-github://{owner}/{repo}/sessions/{sessionId}',
    name: 'wayfinder-github-session',
    description: 'Inspect state, PR metadata, and changed files for a GitHub-backed Wayfinder session',
    mimeType: 'application/json',
  })
  async readSessionResource(
    uri: URL,
    params: Record<string, string>,
    ctx: McpExecutionContext,
  ): Promise<ResourceReadResult> {
    const token = resolveGithubToken(ctx.request, this.config);
    const session = await this.sessionService.getSession(
      {
        owner: params.owner,
        repo: params.repo,
        sessionId: params.sessionId,
      },
      token,
    );

    return {
      contents: [
        {
          uri: uri.href,
          mimeType: 'application/json',
          text: JSON.stringify(session, null, 2),
        },
      ],
    };
  }

  @ResourceTemplate({
    uriTemplate: 'wayfinder-github://{owner}/{repo}/bundle/{ref}',
    name: 'wayfinder-github-bundle',
    description:
      'Read a Wayfinder OKF bundle snapshot (wayfinder.json, wayfinder.lock, Markdown docs) at a Git ref (percent-encode "/" in refs such as wayfinder%2Fsession%2F<id>)',
    mimeType: 'application/json',
  })
  async readBundleResource(
    uri: URL,
    params: Record<string, string>,
    ctx: McpExecutionContext,
  ): Promise<ResourceReadResult> {
    const token = resolveGithubToken(ctx.request, this.config);
    const bundle = await this.repositoryService.pullBundle(
      {
        owner: params.owner,
        repo: params.repo,
        ref: params.ref,
      },
      token,
    );

    return {
      contents: [
        {
          uri: uri.href,
          mimeType: 'application/json',
          text: JSON.stringify(bundle, null, 2),
        },
      ],
    };
  }
}
