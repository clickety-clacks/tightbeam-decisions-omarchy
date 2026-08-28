#!/usr/bin/env bash
set -euo pipefail

host="${1:-gibson}"
user="${2:-mike}"
state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/omarchy-tightbeam-decisions"
seen_file="${state_dir}/seen-ids"
ssh_opts=(-F /dev/null -i "${HOME}/.ssh/id_ed25519" -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile="${HOME}/.ssh/known_hosts")

payload=$(ssh "${ssh_opts[@]}" "${user}@${host}" "/home/${user}/.local/bin/tightbeam decision-requests --status open --as-user ${user}")
seen='[]'
if [[ -r "$seen_file" ]]; then seen=$(jq -Rsc 'split("\n") | map(select(length > 0))' "$seen_file"); fi

jq -c --argjson seen "$seen" '
  [.decisionRequests[] |
    select(.kind != "effort") |
    . as $request |
    {
      id,
      kind,
      question,
      note: (.context.note // ""),
      assignmentId,
      raisedAt,
      raiserId,
      options: [(.options // [])[] | if type == "object" then .label else . end],
      isNew: (($seen | index($request.id)) == null)
    }
  ] | { requests: ., hasNew: any(.isNew), count: length }
' <<<"$payload"
