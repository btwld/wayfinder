#!/usr/bin/env python3
"""Require a package's exact workspace dependencies to be available on pub.dev."""
import argparse
from pathlib import Path
import sys

# publication.py sits beside this script and is not an installed package.
_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

from publication import missing_siblings, sibling_versions  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package')
    args = parser.parse_args()
    missing = missing_siblings(sibling_versions(args.package))
    if missing:
        parser.exit(
            1,
            'Unpublished or retracted siblings: '
            + ', '.join(missing)
            + '. Publish them first, then rerun the same immutable tag.\n',
        )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
