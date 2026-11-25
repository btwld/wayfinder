import { ArgumentsHost, Catch, ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import type { Request, Response } from 'express';

export class ProxyError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
    public readonly details?: Record<string, unknown>,
  ) {
    super(message);
    this.name = new.target.name;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

export class BadRequestProxyError extends ProxyError {
  constructor(message: string, details?: Record<string, unknown>) {
    super(400, 'BAD_REQUEST', message, details);
  }
}

export class UnauthorizedProxyError extends ProxyError {
  constructor(message = 'Authentication required', details?: Record<string, unknown>) {
    super(401, 'UNAUTHORIZED', message, details);
  }
}

export class ForbiddenProxyError extends ProxyError {
  constructor(message: string, details?: Record<string, unknown>) {
    super(403, 'FORBIDDEN', message, details);
  }
}

export class NotFoundProxyError extends ProxyError {
  constructor(message: string, details?: Record<string, unknown>) {
    super(404, 'NOT_FOUND', message, details);
  }
}

export class ConflictProxyError extends ProxyError {
  constructor(message: string, details?: Record<string, unknown>) {
    super(409, 'CONFLICT', message, details);
  }
}

export class UnprocessableProxyError extends ProxyError {
  constructor(message: string, details?: Record<string, unknown>) {
    super(422, 'UNPROCESSABLE_ENTITY', message, details);
  }
}

export class UpstreamGitHubError extends ProxyError {
  constructor(
    public readonly githubStatus: number,
    message: string,
    public readonly githubErrors?: unknown[],
    public readonly documentationUrl?: string,
  ) {
    const statusCode =
      githubStatus >= 400 && githubStatus < 500 ? githubStatus : 502;
    super(statusCode, 'GITHUB_API_ERROR', message, {
      githubStatus,
      ...(githubErrors && githubErrors.length > 0 ? { githubErrors } : {}),
      ...(documentationUrl ? { documentationUrl } : {}),
    });
  }
}

@Catch()
export class ProxyHttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(ProxyHttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const http = host.switchToHttp();
    const res = http.getResponse<Response>();
    const req = http.getRequest<Request>();

    if (res.headersSent) {
      return;
    }

    if (exception instanceof ProxyError) {
      res.status(exception.statusCode).json({
        error: {
          code: exception.code,
          message: exception.message,
          ...(exception.details ? { details: exception.details } : {}),
          path: req?.originalUrl ?? req?.url,
        },
      });
      return;
    }

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse();
      res.status(status).json(
        typeof body === 'object' && body !== null
          ? body
          : { error: { code: 'HTTP_ERROR', message: String(body) } },
      );
      return;
    }

    const message = exception instanceof Error ? exception.message : 'Internal server error';
    this.logger.error(`Unhandled HTTP exception on ${req?.method ?? ''} ${req?.url ?? ''}: ${message}`);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Internal server error',
      },
    });
  }
}

/**
 * Zero-argument Nest filter invoked by @nest-mcp/server's McpExceptionFilterRunner.
 * Converts ProxyError instances into clean JSON-RPC error messages while preserving
 * error recording in ExecutionPipelineService metrics.
 */
@Catch(ProxyError)
export class ProxyMcpExceptionFilter {
  catch(exception: ProxyError): string {
    return JSON.stringify({
      code: exception.code,
      statusCode: exception.statusCode,
      message: exception.message,
      ...(exception.details ? { details: exception.details } : {}),
    });
  }
}
