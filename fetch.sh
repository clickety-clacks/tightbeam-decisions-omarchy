#!/usr/bin/env bash
set -euo pipefail

# Args: [host] [asUser]. A blank host means this machine is the Tightbeam node.
export TB_HOST="${1:-}"
export TB_AS_USER="${2:-}"
source "$(dirname "$(readlink -f "$0")")/tightbeam.sh"

state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/omarchy-tightbeam-decisions"
seen_file="${state_dir}/seen-ids"

payload=$(tb decision-requests --status open)
# Assignment subjects supplement the question; product attribution comes only
# from the request. Keep the open-assignment payload out of argv.
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
      project: (.project // null),
      projectAttribution: (.projectAttribution // "unresolved"),
      projectUnresolvedReason: (.projectUnresolvedReason // "No product was recorded for this request."),
      associationStatus: (.associationStatus // "none"),
      workItemId: (.workItemId // $assignment.workItemId // ""),
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
