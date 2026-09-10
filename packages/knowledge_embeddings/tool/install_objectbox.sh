#!/usr/bin/env bash
set -euo pipefail

# Keep the tested Dart 5.0.4 / native 5.3.2 pair reproducible, and verify the
# release archive before any of its bytes reach the package or a Station
# bundle. Downloading the pinned artifact directly, instead of running the
# upstream download.sh, is what makes that checksum possible; it also avoids
# the upstream unzip prompt when reinstalling on macOS.
#
# Refresh a checksum with `shasum -a 256 objectbox-<platform>.<extension>` on
# the matching release asset.
version=5.3.2
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

unsupported() {
  printf 'ObjectBox %s has no pinned checksum for %s/%s.\n' \
    "$version" "$(uname -s)" "$(uname -m)" >&2
  exit 1
}

case "$(uname -s)" in
  Darwin)
    platform=macos-universal
    extension=zip
    library=libobjectbox.dylib
    checksum=680c598573ede04b9762565d48d4e161ad286f786f159abb8da89353bfa1d0bc
    ;;
  Linux)
    extension=tar.gz
    library=libobjectbox.so
    case "$(uname -m)" in
      x86_64)
        platform=linux-x64
        checksum=6dbb5450c36dd11ee9074f16ecc61e79b45ff43c2082934601f3166b39c8a613
        ;;
      aarch64 | arm64)
        platform=linux-aarch64
        checksum=bdfbfbf4971057e11018ca6645697d8a40ebc7df56ccde63397cbb0e0609c0e8
        ;;
      *) unsupported ;;
    esac
    ;;
  MINGW* | MSYS* | CYGWIN*)
    platform=windows-x64
    extension=zip
    library=objectbox.dll
    checksum=57d7db013bbb46efe415307c9f3baf7564bdc40818ee1f1c42046f4241403d63
    ;;
  *) unsupported ;;
esac

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
printf 'Installed verified ObjectBox %s: %s/lib/%s\n' \
  "$version" "$package_dir" "$library"
