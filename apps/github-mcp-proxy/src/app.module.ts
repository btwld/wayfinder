import {
  McpAuthModule,
  McpModule,
  McpTransportType,
  type BearerTokenVerifier,
} from '@nest-mcp/server';
import { DynamicModule, Module } from '@nestjs/common';
import { ProxyAuthGuard } from './auth/proxy-auth.guard';
import { PROXY_CONFIG, type ProxyConfig } from './config/proxy-config';
import { GitHubApiClient } from './github/github-api.client';
import {
  GITHUB_API_CLIENT,
  type IGitHubApiClient,
} from './github/github-api.interface';
import { HealthController } from './http/health.controller';
import { ProxyController } from './http/proxy.controller';
import { WayfinderMcpResources } from './mcp/wayfinder-mcp.resources';
import { WayfinderMcpTools } from './mcp/wayfinder-mcp.tools';
import { RepositoryService } from './repository/repository.service';
import { SessionService } from './sessions/session.service';

export interface AppModuleOptions {
  config: ProxyConfig;
  githubApiClient?: IGitHubApiClient;
  bearerVerifier?: BearerTokenVerifier;
}

function buildAuthImports(
  config: ProxyConfig,
  bearerVerifier?: BearerTokenVerifier,
): DynamicModule[] {
  if (config.auth.mode === 'oauth' && config.auth.oauth) {
    const oauth = config.auth.oauth;
    return [
      McpAuthModule.forRoot({
        resource: oauth.resource,
        authorizationServers: oauth.authorizationServers,
        requiredScopes: oauth.requiredScopes,
        validateAudience: oauth.validateAudience,
        ...(bearerVerifier
          ? { verifier: bearerVerifier }
          : oauth.jwksUri
            ? {
                jwks: {
                  uri: oauth.jwksUri,
                  issuer: oauth.issuer ?? oauth.authorizationServers[0],
                  audience: oauth.audience,
                },
              }
            : {
                introspection: {
                  endpoint: oauth.introspectionEndpoint!,
                  clientId: oauth.introspectionClientId ?? '',
                  clientSecret: oauth.introspectionClientSecret ?? '',
                },
              }),
      }),
    ];
  }

  if (config.auth.mode === 'firebase' && config.auth.firebase) {
    const fb = config.auth.firebase;
    const issuer = `https://securetoken.google.com/${fb.projectId}`;
    return [
      McpAuthModule.forRoot({
        resource: fb.resource,
        authorizationServers: [issuer],
        requiredScopes: fb.requiredScopes,
        ...(bearerVerifier
          ? { verifier: bearerVerifier }
          : {
              jwks: {
                uri: 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
                issuer,
                audience: fb.projectId,
                algorithms: ['RS256'],
              },
            }),
      }),
    ];
  }

  return [];
}

@Module({})
export class AppModule {
  static register(options: AppModuleOptions): DynamicModule {
    const { config, githubApiClient, bearerVerifier } = options;
    const usesBearerOauth = config.auth.mode === 'oauth' || config.auth.mode === 'firebase';
    const usesControllerGuard =
      config.auth.mode === 'api-key' || config.auth.mode === 'unconfigured';

    return {
      module: AppModule,
      imports: [
        ...buildAuthImports(config, bearerVerifier),
        McpModule.forRoot({
          name: 'wayfinder-github-mcp-proxy',
          version: '0.1.0',
          description:
            'Stateless GitHub-backed Wayfinder OKF bundle inspection, search, and PR write-session MCP server',
          transport: McpTransportType.STREAMABLE_HTTP,
          transportOptions: {
            streamableHttp: {
              endpoint: config.mcp.endpoint,
              stateless: true,
              enableJsonResponse: config.mcp.enableJsonResponse,
              ...(usesBearerOauth
                ? {
                    oauth: {
                      enabled: true,
                      bindSessionToUser: false,
                    },
                  }
                : {}),
              ...(usesControllerGuard
                ? {
                    controllerGuards: [ProxyAuthGuard],
                  }
                : {}),
            },
          },
          // Note: in @nest-mcp/server@0.8.1 HTTP auth is enforced by oauth.enabled / controllerGuards above.
          allowUnauthenticatedAccess: config.auth.mode === 'none',
          resilience: {
            timeout: config.resilience.timeoutMs,
            rateLimit: {
              max: config.resilience.rateLimitMax,
              window: config.resilience.rateLimitWindow,
            },
          },
          capabilities: {
            tools: {},
            resources: {},
          },
        }),
      ],
      controllers: [HealthController, ProxyController],
      providers: [
        { provide: PROXY_CONFIG, useValue: config },
        githubApiClient
          ? { provide: GITHUB_API_CLIENT, useValue: githubApiClient }
          : { provide: GITHUB_API_CLIENT, useClass: GitHubApiClient },
        ProxyAuthGuard,
        SessionService,
        RepositoryService,
        WayfinderMcpTools,
        WayfinderMcpResources,
      ],
      exports: [PROXY_CONFIG, GITHUB_API_CLIENT, SessionService, RepositoryService],
    };
  }
}
