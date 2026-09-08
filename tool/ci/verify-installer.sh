#!/usr/bin/env bash
# Asserts that an install directory holds both binaries at the versions
# install.sh pins, so the smoke job proves the published path end to end.
set -euo pipefail

install_dir="${1:?install directory is required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installer="$script_dir/../install.sh"

for tool in okf okfp; do
  pin="$(sed -n "s/^${tool^^}_VERSION=\"v\(.*\)\"$/\1/p" "$installer")"
  [[ -n "$pin" ]] || { echo "installer: no ${tool^^}_VERSION pin in install.sh" >&2; exit 1; }
  actual="$("$install_dir/$tool" --version)"
  [[ "$actual" == "$tool $pin" ]] || {
    echo "installer: $tool reports '$actual'; install.sh pins $pin" >&2
    exit 1
  }
done
echo "installer: okf and okfp match the pins"
