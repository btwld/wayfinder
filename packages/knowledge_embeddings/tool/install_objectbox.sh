#!/usr/bin/env bash
set -euo pipefail

# Keep the tested Dart 5.0.4 / native 5.3.2 pair reproducible. A fresh temporary
# directory also avoids the upstream unzip prompt when reinstalling on macOS.
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_dir="$(mktemp -d)"
trap 'rm -rf "$install_dir"' EXIT

curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/objectbox/objectbox-c/v5.3.2/download.sh \
  --output "$install_dir/download.sh"
(
  cd "$install_dir"
  bash download.sh --quiet 5.3.2
)

mkdir -p "$package_dir/lib"
for library in libobjectbox.dylib libobjectbox.so objectbox.dll; do
  if [[ -f "$install_dir/lib/$library" ]]; then
    cp "$install_dir/lib/$library" "$package_dir/lib/$library"
    printf 'Installed ObjectBox 5.3.2: %s/lib/%s\n' "$package_dir" "$library"
    exit 0
  fi
done
echo 'The ObjectBox download did not contain a supported shared library.' >&2
exit 1
