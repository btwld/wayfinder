#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
separator=''
printf '{"include":['
while IFS=$'\t' read -r runner_os _ workflow_runner asset; do
  [[ "$runner_os" == \#* ]] && continue
  printf '%s{"os":"%s","asset":"%s"}' "$separator" "$workflow_runner" "$asset"
  separator=,
done < "$script_dir/platforms.tsv"
printf ']}\n'
