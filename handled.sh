#!/usr/bin/env bash
set -euo pipefail

export TB_HOST="${1:-}"
export TB_AS_USER="${2:-}"
request_id="${3:?request id required}"
source "$(dirname "$(readlink -f "$0")")/tightbeam.sh"

payload=$(tb decision-requests --status all)
jq -ce --arg id "$request_id" '
  [.decisionRequests[] | select(.id == $id)][0] as $request
  | if $request == null then
      { status: "handled", actor: "", determination: "The request is no longer open." }
    elif $request.status == "ruled" then
      {
        status: "ruled",
        actor: ($request.ruledBy // $request.raiserId // ""),
        determination: (if (($request.decision // "") != "") then $request.decision
          elif (($request.response // "") != "") then $request.response
          elif (($request.rationale // "") != "") then $request.rationale
          else "A ruling was recorded." end)
      }
    elif $request.status == "withdrawn" then
      {
        status: "withdrawn",
        actor: ($request.raiserId // ""),
        determination: (($request.withdrawnReason // "") | if . == "" then "The raising agent withdrew the request." else . end)
      }
    elif $request.status == "superseded" then
      {
        status: "superseded",
        actor: ($request.raiserId // ""),
        determination: "The request was replaced by a newer determination."
      }
    elif $request.status == "consumed" then
      {
        status: "consumed",
        actor: ($request.raiserId // ""),
        determination: "The recorded ruling was consumed and work continued."
      }
    else
      { status: ($request.status // "handled"), actor: ($request.raiserId // ""), determination: "The request is no longer open." }
    end
' <<<"$payload"
