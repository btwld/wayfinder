#!/usr/bin/env bash
set -euo pipefail

# Keep the tested Dart 5.0.4 / native 5.3.2 pair reproducible, and verify the
# release archive before any of its bytes reach the package or a Station
# bundle. Downloading the pinned artifact directly, instead of running the
# upstream download.sh, is what makes that checksum possible; it also avoids
# the upstream unzip prompt when reinstalling on macOS.
#
# Every platform the upstream script can resolve is pinned here, so selection
# never silently falls back to another architecture. Refresh a checksum with
# `shasum -a 256 objectbox-<platform>.<extension>` on the matching asset.
version=5.3.2
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

checksum_for() {
  case "$1" in
    macos-universal) echo 680c598573ede04b9762565d48d4e161ad286f786f159abb8da89353bfa1d0bc ;;
    linux-x64) echo 6dbb5450c36dd11ee9074f16ecc61e79b45ff43c2082934601f3166b39c8a613 ;;
    linux-aarch64) echo bdfbfbf4971057e11018ca6645697d8a40ebc7df56ccde63397cbb0e0609c0e8 ;;
    linux-armv7hf) echo 9e7e4ed9df601cad54950a829f57dd77f297dffb0d0e3b9758bbe2fb01fd0064 ;;
    linux-armv6hf) echo b641a2b36094b442a58ada5e9cbe100568ec4108e484c30a0bce87347aec679c ;;
    windows-x64) echo 57d7db013bbb46efe415307c9f3baf7564bdc40818ee1f1c42046f4241403d63 ;;
    windows-x86) echo 1e64c03f4ce7a616b426874444cf3fa61853d919e64517b845bb8117f1b6382b ;;
    windows-arm64) echo e32ea12aebd76f00bcf9def941a3c73b24d2cc2dcd0e79a033b49522a2b2c0fd ;;
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
