#!/bin/sh
# Install the complete Wayfinder runtime with built-in Profile validation.
# No Dart SDK, GitHub credentials or administrator privileges are required.
set -eu
fail() { printf 'wayfinder install: %s\n' "$*" >&2; exit 1; }
# The default is the latest verified native release. WAYFINDER_VERSION selects
# another published release; CI uses it to test a prepared version.
version="${WAYFINDER_VERSION:-0.0.2}"
case "$version" in
  *[!0-9A-Za-z.-]*) fail 'WAYFINDER_VERSION must be a published release version.' ;;
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) fail 'WAYFINDER_VERSION must be a published release version.' ;;
esac
release_root="https://github.com/conceptadev/wayfinder/releases/download/wayfinder-v$version"
skills="${WAYFINDER_SKILLS:-all}"
case "$skills" in
  all|claude|agents|none) ;;
  *) fail 'WAYFINDER_SKILLS must be all, claude, agents or none.' ;;
esac
install_dir="${WAYFINDER_INSTALL_DIR:-$HOME/.local/bin}"
runtime_root="${WAYFINDER_INSTALL_ROOT:-$HOME/.local/share/wayfinder-runtime}"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform=macos-arm64 ;;
  Linux-x86_64) platform=linux-x64 ;;
  *) fail 'This platform has no verified prebuilt bundle. See the installation guide.' ;;
esac
case "$install_dir:$runtime_root" in
  /*:/*) ;;
  *) fail 'Installation directories must be absolute paths.' ;;
esac
for command in curl tar mktemp; do
  command -v "$command" >/dev/null 2>&1 || fail "Required command is missing: $command"
done
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1
  else shasum -a 256 "$1" | cut -d ' ' -f 1; fi
}
verify_contents() {
  (cd "$1" && if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c SHA256SUMS >/dev/null
  else shasum -a 256 -c SHA256SUMS >/dev/null; fi)
}
mkdir -p "$runtime_root" "$install_dir"
# Refuse to replace a command managed by another installation method.
for name in wayfinder; do
  target="$install_dir/$name"
  if [ -e "$target" ] || [ -L "$target" ]; then
    [ -L "$target" ] || fail "$target already exists; choose another WAYFINDER_INSTALL_DIR."
    case "$(readlink "$target")" in
      "$runtime_root"/*) ;;
      *) fail "$target belongs to another installation; choose another WAYFINDER_INSTALL_DIR." ;;
    esac
  fi
done
stage="$(mktemp -d "$runtime_root/.install.XXXXXXXX")"
trap 'rm -rf "$stage"' EXIT HUP INT TERM
asset="wayfinder-$platform.tar.gz"
printf 'Downloading Wayfinder %s for %s...\n' "$version" "$platform"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$release_root/$asset" -o "$stage/$asset"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$release_root/$asset.sha256" -o "$stage/checksum"
expected="$(cut -d ' ' -f 1 "$stage/checksum")"
[ "${#expected}" -eq 64 ] || fail 'Invalid release checksum.'
[ "$(hash_file "$stage/$asset")" = "$expected" ] || fail 'Release checksum mismatch.'
mkdir "$stage/bundle"
tar -xzf "$stage/$asset" -C "$stage/bundle"
verify_contents "$stage/bundle" || fail 'Bundle contents failed verification.'
[ "$("$stage/bundle/bin/wayfinder" --version)" = "wayfinder $version" ] || fail 'Unexpected application version.'
# Each installation has its own directory. Switching commands preserves running
# processes, previous runtimes and user indexes. Reinstalling also repairs assets.
destination="$runtime_root/$version-$(basename "$stage")"
mv "$stage/bundle" "$destination"
for name in wayfinder; do
  ln -sfn "$destination/bin/$name" "$install_dir/$name"
done
# wayfinder update reinstalls into the same command directory.
printf '%s\n' "$install_dir" > "$runtime_root/install-dir.txt"
printf 'Installed Wayfinder %s in %s\n' "$version" "$install_dir"
# Agent skills ship with releases that bundle them. A skills failure never
# undoes the installed runtime.
if [ "$skills" != none ] && [ -d "$destination/skills" ]; then
  "$destination/bin/wayfinder" skills install --agent="$skills" ||
    printf 'wayfinder install: skills were not installed; run wayfinder skills install.\n' >&2
fi
case ":$PATH:" in
  *":$install_dir:"*) ;;
  *) printf 'Add %s to PATH, then open a new terminal.\n' "$install_dir" ;;
esac
