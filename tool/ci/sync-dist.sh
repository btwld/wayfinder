#!/usr/bin/env bash
# Preserve the independent okfp release channel in the public distribution repo.
# Plugin/runtime projection is released separately by publish-wayfinder-dist.sh.
set -euo pipefail
tag="${1:?validator release tag is required}"
assets="$(cd "${2:?release artifact directory is required}" && pwd)"
repo="${DIST_REPO:-conceptadev/wayfinder-dist}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
files=()
while IFS=$'\t' read -r runner_os _ _ asset; do
  [[ "$runner_os" == \#* ]] && continue
  [[ -f "$assets/$asset" ]] || { echo "Missing validator asset: $asset" >&2; exit 1; }
  files+=("$assets/$asset")
done < "$script_dir/platforms.tsv"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release download "$tag" --repo "$repo" --dir "$work/existing"
  for file in "${files[@]}"; do
    cmp "$file" "$work/existing/${file##*/}" || {
      echo "Published validator asset differs; publish a new version." >&2; exit 1;
    }
  done
  exit 0
fi
cat > "$work/notes.md" <<EOF
Standalone okfp Profile validator binaries for $tag.
This does not update the Wayfinder runtime or plugin release.
EOF
gh release create "$tag" "${files[@]}" --repo "$repo" --target main \
  --title "okfp ${tag#v}" --notes-file "$work/notes.md"
