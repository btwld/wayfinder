import 'reflect-metadata';
import type { Request, Response } from 'express';
import { onRequest, type HttpsFunction, type HttpsOptions } from 'firebase-functions/v2/https';
import {
  createProxyApp,
  createServerlessExpressHandler,
  type CreateProxyAppOptions,
  type ProxyAppContext,
  type ServerlessExpressHandler,
} from './app.factory';

export { AppModule, type AppModuleOptions } from './app.module';
export { loadProxyConfig, PROXY_CONFIG, type ProxyAuthMode, type ProxyConfig } from './config/proxy-config';
export { RepoAllowlist } from './config/repo-allowlist';
export {
  createProxyApp,
  createServerlessExpressHandler,
  type CreateProxyAppOptions,
  type ProxyAppContext,
  type ServerlessExpressHandler,
};

export function createFirebaseMcpFunction(
  httpsOptions: HttpsOptions = {},
  appOptions: CreateProxyAppOptions = {},
): HttpsFunction {
  const handler = createServerlessExpressHandler(appOptions);
  return onRequest(
    {
      cors: false,
      ...httpsOptions,
    },
    async (req, res) => {
      await handler(req as unknown as Request, res as unknown as Response);
    },
  );
}

export const wayfinderGithubMcp: HttpsFunction = createFirebaseMcpFunction();
