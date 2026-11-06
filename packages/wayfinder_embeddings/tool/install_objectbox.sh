#!/usr/bin/env bash
set -euo pipefail

# Install the native library for the Dart objectbox release the workspace
# resolves: the root pubspec.yaml overrides objectbox to the release that
# tool/objectbox_assets/manifest.json pairs with this version (dartVersion),
# and test/objectbox_assets_test.dart fails when they differ. Verify the
# release archive before any of its bytes reach the package or a Wayfinder
# bundle. Downloading the pinned artifact directly, instead of running the
# upstream download.sh, is what makes that checksum possible; it also avoids
# the upstream unzip prompt when reinstalling on macOS.
#
# Every platform the upstream script can resolve is pinned here, so selection
# never silently falls back to another architecture. Refresh a checksum with
# `shasum -a 256 objectbox-<platform>.<extension>` on the matching asset.
version=6.0.0-beta2
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

checksum_for() {
  case "$1" in
    macos-universal) echo 130e702cbc006f1df481016f8550dff7d67334979d4685526d06b77d78e731bd ;;
    linux-x64) echo 58833743a8c3c5092fe930843aa259a0159bda4c1ce9a048e71a7d75a61cf5dc ;;
    linux-aarch64) echo 0be396a4b28eca8fb9701dd31a3d2a41ea4fe76079c9dfe447eee70aeaf4384c ;;
    linux-armv7hf) echo 11ab8d69a6276acbb4c04b34cbc41139fb324958baa377cfe078bc29816066c7 ;;
    linux-armv6hf) echo be30c91a7a1af770e30372e1093483f8bf819c5a807d9d734056f5c3810b01e6 ;;
    windows-x64) echo c26fae7232bc07c9e2e1f55a3d2ba831b3b631ed8baaafcae01e79e086a80670 ;;
    windows-x86) echo 9cb9c99be87f9a0274535cf5e01221617485d2d28c1049cf48d61e0eddf8c768 ;;
    windows-arm64) echo 5797eea3967df8018b5a47e3f6494228ea812b5c90894a86e84e2ba8e7776034 ;;
    *) return 1 ;;
  esac
}

unsupported() {
  printf 'ObjectBox %s has no pinned checksum for %s/%s.\n' \
    "$version" "$(uname -s)" "$(uname -m)" >&2
  exit 1
}

# Upstream's architecture spellings, so a pinned platform always matches the
# machine the library has to load on.
case "$(uname -m)" in
  x86_64 | amd64) machine=x64 ;;
  i386 | i686) machine=x86 ;;
  aarch64 | arm64 | ARM64) machine=arm64 ;;
  armv7*) machine=armv7hf ;;
  armv6*) machine=armv6hf ;;
  *) machine=unknown ;;
esac

case "$(uname -s)" in
  Darwin)
    # The macOS asset is a universal binary; architecture does not select it.
    platform=macos-universal
    extension=zip
    library=libobjectbox.dylib
    ;;
  Linux)
    # Upstream spells 64-bit ARM as aarch64 on Linux and arm64 on Windows.
    if [[ "$machine" == arm64 ]]; then machine=aarch64; fi
    platform="linux-$machine"
    extension=tar.gz
    library=libobjectbox.so
    ;;
  MINGW* | MSYS* | CYGWIN*)
    platform="windows-$machine"
    extension=zip
    library=objectbox.dll
    ;;
  *) unsupported ;;
esac
checksum="$(checksum_for "$platform")" || unsupported

install_dir="$(mktemp -d)"
trap 'rm -rf "$install_dir"' EXIT
archive="$install_dir/objectbox.$extension"

curl --fail --location --silent --show-error \
  "https://github.com/objectbox/objectbox-c/releases/download/v$version/objectbox-$platform.$extension" \
  --output "$archive"

if command -v shasum >/dev/null 2>&1; then
  downloaded="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
elif command -v sha256sum >/dev/null 2>&1; then
  downloaded="$(sha256sum "$archive" | cut -d ' ' -f 1)"
else
  echo 'Neither shasum nor sha256sum is available to verify the download.' >&2
  exit 1
fi
if [[ "$downloaded" != "$checksum" ]]; then
  printf 'ObjectBox %s SHA-256 mismatch for %s: expected %s, got %s.\n' \
    "$version" "$platform" "$checksum" "$downloaded" >&2
  exit 1
fi

# Only verified bytes are extracted.
mkdir -p "$install_dir/archive"
if [[ "$extension" == zip ]]; then
  unzip -q "$archive" -d "$install_dir/archive"
else
  tar -xzf "$archive" -C "$install_dir/archive"
fi
if [[ ! -f "$install_dir/archive/lib/$library" ]]; then
  printf 'The ObjectBox %s archive for %s did not contain lib/%s.\n' \
    "$version" "$platform" "$library" >&2
  exit 1
fi

mkdir -p "$package_dir/lib"
cp "$install_dir/archive/lib/$library" "$package_dir/lib/$library"
printf 'Installed verified ObjectBox %s for %s: %s/lib/%s\n' \
  "$version" "$platform" "$package_dir" "$library"
