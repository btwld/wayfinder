import { parse as parseYaml } from 'yaml';

export interface ParsedFrontmatter {
  hasFrontmatter: boolean;
  frontmatter: Record<string, unknown> | null;
  body: string;
  rawFrontmatter?: string;
  frontmatterError?: string;
}

const FRONTMATTER_RE = /^---[ \t]*\r?\n([\s\S]*?\r?\n)?(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/;
const EMPTY_FRONTMATTER_RE = /^---[ \t]*\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/;

export function parseFrontmatter(markdown: string): ParsedFrontmatter {
  const source = markdown.startsWith('\uFEFF') ? markdown.slice(1) : markdown;

  if (EMPTY_FRONTMATTER_RE.test(source)) {
    const match = source.match(EMPTY_FRONTMATTER_RE)!;
    return {
      hasFrontmatter: true,
      frontmatter: {},
      body: source.slice(match[0].length),
      rawFrontmatter: '',
    };
  }

  const match = source.match(FRONTMATTER_RE);
  if (!match) {
    return {
      hasFrontmatter: false,
      frontmatter: null,
      body: source,
    };
  }

  const rawBlock = (match[1] ?? '').replace(/\r?\n$/, '');
  const body = source.slice(match[0].length);

  try {
    const parsed: unknown = parseYaml(rawBlock);
    if (parsed === null || parsed === undefined) {
      return {
        hasFrontmatter: true,
        frontmatter: {},
        body,
        rawFrontmatter: rawBlock,
      };
    }
    if (typeof parsed !== 'object' || Array.isArray(parsed)) {
      return {
        hasFrontmatter: true,
        frontmatter: null,
        body,
        rawFrontmatter: rawBlock,
        frontmatterError: 'YAML frontmatter must deserialize to a mapping/object',
      };
    }
    return {
      hasFrontmatter: true,
      frontmatter: parsed as Record<string, unknown>,
      body,
      rawFrontmatter: rawBlock,
    };
  } catch (error) {
    return {
      hasFrontmatter: true,
      frontmatter: null,
      body,
      rawFrontmatter: rawBlock,
      frontmatterError: error instanceof Error ? error.message : String(error),
    };
  }
}
