import 'reflect-metadata';
import { Logger, ShutdownSignal } from '@nestjs/common';
import { createProxyApp } from './app.factory';
import { loadProxyConfig } from './config/proxy-config';

async function bootstrap(): Promise<void> {
  const logger = new Logger('Bootstrap');
  const config = loadProxyConfig();
  const { app } = await createProxyApp({ config });

  app.enableShutdownHooks([ShutdownSignal.SIGTERM, ShutdownSignal.SIGINT], {
    useProcessExit: true,
  });

  await app.listen(config.port, config.host);
  logger.log(
    `Wayfinder GitHub MCP Proxy listening on http://${config.host}:${config.port} ` +
      `(mcp=${config.mcp.endpoint}, auth=${config.auth.mode}, allowedRepos=${config.github.allowedRepos.size})`,
  );
}

bootstrap().catch((error) => {
  const logger = new Logger('Bootstrap');
  logger.error(error instanceof Error ? error.stack ?? error.message : String(error));
  process.exit(1);
});
