#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/omarchy-tightbeam-decisions"
seen_file="${state_dir}/seen-ids"
request_ids=("$@")

mkdir -p "$state_dir"
temporary_file=$(mktemp "${state_dir}/seen-ids.tmp.XXXXXX")
trap 'rm -f "$temporary_file"' EXIT

{
  [[ ! -r "$seen_file" ]] || cat "$seen_file"
  printf '%s\n' "${request_ids[@]}"
} | awk 'NF && !seen[$0]++' >"$temporary_file"

chmod 600 "$temporary_file"
mv -f -- "$temporary_file" "$seen_file"
trap - EXIT
