#!/usr/bin/env bash
# The installers are the one place okf and okfp versions are pinned together.
# This keeps install.sh and install.ps1 equal, and keeps the okf pin equal to
# the okf that okfp itself embeds, so a teammate never runs an okf that
# disagrees with the okfp gate (docs/releasing.md).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
sh_pin() { sed -n "s/^$1_VERSION=\"v\(.*\)\"$/\1/p" "$repo_root/tool/install.sh"; }
ps_pin() { sed -n "s/^\$$1Version = 'v\(.*\)'$/\1/p" "$repo_root/tool/install.ps1"; }

status=0
for pair in "OKF Okf" "OKFP Okfp"; do
  set -- $pair
  sh="$(sh_pin "$1")"
  ps="$(ps_pin "$2")"
  if [[ -z "$sh" || "$sh" != "$ps" ]]; then
    echo "pins: install.sh pins $1 '$sh' but install.ps1 pins '$ps'" >&2
    status=1
  fi
done

okfp_pin="$(sh_pin OKFP)"
package_version="$(sed -n 's/^version: //p' "$repo_root/packages/okf_profile/pubspec.yaml")"
if [[ "$okfp_pin" != "$package_version" ]]; then
  # Expected between a version bump and its installer-pin follow-up; the
  # checklist orders them, and this line says which side is behind.
  echo "pins: install.sh pins okfp $okfp_pin; packages/okf_profile is $package_version (bump the installer after the release is published)"
fi

if command -v dart >/dev/null 2>&1; then
  embedded="$(cd "$repo_root/packages/okf_profile" && dart pub deps --json \
    | tr -d '\n' | sed -n 's/.*"name": *"okf",[^}]*"version": *"\([^"]*\)".*/\1/p')"
  okf_pin="$(sh_pin OKF)"
  if [[ -z "$embedded" ]]; then
    echo "pins: could not read the embedded okf version from dart pub deps" >&2
    status=1
  elif [[ "$embedded" != "$okf_pin" ]]; then
    echo "pins: install.sh pins okf $okf_pin but okfp embeds okf $embedded" >&2
    status=1
  fi
fi

[[ "$status" == 0 ]] && echo "pins: install.sh and install.ps1 agree"
exit "$status"
