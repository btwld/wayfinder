import { Controller, Get, Inject } from '@nestjs/common';
import { PROXY_CONFIG, type ProxyConfig } from '../config/proxy-config';

@Controller('health')
export class HealthController {
  constructor(@Inject(PROXY_CONFIG) private readonly config: ProxyConfig) {}

  @Get()
  getHealth() {
    return {
      status: 'ok',
      service: 'wayfinder-github-mcp-proxy',
      stateless: this.config.mcp.stateless,
      authMode: this.config.auth.mode,
      allowRequestTokenOverride: this.config.github.allowRequestTokenOverride,
      allowedReposCount: this.config.github.allowedRepos.size,
    };
  }
}
