import {
  Body,
  Controller,
  Get,
  Inject,
  Param,
  Post,
  Query,
  Req,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';
import { ProxyAuthGuard } from '../auth/proxy-auth.guard';
import { ProxyHttpExceptionFilter } from '../common/errors';
import { requireGithubToken, resolveGithubToken } from '../common/token-extractor';
import { ZodValidationPipe } from '../common/zod-validation.pipe';
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

function mergeWithSessionId(
  raw: unknown,
  sessionId: string,
  defaultEmptyObject: boolean,
): unknown {
  if (raw === undefined) {
    return defaultEmptyObject ? { sessionId } : undefined;
  }
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    return { ...(raw as Record<string, unknown>), sessionId };
  }
  return raw;
}

@Controller('api')
@UseGuards(ProxyAuthGuard)
@UseFilters(ProxyHttpExceptionFilter)
export class ProxyController {
  private readonly sessionWritePipe = new ZodValidationPipe(SessionWriteSchema);
  private readonly getSessionPipe = new ZodValidationPipe(GetSessionSchema, {
    coerceQuery: true,
  });
  private readonly commitSessionPipe = new ZodValidationPipe(CommitSessionSchema);
  private readonly closeSessionPipe = new ZodValidationPipe(CloseSessionSchema);

  constructor(
    @Inject(PROXY_CONFIG) private readonly config: ProxyConfig,
    private readonly repositoryService: RepositoryService,
    private readonly sessionService: SessionService,
  ) {}

  @Get('repo')
  async getRepoInfo(
    @Query(new ZodValidationPipe(RepoInfoSchema, { coerceQuery: true }))
    query: RepoInfoInput,
    @Req() req: Request,
  ) {
    const token = resolveGithubToken(req, this.config);
    return this.repositoryService.getRepoInfo(query, token);
  }

  @Get('tree')
  async pullTree(
    @Query(new ZodValidationPipe(PullTreeSchema, { coerceQuery: true }))
    query: PullTreeInput,
    @Req() req: Request,
  ) {
    const token = resolveGithubToken(req, this.config);
    return this.repositoryService.pullTree(query, token);
  }

  @Get('file')
  async pullFile(
    @Query(new ZodValidationPipe(PullFileSchema, { coerceQuery: true }))
    query: PullFileInput,
    @Req() req: Request,
  ) {
    const token = resolveGithubToken(req, this.config);
    return this.repositoryService.pullFile(query, token);
  }

  @Get('bundle')
  async pullBundle(
    @Query(new ZodValidationPipe(PullBundleSchema, { coerceQuery: true }))
    query: PullBundleInput,
    @Req() req: Request,
  ) {
    const token = resolveGithubToken(req, this.config);
    return this.repositoryService.pullBundle(query, token);
  }

  @Get('search')
  async searchRepository(
    @Query(new ZodValidationPipe(SearchRepositorySchema, { coerceQuery: true }))
    query: SearchRepositoryInput,
    @Req() req: Request,
  ) {
    const token = resolveGithubToken(req, this.config);
    return this.repositoryService.searchRepository(query, token);
  }

  @Get('sessions')
  async listSessions(
    @Query(new ZodValidationPipe(ListSessionsSchema, { coerceQuery: true }))
    query: ListSessionsInput,
    @Req() req: Request,
  ) {
    const token = resolveGithubToken(req, this.config);
    return this.sessionService.listSessions(query, token);
  }

  @Post('sessions')
  async startSession(
    @Body(new ZodValidationPipe(StartSessionSchema, { defaultEmptyObject: true }))
    body: StartSessionInput,
    @Req() req: Request,
  ) {
    const token = requireGithubToken(req, this.config);
    return this.sessionService.startSession(body, token);
  }

  @Post('sessions/write')
  async writeWithAutoStart(
    @Body(new ZodValidationPipe(SessionWriteSchema))
    body: SessionWriteInput,
    @Req() req: Request,
  ) {
    const token = requireGithubToken(req, this.config);
    return this.sessionService.sessionWrite(body, token);
  }

  @Get('sessions/:sessionId')
  async getSession(
    @Param('sessionId') sessionId: string,
    @Query() query: Record<string, unknown>,
    @Req() req: Request,
  ) {
    const input = this.getSessionPipe.transform(
      mergeWithSessionId(query, sessionId, true),
    );
    const token = resolveGithubToken(req, this.config);
    return this.sessionService.getSession(input, token);
  }

  @Post('sessions/:sessionId/write')
  async sessionWrite(
    @Param('sessionId') sessionId: string,
    @Body() body: unknown,
    @Req() req: Request,
  ) {
    const input = this.sessionWritePipe.transform(
      mergeWithSessionId(body, sessionId, false),
    );
    const token = requireGithubToken(req, this.config);
    return this.sessionService.sessionWrite(input, token);
  }

  @Post('sessions/:sessionId/commit')
  async commitSession(
    @Param('sessionId') sessionId: string,
    @Body() body: unknown,
    @Req() req: Request,
  ) {
    const input = this.commitSessionPipe.transform(
      mergeWithSessionId(body, sessionId, true),
    );
    const token = requireGithubToken(req, this.config);
    return this.sessionService.commitSession(input, token);
  }

  @Post('sessions/:sessionId/close')
  async closeSession(
    @Param('sessionId') sessionId: string,
    @Body() body: unknown,
    @Req() req: Request,
  ) {
    const input = this.closeSessionPipe.transform(
      mergeWithSessionId(body, sessionId, true),
    );
    const token = requireGithubToken(req, this.config);
    return this.sessionService.closeSession(input, token);
  }
}
