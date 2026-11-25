import { EventEmitter } from 'node:events';
import { PassThrough, Readable } from 'node:stream';
import type { Request, Response } from 'express';
import { afterEach, describe, expect, it } from 'vitest';
import {
  createServerlessExpressHandler,
  type ServerlessExpressHandler,
} from '../../src/app.factory';
import { loadProxyConfig } from '../../src/config/proxy-config';
import { createFirebaseMcpFunction } from '../../src/index';
import { FakeGitHubApi } from '../fakes/fake-github-api';

interface MockFirebaseResponse {
  statusCode: number;
  headers: Record<string, string | string[]>;
  bodyText: string;
  ended: boolean;
  res: Response;
}

function createMockFirebaseRequest(options: {
  method: string;
  url: string;
  headers?: Record<string, string>;
  body?: unknown;
}): Request {
  // Simulate Firebase Cloud Functions v2 request where the HTTP stream is already
  // drained and `req.body` + `req.rawBody` have been pre-populated.
  const stream = new Readable({
    read() {
      this.push(null);
    },
  });

  const normalizedHeaders: Record<string, string> = {
    host: 'us-central1-wayfinder.cloudfunctions.net',
    ...Object.fromEntries(
      Object.entries(options.headers ?? {}).map(([k, v]) => [k.toLowerCase(), v]),
    ),
  };
  const rawHeaders = Object.entries(normalizedHeaders).flatMap(([k, v]) => [k, v]);

  const rawText = options.body !== undefined ? JSON.stringify(options.body) : '';
  const req = Object.assign(stream, {
    method: options.method,
    url: options.url,
    originalUrl: options.url,
    headers: normalizedHeaders,
    rawHeaders,
    body: options.body,
    rawBody: Buffer.from(rawText, 'utf8'),
    ip: '127.0.0.1',
    protocol: 'https',
    socket: Object.assign(new PassThrough(), { encrypted: true }),
    get(name: string) {
      return (this.headers as Record<string, string | undefined>)[name.toLowerCase()];
    },
  });

  return req as unknown as Request;
}

function createMockFirebaseResponse(options?: { delayFinishMs?: number }): MockFirebaseResponse {
  const emitter = new EventEmitter();
  const state: MockFirebaseResponse = {
    statusCode: 200,
    headers: {},
    bodyText: '',
    ended: false,
    res: null as unknown as Response,
  };

  const chunks: Buffer[] = [];

  const resObj = Object.assign(emitter, {
    locals: {},
    headersSent: false,
    writableEnded: false,
    get statusCode() {
      return state.statusCode;
    },
    set statusCode(code: number) {
      state.statusCode = code;
    },
    status(code: number) {
      state.statusCode = code;
      return resObj;
    },
    setHeader(name: string, value: string | string[]) {
      state.headers[name.toLowerCase()] = value;
      return resObj;
    },
    getHeader(name: string) {
      return state.headers[name.toLowerCase()];
    },
    getHeaders() {
      return { ...state.headers };
    },
    removeHeader(name: string) {
      delete state.headers[name.toLowerCase()];
    },
    header(name: string, value: string | string[]) {
      state.headers[name.toLowerCase()] = value;
      return resObj;
    },
    set(name: string, value: string | string[]) {
      state.headers[name.toLowerCase()] = value;
      return resObj;
    },
    type(mime: string) {
      state.headers['content-type'] = mime;
      return resObj;
    },
    writeHead(statusCode: number, hdrs?: Record<string, string | string[]>) {
      state.statusCode = statusCode;
      if (hdrs) {
        for (const [k, v] of Object.entries(hdrs)) {
          state.headers[k.toLowerCase()] = v;
        }
      }
      resObj.headersSent = true;
      return resObj;
    },
    write(chunk: string | Buffer) {
      resObj.headersSent = true;
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, 'utf8'));
      return true;
    },
    json(payload: unknown) {
      state.headers['content-type'] = 'application/json';
      return resObj.end(JSON.stringify(payload));
    },
    send(payload: unknown) {
      if (typeof payload === 'object' && payload !== null && !Buffer.isBuffer(payload)) {
        return resObj.json(payload);
      }
      return resObj.end(payload as string | Buffer);
    },
    end(chunk?: string | Buffer) {
      if (chunk !== undefined) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk, 'utf8'));
      }
      state.bodyText = Buffer.concat(chunks).toString('utf8');
      resObj.headersSent = true;
      resObj.writableEnded = true;
      const complete = () => {
        state.ended = true;
        emitter.emit('finish');
        emitter.emit('close');
      };
      if (options?.delayFinishMs) {
        setTimeout(complete, options.delayFinishMs);
      } else {
        queueMicrotask(complete);
      }
      return resObj;
    },
  });

  state.res = resObj as unknown as Response;
  return state;
}

describe('Firebase Cloud Functions v2 serverless handler', () => {
  const handlers: ServerlessExpressHandler[] = [];

  afterEach(async () => {
    while (handlers.length > 0) {
      const h = handlers.pop()!;
      await h.close();
    }
  });

  it('handles pre-parsed req.body on /api/* and /mcp and waits for response completion', async () => {
    const fakeGitHub = new FakeGitHubApi();
    fakeGitHub.seedRepository('btwld', 'wayfinder', {
      'knowledge/index.md': '# Index\n',
    });

    const config = loadProxyConfig({
      GITHUB_OWNER: 'btwld',
      GITHUB_REPO: 'wayfinder',
      GITHUB_TOKEN: 'ghp_fb',
      PROXY_AUTH_MODE: 'api-key',
      PROXY_API_KEYS: 'fb-key',
    });

    const handler = createServerlessExpressHandler({
      config,
      githubApiClient: fakeGitHub,
      logger: false,
    });
    handlers.push(handler);

    // REST POST with pre-parsed req.body + delayed finish (verifies async await)
    const req1 = createMockFirebaseRequest({
      method: 'POST',
      url: '/api/sessions',
      headers: {
        'content-type': 'application/json',
        'x-api-key': 'fb-key',
      },
      body: {
        sessionId: 'fb-sess-1',
        files: [{ path: 'knowledge/from-firebase.md', content: '# From Firebase\n' }],
      },
    });
    const res1 = createMockFirebaseResponse({ delayFinishMs: 30 });

    await handler(req1, res1.res);
    expect(res1.ended).toBe(true);
    expect(res1.statusCode).toBe(201);
    const parsedRest = JSON.parse(res1.bodyText);
    expect(parsedRest.sessionId).toBe('fb-sess-1');
    expect(parsedRest.prNumber).toBe(1);

    // MCP Streamable HTTP POST with pre-parsed req.body
    const req2 = createMockFirebaseRequest({
      method: 'POST',
      url: '/mcp',
      headers: {
        'content-type': 'application/json',
        accept: 'application/json, text/event-stream',
        'x-api-key': 'fb-key',
      },
      body: {
        jsonrpc: '2.0',
        id: 1,
        method: 'tools/call',
        params: {
          name: 'get_session',
          arguments: { sessionId: 'fb-sess-1' },
        },
      },
    });
    const res2 = createMockFirebaseResponse({ delayFinishMs: 20 });

    await handler(req2, res2.res);
    expect(res2.ended).toBe(true);
    expect(res2.statusCode).toBe(200);
    const parsedMcp = JSON.parse(res2.bodyText);
    const sessionData = JSON.parse(parsedMcp.result.content[0].text);
    expect(sessionData.sessionId).toBe('fb-sess-1');
    expect(sessionData.state).toBe('open');

    // Unknown route returns JSON 404
    const req404 = createMockFirebaseRequest({
      method: 'GET',
      url: '/nonexistent-route',
    });
    const res404 = createMockFirebaseResponse();
    await handler(req404, res404.res);
    expect(res404.ended).toBe(true);
    expect(res404.statusCode).toBe(404);
    expect(JSON.parse(res404.bodyText)).toMatchObject({
      statusCode: 404,
      error: 'Not Found',
    });

    // Verify createFirebaseMcpFunction exports a valid Firebase v2 onRequest HttpsFunction
    const fn = createFirebaseMcpFunction(
      { region: 'us-central1' },
      { config, githubApiClient: fakeGitHub, logger: false },
    );
    expect(typeof fn).toBe('function');
    expect(typeof fn.__endpoint).toBe('object');
  });
});
