#!/usr/bin/env bash
set -euo pipefail

export TB_HOST="${1:-}"
export TB_AS_USER="${2:-}"
request_id="${3:?request id required}"
choice_label="${4:?choice label required}"
source "$(dirname "$(readlink -f "$0")")/tightbeam.sh"

payload=$(tb decision-requests --status open)
request=$(jq -ce --arg id "$request_id" '.decisionRequests[] | select(.id == $id)' <<<"$payload")
kind=$(jq -r '.kind' <<<"$request")

if [[ "$kind" == "effort" ]]; then
  options='["continue","dismiss"]'
else
  options=$(jq -c '[.options[] | if type == "object" then .label else . end]' <<<"$request")
fi

choice=$(jq -er --arg wanted "$choice_label" '.[] | select(. == $wanted)' <<<"$options") \
  || { echo "No such recordable option: $choice_label" >&2; exit 2; }

if [[ "$kind" == "effort" ]]; then
  tb effort-rule --request "$request_id" --action "$choice"
else
  tb operator-rule "$request_id" --decision "$choice"
  raiser=$(jq -r '.raiserId // ""' <<<"$request")
  if [[ "$raiser" == agent:* ]]; then
    tb wake --role "${raiser#agent:}" \
      --prompt "Decision ${request_id} was ruled: ${choice}. Re-read durable state and proceed accordingly." >/dev/null
  fi
fi

printf 'Recorded: %s\n' "$choice"
