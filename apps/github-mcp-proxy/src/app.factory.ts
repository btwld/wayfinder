import type { BearerTokenVerifier } from '@nest-mcp/server';
import { INestApplication, LoggerService } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { ExpressAdapter } from '@nestjs/platform-express';
import cors from 'cors';
import express, { type Express, type NextFunction, type Request, type Response } from 'express';
import { AppModule } from './app.module';
import { ForbiddenProxyError, ProxyHttpExceptionFilter } from './common/errors';
import { loadProxyConfig, type ProxyConfig } from './config/proxy-config';
import type { IGitHubApiClient } from './github/github-api.interface';

export interface CreateProxyAppOptions {
  config?: ProxyConfig;
  githubApiClient?: IGitHubApiClient;
  bearerVerifier?: BearerTokenVerifier;
  logger?: LoggerService | false;
}

export interface ProxyAppContext {
  app: INestApplication;
  expressApp: Express;
  config: ProxyConfig;
}

export type ServerlessExpressHandler = ((
  req: Request,
  res: Response,
) => Promise<void>) & {
  close: () => Promise<void>;
};

export async function createProxyApp(
  options: CreateProxyAppOptions = {},
): Promise<ProxyAppContext> {
  const config = options.config ?? loadProxyConfig();
  const expressApp = express();
  expressApp.disable('x-powered-by');

  if (config.cors.origins.length > 0) {
    const allowedOrigins = new Set(config.cors.origins);
    expressApp.use(
      cors({
        origin(origin, callback) {
          if (!origin || allowedOrigins.has(origin)) {
            callback(null, true);
            return;
          }
          callback(new ForbiddenProxyError(`Origin "${origin}" is not allowed by CORS_ORIGINS`));
        },
      }),
    );
    expressApp.use(
      (err: unknown, req: Request, res: Response, next: NextFunction) => {
        if (err instanceof ForbiddenProxyError) {
          res.status(err.statusCode).json({
            error: {
              code: err.code,
              message: err.message,
              path: req.originalUrl ?? req.url,
            },
          });
          return;
        }
        next(err);
      },
    );
  }

  // Firebase Cloud Functions v2 pre-parses req.body before invoking the handler.
  // Skip express.json() when req.body is already populated so the drained stream
  // does not hang or throw, while still parsing JSON in standalone / Cloud Run mode.
  const jsonParser = express.json({ limit: '10mb' });
  expressApp.use((req: Request, res: Response, next: NextFunction) => {
    if (req.body !== undefined) {
      next();
      return;
    }
    jsonParser(req, res, next);
  });

  const app = await NestFactory.create(
    AppModule.register({
      config,
      githubApiClient: options.githubApiClient,
      bearerVerifier: options.bearerVerifier,
    }),
    new ExpressAdapter(expressApp),
    {
      bodyParser: false,
      ...(options.logger !== undefined ? { logger: options.logger } : {}),
    },
  );

  app.useGlobalFilters(new ProxyHttpExceptionFilter());

  return { app, expressApp, config };
}

export function createServerlessExpressHandler(
  options: CreateProxyAppOptions = {},
): ServerlessExpressHandler {
  let contextPromise: Promise<ProxyAppContext> | null = null;

  const ensureInitialized = (): Promise<ProxyAppContext> => {
    if (!contextPromise) {
      contextPromise = (async () => {
        const ctx = await createProxyApp(options);
        await ctx.app.init();
        return ctx;
      })().catch((error) => {
        contextPromise = null;
        throw error;
      });
    }
    return contextPromise;
  };

  const handler = async (req: Request, res: Response): Promise<void> => {
    const { expressApp } = await ensureInitialized();

    await new Promise<void>((resolve, reject) => {
      let settled = false;

      const cleanup = () => {
        res.removeListener('finish', onDone);
        res.removeListener('close', onDone);
        res.removeListener('error', onError);
      };

      const onDone = () => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve();
      };

      const onError = (err: unknown) => {
        if (settled) return;
        settled = true;
        cleanup();
        reject(err);
      };

      res.once('finish', onDone);
      res.once('close', onDone);
      res.once('error', onError);

      expressApp(req, res, (err?: unknown) => {
        if (err) {
          onError(err);
          return;
        }
        if (!res.headersSent && !res.writableEnded) {
          res.status(404).json({
            error: {
              code: 'NOT_FOUND',
              message: `Route ${req.method} ${req.originalUrl ?? req.url} not found`,
            },
          });
          return;
        }
        if (res.writableEnded) {
          onDone();
        }
      });
    });
  };

  handler.close = async (): Promise<void> => {
    if (!contextPromise) return;
    const ctx = await contextPromise;
    contextPromise = null;
    await ctx.app.close();
  };

  return handler;
}
