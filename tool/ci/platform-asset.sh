#!/usr/bin/env bash
set -euo pipefail

runner_os="${1:?runner OS is required}"
runner_arch="${2:?runner architecture is required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while IFS=$'\t' read -r candidate_os candidate_arch _ asset; do
  [[ "$candidate_os" == \#* ]] && continue
  if [[ "$candidate_os" == "$runner_os" && "$candidate_arch" == "$runner_arch" ]]; then
    printf '%s\n' "$asset"
    exit 0
  fi
done < "$script_dir/platforms.tsv"

echo "okfp: no released binary for $runner_os $runner_arch" >&2
exit 1
