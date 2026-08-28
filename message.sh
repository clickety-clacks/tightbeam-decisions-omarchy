#!/usr/bin/env bash
set -euo pipefail

export TB_HOST="${1:-}"
export TB_AS_USER="${2:-}"
request_id="${3:?request id required}"
message="${4:?message required}"
source "$(dirname "$(readlink -f "$0")")/tightbeam.sh"

[[ -n "${message//[[:space:]]/}" ]] || { echo "Type a message first" >&2; exit 2; }
payload=$(tb decision-requests --status open)
raiser=$(jq -er --arg id "$request_id" '.decisionRequests[] | select(.id == $id) | .raiserId' <<<"$payload")
[[ "$raiser" == agent:* ]] || { echo "This request was raised by automation, not an addressable agent" >&2; exit 2; }
role=${raiser#agent:}

tb wake --role "$role" --prompt "Regarding decision request ${request_id}: ${message}" >/dev/null
printf 'Message sent to %s\n' "$role"
