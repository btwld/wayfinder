import { BadRequestProxyError } from './errors';

const SESSION_ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const CONTROL_CHAR_RE = /[\x00-\x1f\x7f]/;

export interface WriteOpPathCheck {
  path: string;
  delete?: boolean;
  content?: string;
}

export function assertSafeRepoPath(rawPath: string): string {
  if (typeof rawPath !== 'string') {
    throw new BadRequestProxyError('Path must be a string');
  }
  if (rawPath.includes('\0') || CONTROL_CHAR_RE.test(rawPath)) {
    throw new BadRequestProxyError('Path contains forbidden control characters or NUL bytes');
  }
  const trimmed = rawPath.trim();
  if (!trimmed) {
    throw new BadRequestProxyError('Path must not be empty');
  }
  if (trimmed.includes('\\')) {
    throw new BadRequestProxyError(`Path "${rawPath}" must use POSIX "/" separators`);
  }
  if (trimmed.startsWith('/') || trimmed.endsWith('/')) {
    throw new BadRequestProxyError(`Path "${rawPath}" must be relative without leading or trailing "/"`);
  }

  const segments = trimmed.split('/');
  for (const segment of segments) {
    if (!segment) {
      throw new BadRequestProxyError(`Path "${rawPath}" contains an empty path segment`);
    }
    if (segment === '.' || segment === '..') {
      throw new BadRequestProxyError(`Path "${rawPath}" must not contain "." or ".." segments`);
    }
    if (segment.toLowerCase() === '.git') {
      throw new BadRequestProxyError(`Path "${rawPath}" must not target ".git"`);
    }
  }

  return trimmed;
}

export function normalizeOptionalPrefix(rawPrefix?: string): string | undefined {
  if (rawPrefix === undefined) return undefined;
  if (typeof rawPrefix !== 'string') {
    throw new BadRequestProxyError('Path prefix must be a string');
  }
  if (rawPrefix.includes('\0') || CONTROL_CHAR_RE.test(rawPrefix)) {
    throw new BadRequestProxyError('Path prefix contains forbidden control characters or NUL bytes');
  }
  let normalized = rawPrefix.trim();
  if (!normalized || normalized === '.') {
    return '';
  }
  while (normalized.startsWith('./')) {
    normalized = normalized.slice(2);
  }
  normalized = normalized.replace(/\/+$/, '');
  if (!normalized || normalized === '.') {
    return '';
  }
  return assertSafeRepoPath(normalized);
}

export function assertSafeWriteBatch(operations: WriteOpPathCheck[]): void {
  const seen = new Set<string>();
  for (const op of operations) {
    const safePath = assertSafeRepoPath(op.path);
    if (seen.has(safePath)) {
      throw new BadRequestProxyError(`Duplicate path in write batch: "${safePath}"`);
    }
    seen.add(safePath);

    const isDelete = op.delete === true;
    const hasContent = op.content !== undefined;
    if (isDelete && hasContent) {
      throw new BadRequestProxyError(
        `File operation for "${safePath}" cannot specify both delete=true and content`,
      );
    }
    if (!isDelete && !hasContent) {
      throw new BadRequestProxyError(
        `File operation for "${safePath}" must specify content or delete=true`,
      );
    }
  }
}

export function assertSafeSessionId(sessionId: string): string {
  if (typeof sessionId !== 'string') {
    throw new BadRequestProxyError('sessionId must be a string');
  }
  const trimmed = sessionId.trim();
  if (
    !SESSION_ID_RE.test(trimmed) ||
    trimmed.includes('..') ||
    trimmed.endsWith('.') ||
    trimmed.endsWith('.lock')
  ) {
    throw new BadRequestProxyError(
      `Invalid sessionId "${sessionId}". Allowed: 1-64 alphanumeric, ".", "_", "-" characters without ".." or ".lock".`,
    );
  }
  return trimmed;
}

export function encodeGitRefPath(ref: string): string {
  const trimmed = ref.trim();
  if (!trimmed || trimmed.includes('\0') || CONTROL_CHAR_RE.test(trimmed)) {
    throw new BadRequestProxyError('Invalid Git ref');
  }
  return trimmed
    .split('/')
    .map((segment) => {
      if (!segment || segment === '.' || segment === '..') {
        throw new BadRequestProxyError(`Invalid segment in Git ref "${ref}"`);
      }
      return encodeURIComponent(segment);
    })
    .join('/');
}

export function encodeContentPath(filePath: string): string {
  return assertSafeRepoPath(filePath)
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
}
