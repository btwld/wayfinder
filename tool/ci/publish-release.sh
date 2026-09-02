#!/usr/bin/env bash
set -euo pipefail

tag="${1:?release tag is required}"
distribution="${2:?distribution directory is required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets=()

while IFS=$'\t' read -r runner_os _ _ asset; do
  [[ "$runner_os" == \#* ]] && continue
  path="$distribution/$asset"
  [[ -f "$path" ]] || {
    echo "okfp: missing release asset $path" >&2
    exit 1
  }
  assets+=("$path")
done < "$script_dir/platforms.tsv"

if draft_state="$(gh release view "$tag" --json isDraft --jq .isDraft 2>/dev/null)"; then
  if [[ "$draft_state" != true ]]; then
    if [[ "$(gh api "repos/$GH_REPO/releases/tags/$tag" --jq .immutable)" \
      != true ]]; then
      echo "okfp: existing release $tag is not immutable" >&2
      exit 1
    fi
    release_assets="$(gh release view "$tag" --json assets \
      --jq '.assets[].name')"
    for path in "${assets[@]}"; do
      asset="${path##*/}"
      grep -Fxq "$asset" <<< "$release_assets" || {
        echo "okfp: existing release $tag is missing $asset" >&2
        exit 1
      }
    done
    echo "okfp: immutable release $tag is already complete"
    exit 0
  fi
  gh release upload "$tag" "${assets[@]}" --clobber
else
  gh release create "$tag" "${assets[@]}" \
    --verify-tag --generate-notes --draft
fi
gh release edit "$tag" --draft=false

if [[ "$(gh api "repos/$GH_REPO/releases/tags/$tag" --jq .immutable)" != true ]]; then
  echo "okfp: release $tag was published mutable; enable immutable releases" \
    "for $GH_REPO before publishing another version" >&2
  exit 1
fi
