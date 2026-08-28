#!/usr/bin/env bash
set -euo pipefail

# Args: [host] [asUser]. A blank host means this machine is the Tightbeam node.
export TB_HOST="${1:-}"
export TB_AS_USER="${2:-}"
source "$(dirname "$(readlink -f "$0")")/tightbeam.sh"

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/omarchy-tightbeam-decisions"
seen_file="${state_dir}/seen-ids"

payload=$(tb decision-requests --status open)
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
