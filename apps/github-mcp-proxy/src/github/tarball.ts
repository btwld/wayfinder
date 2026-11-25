import { promisify } from 'node:util';
import * as zlib from 'node:zlib';
import { BadRequestProxyError } from '../common/errors';
import { assertSafeRepoPath } from '../common/path-safety';

const gunzipAsync = promisify(zlib.gunzip);

export interface TarEntry {
  path: string;
  content: Buffer;
  size: number;
}

export interface ExtractTarballOptions {
  maxUncompressedBytes?: number;
  maxEntries?: number;
}

export interface ExtractTarballResult {
  entries: TarEntry[];
  truncated: boolean;
}

function readAscii(buf: Buffer, start: number, end: number): string {
  const slice = buf.subarray(start, end);
  const nul = slice.indexOf(0);
  const clean = nul === -1 ? slice : slice.subarray(0, nul);
  return clean.toString('utf8').trim();
}

function parseTarSize(buf: Buffer, offset: number): number {
  const firstByte = buf[offset];
  // GNU/POSIX base-256 size encoding when high bit is set
  if ((firstByte & 0x80) !== 0) {
    let size = BigInt(firstByte & 0x7f);
    for (let i = 1; i < 12; i++) {
      size = (size << 8n) | BigInt(buf[offset + i]);
    }
    return Number(size);
  }
  const raw = readAscii(buf, offset, offset + 12);
  if (!raw) return 0;
  const parsed = Number.parseInt(raw, 8);
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new BadRequestProxyError(`Invalid tar entry size: "${raw}"`);
  }
  return parsed;
}

function parsePaxRecords(data: Buffer): Record<string, string> {
  const records: Record<string, string> = {};
  let cursor = 0;

  while (cursor < data.length) {
    const spaceIdx = data.indexOf(0x20, cursor);
    if (spaceIdx === -1) break;
    const length = Number.parseInt(data.subarray(cursor, spaceIdx).toString('ascii'), 10);
    if (!Number.isFinite(length) || length <= 0) break;

    const recordEnd = Math.min(cursor + length, data.length);
    const valueEnd =
      recordEnd > spaceIdx + 1 && data[recordEnd - 1] === 0x0a
        ? recordEnd - 1
        : recordEnd;
    const line = data.subarray(spaceIdx + 1, valueEnd).toString('utf8');
    const eqIdx = line.indexOf('=');
    if (eqIdx !== -1) {
      records[line.slice(0, eqIdx)] = line.slice(eqIdx + 1);
    }
    cursor += length;
  }

  return records;
}

function stripGithubTarPrefix(rawPath: string): string | null {
  const trimmed = rawPath.replace(/^\.\//, '').replace(/\/+$/, '');
  if (!trimmed) return null;
  const slashIdx = trimmed.indexOf('/');
  if (slashIdx === -1) {
    return null;
  }
  const relative = trimmed.slice(slashIdx + 1);
  if (!relative) return null;
  try {
    return assertSafeRepoPath(relative);
  } catch {
    return null;
  }
}

export async function extractGzipTarball(
  gzBuffer: Buffer,
  options?: ExtractTarballOptions,
): Promise<ExtractTarballResult> {
  const maxOutputLength = options?.maxUncompressedBytes ?? 100 * 1024 * 1024;
  const maxEntries = options?.maxEntries ?? 10_000;

  let tar: Buffer;
  try {
    tar = await gunzipAsync(gzBuffer, { maxOutputLength });
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    throw new BadRequestProxyError(`Failed to decompress tarball: ${msg}`);
  }

  const entries: TarEntry[] = [];
  let truncated = false;

  let offset = 0;
  let paxHeaders: Record<string, string> | null = null;
  let gnuLongName: string | null = null;

  while (offset + 512 <= tar.length) {
    const header = tar.subarray(offset, offset + 512);
    offset += 512;

    if (header.every((b) => b === 0)) {
      break;
    }

    const name = readAscii(header, 0, 100);
    const prefix = readAscii(header, 345, 500);
    const typeFlagChar = header[156] === 0 ? '0' : String.fromCharCode(header[156]);
    let size = parseTarSize(header, 124);

    if (paxHeaders?.size) {
      const paxSize = Number.parseInt(paxHeaders.size, 10);
      if (Number.isFinite(paxSize) && paxSize >= 0) {
        size = paxSize;
      }
    }

    const dataStart = offset;
    const dataEnd = offset + size;
    if (dataEnd > tar.length) {
      throw new BadRequestProxyError('Truncated tar archive entry');
    }
    const data = tar.subarray(dataStart, dataEnd);
    const paddedSize = Math.ceil(size / 512) * 512;
    offset += paddedSize;

    if (typeFlagChar === 'x') {
      paxHeaders = { ...(paxHeaders ?? {}), ...parsePaxRecords(data) };
      continue;
    }
    if (typeFlagChar === 'g') {
      continue;
    }
    if (typeFlagChar === 'L') {
      gnuLongName = data.toString('utf8').replace(/\0+$/, '');
      continue;
    }

    const combinedName =
      paxHeaders?.path ??
      gnuLongName ??
      (prefix ? `${prefix}/${name}` : name);

    paxHeaders = null;
    gnuLongName = null;

    if (typeFlagChar !== '0') {
      continue;
    }

    const safeRelative = stripGithubTarPrefix(combinedName);
    if (!safeRelative) {
      continue;
    }

    if (entries.length >= maxEntries) {
      truncated = true;
      break;
    }

    entries.push({
      path: safeRelative,
      content: Buffer.from(data),
      size: data.length,
    });
  }

  return { entries, truncated };
}
