#!/usr/bin/env bash
set -euo pipefail

# Args: [host] [asUser]. A blank host means this machine is the Tightbeam node.
export TB_HOST="${1:-}"
export TB_AS_USER="${2:-}"
source "$(dirname "$(readlink -f "$0")")/tightbeam.sh"

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/omarchy-tightbeam-decisions"
seen_file="${state_dir}/seen-ids"

payload=$(tb decision-requests --status open)
# A decision request names no project -- only the assignment it came from does,
# via that assignment's subject and work item. Open assignments are ~200KB
# against ~8MB for every assignment ever, and an open request's assignment is
# open too, so this stays a cheap second call. A request whose assignment has
# since closed simply gets no subject rather than failing the fetch.
# Written to a file rather than passed with --argjson: the open set is ~200KB
# and handing that to jq through argv is fragile.
assignments_file=$(mktemp "${TMPDIR:-/tmp}/tb-assignments.XXXXXX")
trap 'rm -f "$assignments_file"' EXIT
tb assignments --state open >"$assignments_file" 2>/dev/null || echo '{"assignments":[]}' >"$assignments_file"
seen='[]'
if [[ -r "$seen_file" ]]; then seen=$(jq -Rsc 'split("\n") | map(select(length > 0))' "$seen_file"); fi

# Every kind is returned. Which kinds are shown is a UI toggle now, not a
# filter baked in here, so a newly-introduced kind cannot go invisible just
# because this script has never heard of it. `kinds` lists what the org is
# currently raising, so the panel can offer a toggle even for a kind that is
# switched off and therefore absent from `requests`.
jq -c --argjson seen "$seen" --slurpfile asg "$assignments_file" '
  (($asg[0].assignments // $asg[0]) // []) as $assignments
  | [.decisionRequests[] |
    . as $request |
    ($assignments | map(select(.id == $request.assignmentId)) | .[0]) as $assignment |
    {
      id,
      kind,
      question,
      subject: ($assignment.subject // ""),
      workItemId: ($assignment.workItemId // ""),
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
