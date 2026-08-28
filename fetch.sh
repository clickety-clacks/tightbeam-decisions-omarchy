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

# Every kind is returned. Which kinds are shown is a UI toggle now, not a
# filter baked in here, so a newly-introduced kind cannot go invisible just
# because this script has never heard of it. `kinds` lists what the org is
# currently raising, so the panel can offer a toggle even for a kind that is
# switched off and therefore absent from `requests`.
jq -c --argjson seen "$seen" '
  [.decisionRequests[] |
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
  ] as $all
  | {
      requests: $all,
      kinds: ($all | map(.kind) | unique),
      count: ($all | length)
    }
' <<<"$payload"
