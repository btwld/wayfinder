#!/usr/bin/env bash
# Points the tap's okfp formula at the pub.dev archive of the released version.
# The formula builds from the public pub.dev source, so it never references
# this (private) repository; only the archive URL and its digest move.
set -euo pipefail

tag="${1:?release tag is required}"
version="${tag#v}"
tap_repo="${TAP_REPO:-btwld/homebrew-tap}"
formula="Formula/okfp.rb"
archive="https://pub.dev/api/archives/okf_profile-$version.tar.gz"

# pub.dev serves the archive shortly after publishing; give it a moment.
for attempt in 1 2 3 4 5 6; do
  if digest="$(curl --fail --silent --show-error --location "$archive" | sha256sum | cut -d' ' -f1)" \
    && [[ -n "$digest" ]]; then
    break
  fi
  [[ "$attempt" == 6 ]] && { echo "okfp: $archive is not available" >&2; exit 1; }
  sleep 10
done

root="$(git rev-parse --show-toplevel)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -c credential.helper='!gh auth git-credential' clone --quiet --depth 1 \
  "https://github.com/$tap_repo.git" \
  "$work/tap"
cd "$work/tap"
if [[ ! -f "$formula" ]]; then
  mkdir -p Formula
  cp "$root/tool/homebrew/okfp.rb" "$formula"
fi

sed -i -E \
  -e "s|^( *url )\"[^\"]+\"|\1\"$archive\"|" \
  -e "s|^( *version )\"[^\"]+\"|\1\"$version\"|" \
  -e "s|^( *sha256 )\"[^\"]+\"|\1\"$digest\"|" \
  "$formula"
grep -Fq "$archive" "$formula" && grep -Fq "$digest" "$formula" || {
  echo "okfp: could not rewrite url/sha256 in $formula" >&2
  exit 1
}

git add "$formula"
if git diff --cached --quiet; then
  echo "okfp: $formula already points at $version"
  exit 0
fi
git -c user.name="${GIT_AUTHOR_NAME:-wayfinder-release[bot]}" \
  -c user.email="${GIT_AUTHOR_EMAIL:-wayfinder-release[bot]@users.noreply.github.com}" \
  commit --quiet -am "Update okfp to $version"
git -c credential.helper='!gh auth git-credential' push --quiet origin HEAD
