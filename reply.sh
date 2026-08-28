#!/usr/bin/env bash
set -euo pipefail

host="${1:?host required}"
user="${2:?user required}"
request_id="${3:?request id required}"
choice_number="${4:?choice number required}"
ssh_opts=(-F /dev/null -i "${HOME}/.ssh/id_ed25519" -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile="${HOME}/.ssh/known_hosts")

payload=$(ssh "${ssh_opts[@]}" "${user}@${host}" "/home/${user}/.local/bin/tightbeam decision-requests --status open --as-user ${user}")
request=$(jq -ce --arg id "$request_id" '.decisionRequests[] | select(.id == $id)' <<<"$payload")
kind=$(jq -r '.kind' <<<"$request")

if [[ "$kind" == "effort" ]]; then
  options='["continue","dismiss"]'
else
  options=$(jq -c '[.options[] | if type == "object" then .label else . end]' <<<"$request")
fi

if ! [[ "$choice_number" =~ ^[0-9]+$ ]]; then echo "Type an option number" >&2; exit 2; fi
index=$((choice_number - 1))
choice=$(jq -er --argjson i "$index" '.[$i]' <<<"$options") || { echo "No such option" >&2; exit 2; }
remote_cli="/home/${user}/.local/bin/tightbeam"

if [[ "$kind" == "effort" ]]; then
  ssh "${ssh_opts[@]}" "${user}@${host}" "$remote_cli effort-rule --request $(printf %q "$request_id") --action $(printf %q "$choice") --as-user $(printf %q "$user")"
else
  ssh "${ssh_opts[@]}" "${user}@${host}" "$remote_cli operator-rule $(printf %q "$request_id") --decision $(printf %q "$choice") --as-user $(printf %q "$user")"
  raiser=$(jq -r '.raiserId // ""' <<<"$request")
  if [[ "$raiser" == agent:* ]]; then
    role=${raiser#agent:}
    prompt="Decision ${request_id} was ruled: ${choice}. Re-read durable state and proceed accordingly."
    ssh "${ssh_opts[@]}" "${user}@${host}" "$remote_cli wake --role $(printf %q "$role") --prompt $(printf %q "$prompt") --as-user $(printf %q "$user")" >/dev/null
  fi
fi

printf 'Recorded: %s\n' "$choice"
