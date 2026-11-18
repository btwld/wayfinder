"""The link checker's rules, without network or Dart."""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    'verify_links', Path(__file__).with_name('verify-links.py'))
links = importlib.util.module_from_spec(SPEC)
# dataclasses resolves a class's annotations through sys.modules.
sys.modules[SPEC.name] = links
SPEC.loader.exec_module(links)

ROOT = Path(__file__).resolve().parents[2]


class LinkRulesTest(unittest.TestCase):
    def tree(self, files):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        for path, text in files.items():
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_text(text, encoding='utf-8')
        return links.Tree.holding(root, files)

    def issues(self, files):
        return [
            (issue.rule, issue.source, issue.line)
            for issue in links.check(self.tree(files))
        ]

    def test_relative_link_resolves_from_the_page_and_a_leading_slash_from_the_root(self):
        files = {
            'README.md': '[a](docs/a.md)\n',
            'docs/a.md': (
                '# Top\n'
                '[sibling](b.md) [up](../README.md) [root](/docs/b.md)\n'
                '[directory](../docs/) [here](#top) ![image](b.md)\n'
                '\n'
                '[defined]: b.md\n'
            ),
            'docs/b.md': '',
        }
        self.assertEqual(self.issues(files), [])
        files['docs/a.md'] = '[bundle-absolute](/b.md)\n'
        self.assertEqual(self.issues(files), [('link-resolves', 'docs/a.md', 1)])

    def test_a_missing_target_and_a_target_above_the_root_are_issues(self):
        tree = self.tree({
            'docs/a.md': 'text\n[gone](nope.md)\n\n[outside](../../outside.md)\n',
        })
        issues = links.check(tree)
        self.assertEqual(
            [(issue.rule, issue.line) for issue in issues],
            [('link-resolves', 2), ('link-resolves', 4)],
        )
        self.assertIn('docs/nope.md, which does not exist', issues[0].message)
        self.assertIn('leaves the repository', issues[1].message)

    def test_anchor_slug_keeps_digits_and_drops_dots(self):
        self.assertEqual(
            links.heading_slugs('### 5.6 Rules and builtins\n'),
            {'56-rules-and-builtins'},
        )
        self.assertEqual(
            links.heading_slugs('## `index-current` and [the log](log.md) ##\n'),
            {'index-current-and-the-log'},
        )
        files = {
            'guide.md': '### 5.6 Rules and builtins\n',
            'README.md': (
                '[rules](guide.md#56-rules-and-builtins)\n'
                '[dotted](guide.md#5.6-rules-and-builtins)\n'
            ),
        }
        self.assertEqual(
            self.issues(files), [('anchor-names-a-heading', 'README.md', 2)])

    def test_duplicate_headings_get_numbered_slugs(self):
        self.assertEqual(
            links.heading_slugs('# Rules\n\n## Rules\n\n## Rules\n'),
            {'rules', 'rules-1', 'rules-2'},
        )

    def test_links_inside_fenced_code_at_any_indentation_are_not_read(self):
        text = (
            '- A list item holds an indented block:\n'
            '\n'
            '  ```md\n'
            '  [dead](in-indented-fence.md)\n'
            '  # Not a heading\n'
            '  ```\n'
            '\n'
            '~~~\n'
            '[dead](in-tilde-fence.md)\n'
            '~~~\n'
            '\n'
            '````\n'
            '```\n'
            '[dead](in-nested-fence.md)\n'
            '````\n'
            '\n'
            'Inline `[dead](in-inline-code.md)` and [live](b.md).\n'
        )
        self.assertEqual(
            [(reference.line, reference.written)
             for reference in links.markdown_references('a.md', text)],
            [(17, 'b.md')],
        )
        self.assertEqual(links.heading_slugs(text), frozenset())

    def test_a_footnote_definition_is_not_a_reference(self):
        text = 'A claim.[^demo-0730]\n\n[^demo-0730]: Reporting demo transcript\n'
        self.assertEqual(list(links.markdown_references('a.md', text)), [])

    def test_self_url_drops_trailing_sentence_punctuation(self):
        text = (
            f'See {links.SELF_URL}docs/install.md. Then read\n'
            f'{links.SELF_URL}docs/install.md#upgrade, which follows.\n'
        )
        self.assertEqual(
            [(reference.target, reference.fragment)
             for reference in links.self_url_references('a.md', text)],
            [('docs/install.md', None), ('docs/install.md', 'upgrade')],
        )

    def test_self_url_in_a_dart_string_is_checked(self):
        files = {
            'docs/install.md': '# Install\n\n## Upgrade\n',
            'lib/update.dart': (
                'final message =\n'
                f"    '({links.SELF_URL}docs/install.md), '\n"
                f"    '({links.SELF_URL}docs/gone.md), '\n"
                f"    '({links.SELF_URL}docs/install.md#upgrade) '\n"
                f"    '({links.SELF_URL}docs/install.md#downgrade)';\n"
            ),
        }
        self.assertEqual(self.issues(files), [
            ('self-url-resolves', 'lib/update.dart', 3),
            ('self-url-resolves', 'lib/update.dart', 5),
        ])

    def test_profile_rule_without_a_heading_is_an_issue(self):
        package = json.dumps({
            'docs': f'{links.SELF_URL}profile/README.md',
            'rules': [{'id': 'has-a-heading'}, {'id': 'has-no-heading'}],
        }, indent=2)
        files = {
            'profile/wayfinder-profile.json': package,
            'profile/README.md': '## Rules\n\n### has-a-heading\n',
        }
        issues = links.check(self.tree(files))
        self.assertEqual(
            [(issue.rule, issue.source) for issue in issues],
            [('rule-help-link-lands', 'profile/wayfinder-profile.json')],
        )
        self.assertIn('has-no-heading', issues[0].message)
        self.assertIn(
            'has-no-heading', package.splitlines()[issues[0].line - 1])

    def test_unchecked_sources_are_not_read_but_remain_valid_targets(self):
        fixture = 'packages/a/test/fixtures/bundle/note.md'
        files = {
            fixture: '[dead](nope.md)\n',
            'profiles/a/versions/old.md': '[dead](nope.md)\n',
            'README.md': f'[fixture]({fixture}#no-such-heading)\n',
        }
        self.assertEqual(self.issues(files), [])
        files['README.md'] = '[fixture](packages/a/test/fixtures/bundle/gone.md)\n'
        self.assertEqual(self.issues(files), [('link-resolves', 'README.md', 1)])

    def test_the_real_tree_has_no_issue(self):
        tree = links.read_tree(ROOT)
        self.assertIn('README.md', links.checked_sources(tree))
        self.assertEqual(links.check(tree), [])


if __name__ == '__main__':
    unittest.main()
