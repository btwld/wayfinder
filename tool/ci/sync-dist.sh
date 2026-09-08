#!/usr/bin/env bash
# Projects one release's public surface into the distribution repository:
# the plugin (skills + manifests), the installers, and the okfp binaries as
# that repository's release assets. The distribution repository is a pure
# projection — nothing there is hand-edited, and this script is the only
# writer — so collapsing back to a single public repository later means
# deleting this step and re-pointing the installer's release host.
set -euo pipefail

tag="${1:?release tag is required}"
distribution="${2:?distribution directory with the release assets is required}"
dist_repo="${DIST_REPO:-conceptadev/okf-profile-dist}"
source_repo="${GH_REPO:?GH_REPO (the source repository) is required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone --quiet --depth 1 \
  "https://x-access-token:${GH_TOKEN:?GH_TOKEN is required}@github.com/$dist_repo.git" \
  "$work/dist" 2>/dev/null || git init --quiet -b main "$work/dist"
cd "$work/dist"
git checkout --quiet -B main

# The projection is replaced wholesale so removals in the source propagate.
rm -rf skills .claude-plugin tool docs LICENSE README.md
mkdir -p tool docs
cp -R "$repo_root/skills" skills
cp -R "$repo_root/.claude-plugin" .claude-plugin
cp "$repo_root/tool/install.sh" "$repo_root/tool/install.ps1" tool/
cp "$repo_root/docs/install.md" docs/install.md
cp "$repo_root/LICENSE" LICENSE
sed -e "s|{{TAG}}|$tag|g" -e "s|{{SOURCE_REPO}}|$source_repo|g" \
  "$repo_root/tool/dist/README.md" > README.md

git add -A
if git diff --cached --quiet; then
  echo "okfp: distribution projection already matches $tag"
else
  git -c user.name="${GIT_AUTHOR_NAME:-okf-profile-release[bot]}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-okf-profile-release[bot]@users.noreply.github.com}" \
    commit --quiet -m "Sync $source_repo $tag"
  git push --quiet \
    "https://x-access-token:$GH_TOKEN@github.com/$dist_repo.git" main
fi

if gh release view "$tag" --repo "$dist_repo" --json isDraft >/dev/null 2>&1; then
  release_assets="$(gh release view "$tag" --repo "$dist_repo" --json assets \
    --jq '.assets[].name')"
  for path in "${assets[@]}"; do
    grep -Fxq "${path##*/}" <<< "$release_assets" || {
      echo "okfp: distribution release $tag exists but lacks ${path##*/};" \
        "immutable releases cannot be amended" >&2
      exit 1
    }
  done
  echo "okfp: distribution release $tag is already complete"
  exit 0
fi

gh release create "$tag" "${assets[@]}" --repo "$dist_repo" --target main \
  --title "$tag" \
  --notes "okfp binaries and plugin projection for $source_repo $tag. Release notes live at https://github.com/$source_repo/releases/tag/$tag."
