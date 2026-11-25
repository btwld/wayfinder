export type OkfFileKind = 'concept' | 'index' | 'log' | 'config' | 'attachment' | 'other';

const CONFIG_BASENAMES = new Set([
  'wayfinder.json',
  'wayfinder.lock',
  'wayfinder-profile.json',
  '.okf.lock',
]);

const KNOWN_ATTACHMENT_EXTENSIONS = new Set([
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.svg',
  '.ico',
  '.bmp',
  '.tif',
  '.tiff',
  '.pdf',
  '.csv',
  '.tsv',
  '.xls',
  '.xlsx',
  '.doc',
  '.docx',
  '.ppt',
  '.pptx',
  '.zip',
  '.tar',
  '.gz',
  '.tgz',
  '.mp3',
  '.mp4',
  '.wav',
  '.mov',
]);

const KNOWN_BINARY_EXTENSIONS = new Set([
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.ico',
  '.bmp',
  '.tif',
  '.tiff',
  '.pdf',
  '.xls',
  '.xlsx',
  '.doc',
  '.docx',
  '.ppt',
  '.pptx',
  '.zip',
  '.tar',
  '.gz',
  '.tgz',
  '.mp3',
  '.mp4',
  '.wav',
  '.mov',
  '.woff',
  '.woff2',
  '.ttf',
  '.otf',
  '.eot',
  '.bin',
  '.exe',
  '.wasm',
]);

function posixBasename(relativePath: string): string {
  const idx = relativePath.lastIndexOf('/');
  return idx === -1 ? relativePath : relativePath.slice(idx + 1);
}

function lowerExtension(relativePath: string): string {
  const base = posixBasename(relativePath);
  const dot = base.lastIndexOf('.');
  return dot > 0 ? base.slice(dot).toLowerCase() : '';
}

export function isPathWithinRoot(relativePath: string, root: string): boolean {
  if (root === '') return true;
  return relativePath === root || relativePath.startsWith(`${root}/`);
}

export function classifyOkfFile(
  relativePath: string,
  options?: { bundleRoots?: string[] },
): OkfFileKind {
  const clean = relativePath.replace(/^\/+/, '');
  const base = posixBasename(clean);

  if (CONFIG_BASENAMES.has(base)) {
    return 'config';
  }

  const bundleRoots = options?.bundleRoots;
  const hasExplicitBundleRoots = bundleRoots !== undefined && bundleRoots.length > 0;
  const inBundle = hasExplicitBundleRoots
    ? bundleRoots.some((root) => isPathWithinRoot(clean, root))
    : !clean.startsWith('.');

  if (!inBundle) {
    return 'other';
  }

  // OKF reserves case-sensitive `.md`, `index.md`, and `log.md`.
  if (clean.endsWith('.md')) {
    if (base === 'index.md') return 'index';
    if (base === 'log.md') return 'log';
    return 'concept';
  }

  const ext = lowerExtension(clean);
  if (hasExplicitBundleRoots || KNOWN_ATTACHMENT_EXTENSIONS.has(ext)) {
    return 'attachment';
  }

  return 'other';
}

export function isBinaryAttachmentPath(relativePath: string, content?: Buffer): boolean {
  const ext = lowerExtension(relativePath);
  if (KNOWN_BINARY_EXTENSIONS.has(ext)) {
    return true;
  }
  if (!content) {
    return false;
  }
  const sampleLen = Math.min(content.length, 8192);
  for (let i = 0; i < sampleLen; i++) {
    if (content[i] === 0) {
      return true;
    }
  }
  return false;
}
