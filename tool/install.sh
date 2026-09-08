#!/bin/sh
# Installs the okf and okfp binaries for the Concepta OKF Profile.
#
#   curl -fsSL https://raw.githubusercontent.com/conceptadev/okf-profile-dist/main/tool/install.sh | sh
#
# No Dart SDK, no gh, no sudo. Binaries land in ~/.local/bin (override with
# OKF_INSTALL_DIR). Versions are pinned below, together with install.ps1, and
# CI keeps the two in step (docs/releasing.md): re-running after a pin bump
# upgrades, re-running with matching pins is a no-op. Homebrew users can skip
# this script: brew install conceptadev/tap/okf conceptadev/tap/okfp
set -eu

OKF_VERSION="v0.3.0"
OKFP_VERSION="v0.2.0"
OKF_RELEASES="conceptadev/okf"
OKFP_RELEASES="conceptadev/okf-profile-dist"

install_dir="${OKF_INSTALL_DIR:-$HOME/.local/bin}"

fail() {
  printf 'install: %s\n' "$*" >&2
  exit 1
}

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  *) fail "unsupported operating system $(uname -s); on Windows run install.ps1" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=x64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) fail "unsupported architecture $(uname -m)" ;;
esac
platform="$os-$arch"
case "$platform" in
  linux-x64 | macos-arm64) ;;
  *) fail "no prebuilt binaries for $platform; use Homebrew instead:
  brew install conceptadev/tap/okf conceptadev/tap/okfp" ;;
esac

# Attestations are verified when a signed-in gh is around; the download itself
# never needs it.
verify=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  verify=1
fi

install_one() {
  name="$1"
  version="$2"
  repo="$3"
  asset="$name-$platform"
  target="$install_dir/$name"
  expected="$name ${version#v}"

  if [ -x "$target" ] && [ "$("$target" --version 2>/dev/null || true)" = "$expected" ]; then
    printf 'install: %s is already %s, nothing to do\n' "$name" "${version#v}"
    return 0
  fi

  tmp="$(mktemp)"
  printf 'install: downloading %s %s for %s\n' "$name" "${version#v}" "$platform"
  curl -fsSL --retry 3 -o "$tmp" \
    "https://github.com/$repo/releases/download/$version/$asset" ||
    fail "could not download $asset from the $repo $version release"
  if [ "$verify" = 1 ]; then
    gh release verify-asset "$version" "$tmp" --repo "$repo" >/dev/null ||
      fail "$asset did not verify against the $repo $version release"
  fi
  chmod +x "$tmp"
  mkdir -p "$install_dir"
  mv "$tmp" "$target"
  printf 'install: %s -> %s\n' "$("$target" --version)" "$target"
}

install_one okf "$OKF_VERSION" "$OKF_RELEASES"
install_one okfp "$OKFP_VERSION" "$OKFP_RELEASES"

if [ "$verify" = 0 ]; then
  printf 'install: release attestations were not verified (no signed-in gh); that is fine for everyday use\n'
fi
case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    printf '\ninstall: %s is not on your PATH. Add this line to your shell profile (~/.zshrc or ~/.bashrc) and open a new terminal:\n' "$install_dir"
    printf '  export PATH="%s:$PATH"\n' "$install_dir"
    ;;
esac
