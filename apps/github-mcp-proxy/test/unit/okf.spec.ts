import { describe, expect, it } from 'vitest';
import { BadRequestProxyError } from '../../src/common/errors';
import { extractGzipTarball } from '../../src/github/tarball';
import { classifyOkfFile } from '../../src/okf/classify';
import { parseFrontmatter } from '../../src/okf/frontmatter';
import { parseWayfinderJson } from '../../src/okf/wayfinder-config';
import { createTestGzipTarball } from '../fakes/fake-github-api';

describe('OKF frontmatter parser (yaml)', () => {
  it('parses complex OKF relationships, sources, block scalars, and quoted colons', () => {
    const markdown = [
      '---',
      'type: Request',
      'title: "Auth: OAuth 2.0 & Token Exchange"',
      'description: |',
      '  Multi-line description:',
      '  keeps indentation and colons intact.',
      'status: draft',
      'tags: [auth, security]',
      'generated: { by: claude-code/opus-5, at: 2026-07-30T16:20:00Z }',
      'relationships:',
      '  - relationship: specified-by',
      '    resource: https://github.com/btwld/wayfinder/issues/128',
      '  - relationship: assessed-by',
      '    resource: /reporting/pdf-export-feasibility.md',
      '---',
      '',
      '# Heading',
      'Body content here.',
      '',
    ].join('\n');

    const parsed = parseFrontmatter(markdown);
    expect(parsed.hasFrontmatter).toBe(true);
    expect(parsed.frontmatterError).toBeUndefined();
    expect(parsed.frontmatter).toMatchObject({
      type: 'Request',
      title: 'Auth: OAuth 2.0 & Token Exchange',
      status: 'draft',
      tags: ['auth', 'security'],
      generated: { by: 'claude-code/opus-5' },
      relationships: [
        {
          relationship: 'specified-by',
          resource: 'https://github.com/btwld/wayfinder/issues/128',
        },
        {
          relationship: 'assessed-by',
          resource: '/reporting/pdf-export-feasibility.md',
        },
      ],
    });
    expect(parsed.frontmatter?.description).toContain('Multi-line description:');
    expect(parsed.body).toBe('\n# Heading\nBody content here.\n');
  });

  it('handles missing and malformed YAML frontmatter gracefully', () => {
    const plain = parseFrontmatter('# Plain Markdown\nNo frontmatter.\n');
    expect(plain.hasFrontmatter).toBe(false);
    expect(plain.frontmatter).toBeNull();
    expect(plain.body).toContain('# Plain Markdown');

    const bad = parseFrontmatter('---\ntitle: [unclosed\n---\n\nBody\n');
    expect(bad.hasFrontmatter).toBe(true);
    expect(bad.frontmatter).toBeNull();
    expect(bad.frontmatterError).toBeTruthy();
    expect(bad.body).toBe('\nBody\n');
  });
});

describe('OKF file classification & wayfinder.json', () => {
  it('classifies concept, index, log, config, attachment, and other files', () => {
    const bundleRoots = ['knowledge'];
    expect(classifyOkfFile('wayfinder.json', { bundleRoots })).toBe('config');
    expect(classifyOkfFile('wayfinder.lock', { bundleRoots })).toBe('config');
    expect(classifyOkfFile('knowledge/index.md', { bundleRoots })).toBe('index');
    expect(classifyOkfFile('knowledge/reporting/index.md', { bundleRoots })).toBe('index');
    expect(classifyOkfFile('knowledge/log.md', { bundleRoots })).toBe('log');
    expect(classifyOkfFile('knowledge/reporting/pdf-export.md', { bundleRoots })).toBe('concept');
    expect(classifyOkfFile('knowledge/assets/diagram.png', { bundleRoots })).toBe('attachment');
    expect(classifyOkfFile('knowledge/references/data.json', { bundleRoots })).toBe('attachment');
    expect(classifyOkfFile('README.md', { bundleRoots })).toBe('other');
    expect(classifyOkfFile('src/main.ts', { bundleRoots })).toBe('other');
  });

  it('parses applies_to roots from wayfinder.json', () => {
    const parsed = parseWayfinderJson(
      JSON.stringify({
        version: 1,
        profiles: {
          bitwild: {
            source: { git: 'https://github.com/btwld/wayfinder', ref: 'main', path: 'profiles/bitwild' },
            applies_to: ['./knowledge', './docs/notes/'],
          },
        },
      }),
    );

    expect(parsed.version).toBe(1);
    expect(parsed.appliesTo).toEqual(['knowledge', 'docs/notes']);
    expect(parsed.profiles).toHaveLength(1);
  });
});

describe('Tarball extraction', () => {
  it('extracts USTAR and multi-record UTF-8 PAX entries and strips GitHub root prefix', async () => {
    const longPath =
      'knowledge/deeply/nested/subdirectory/for/testing/pax/headers/' +
      'very-long-concept-document-name-exceeding-one-hundred-characters.md';
    const utf8Path = 'knowledge/café-résumé-日本語.md';

    const gz = createTestGzipTarball('btwld-wayfinder-abc1234', [
      { path: 'wayfinder.json', content: Buffer.from('{"version":1}', 'utf8') },
      { path: longPath, content: Buffer.from('# Long Path Concept\n', 'utf8') },
      { path: utf8Path, content: Buffer.from('# UTF-8 Concept\n', 'utf8'), forcePax: true },
    ]);

    const { entries, truncated } = await extractGzipTarball(gz);
    expect(truncated).toBe(false);
    expect(entries.map((e) => e.path)).toEqual(['wayfinder.json', longPath, utf8Path]);
    expect(entries[1].content.toString('utf8')).toBe('# Long Path Concept\n');
    expect(entries[2].content.toString('utf8')).toBe('# UTF-8 Concept\n');
  });

  it('rejects corrupt gzip buffers with BadRequestProxyError', async () => {
    await expect(extractGzipTarball(Buffer.from('not-a-gzip', 'utf8'))).rejects.toThrow(
      BadRequestProxyError,
    );
  });
});
