import { createHash, timingSafeEqual } from 'node:crypto';
import { McpBearerGuard } from '@nest-mcp/server';
import {
  CanActivate,
  ExecutionContext,
  Injectable,
} from '@nestjs/common';
import { ModuleRef } from '@nestjs/core';
import { UnauthorizedProxyError } from '../common/errors';
import { extractRequestHeaders, getHeaderValue } from '../common/token-extractor';
import { PROXY_CONFIG, type ProxyConfig } from '../config/proxy-config';

function sha256(value: string): Buffer {
  return createHash('sha256').update(value, 'utf8').digest();
}

function constantTimeIncludes(candidates: string[], presented: string): boolean {
  const presentedHash = sha256(presented);
  let matched = false;
  for (const candidate of candidates) {
    const candidateHash = sha256(candidate);
    if (timingSafeEqual(candidateHash, presentedHash)) {
      matched = true;
    }
  }
  return matched;
}

@Injectable()
export class ProxyAuthGuard implements CanActivate {
  private config?: ProxyConfig;
  private bearerGuard?: McpBearerGuard;

  constructor(private readonly moduleRef: ModuleRef) {}

  private resolveConfig(): ProxyConfig {
    if (!this.config) {
      this.config = this.moduleRef.get(PROXY_CONFIG, { strict: false });
    }
    return this.config;
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const config = this.resolveConfig();
    const mode = config.auth.mode;

    if (mode === 'none') {
      return true;
    }

    if (mode === 'unconfigured') {
      throw new UnauthorizedProxyError(
        'Proxy authentication is not configured. Configure PROXY_API_KEYS, OAuth, Firebase Auth, or explicitly set ALLOW_UNAUTHENTICATED_ACCESS=true for local development.',
      );
    }

    if (mode === 'api-key') {
      const req = context.switchToHttp().getRequest<unknown>();
      const headers = extractRequestHeaders(req);
      let key = getHeaderValue(headers, 'x-api-key')?.trim();

      if (!key) {
        const authHeader = getHeaderValue(headers, 'authorization');
        if (authHeader) {
          const [scheme, value] = authHeader.split(/\s+/, 2);
          if (scheme?.toLowerCase() === 'apikey' && value) {
            key = value.trim();
          }
        }
      }

      if (!key || !constantTimeIncludes(config.auth.apiKeys, key)) {
        throw new UnauthorizedProxyError('Missing or invalid API key');
      }

      return true;
    }

    // mode === 'oauth' || mode === 'firebase'
    if (!this.bearerGuard) {
      this.bearerGuard = this.moduleRef.get(McpBearerGuard, { strict: false });
    }
    return this.bearerGuard.canActivate(context);
  }
}
