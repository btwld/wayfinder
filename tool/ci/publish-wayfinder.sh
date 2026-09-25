#!/usr/bin/env bash
# Called after complete-archive and CI provenance checks with GITHUB_TOKEN. Credentials stay in GH_TOKEN, never in Git remote URLs.
set -euo pipefail
assets="$(cd "${1:?release artifact directory is required}" && pwd)"
root="$(git rev-parse --show-toplevel)"
version="$(sed -n 's/^version: //p' "$root/packages/wayfinder_cli/pubspec.yaml")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || exit 1
tag="wayfinder-v$version"
repo="btwld/wayfinder"
source_sha="$(git rev-parse HEAD)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
python3 "$root/tool/ci/verify-distribution.py" "$assets"
python3 - "$assets/source.json" "$source_sha" "$version" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
    'repository': 'btwld/wayfinder', 'commit': sys.argv[2],
    'applicationVersion': sys.argv[3],
}, indent=2) + '\n')
PY
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release download "$tag" --repo "$repo" --dir "$work/existing"
  for file in "$assets"/*.tar.gz "$assets"/*.sha256 "$assets/source.json"; do
    cmp "$file" "$work/existing/${file##*/}" || {
      echo "Existing release differs: ${file##*/}. Publish a new version." >&2
      exit 1
    }
  done
  echo "Public release $tag already contains these exact assets."
  exit 0
fi
cat > "$work/notes.md" <<EOF
Complete Wayfinder $version native bundles, including built-in Profile validation,
embedding model and required native libraries. Verify the accompanying SHA-256
checksums before installation. Platform verification and source provenance are
recorded by the source CI; source commit: $source_sha.

See the installation guide in this repository for plugin setup and upgrades.
EOF
release_flags=()
if [[ "$version" == *-* ]]; then release_flags+=(--prerelease); fi
# Require the pre-existing application tag; its push owns pub.dev publication.
actual_sha="$(git rev-list -n 1 "$tag")"
[[ "$actual_sha" == "$source_sha" ]] || { echo 'Release tag must match the checked commit.' >&2; exit 1; }
gh release create "$tag" --repo "$repo" --verify-tag "${release_flags[@]}" \
  --title "Wayfinder $version" --notes-file "$work/notes.md" \
  "$assets"/*.tar.gz "$assets"/*.sha256 "$assets/source.json"
