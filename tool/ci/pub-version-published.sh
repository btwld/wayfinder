#!/usr/bin/env bash
# Emit published=true/false for GitHub Actions. A missing package is unpublished.
set -euo pipefail
package="${1:?package name is required}"
version="${2:?package version is required}"
[[ "$package" =~ ^[a-z][a-z0-9_]*$ ]] || {
  echo "Invalid package name: $package" >&2
  exit 1
}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || {
  echo "Invalid package version: $version" >&2
  exit 1
}
work="$(mktemp)"
trap 'rm -f "$work"' EXIT
code="$(curl --silent --show-error --output "$work" --write-out '%{http_code}' \
  "https://pub.dev/api/packages/$package")"
if [[ "$code" == 404 ]]; then
  echo "published=false"
  exit 0
fi
if [[ "$code" != 200 ]]; then
  echo "Unexpected pub.dev response for $package: $code" >&2
  exit 1
fi
if jq -e --arg version "$version" '.versions | any(.version == $version)' "$work" >/dev/null; then
  echo "published=true"
else
  echo "published=false"
fi
