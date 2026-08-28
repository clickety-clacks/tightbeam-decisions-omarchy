#!/usr/bin/env bash
set -euo pipefail

host="${1:?host required}"
user="${2:?user required}"
request_id="${3:?request id required}"
message="${4:?message required}"
ssh_opts=(-F /dev/null -i "${HOME}/.ssh/id_ed25519" -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile="${HOME}/.ssh/known_hosts")
remote_cli="/home/${user}/.local/bin/tightbeam"

[[ -n "${message//[[:space:]]/}" ]] || { echo "Type a message first" >&2; exit 2; }
payload=$(ssh "${ssh_opts[@]}" "${user}@${host}" "$remote_cli decision-requests --status open --as-user $(printf %q "$user")")
raiser=$(jq -er --arg id "$request_id" '.decisionRequests[] | select(.id == $id) | .raiserId' <<<"$payload")
[[ "$raiser" == agent:* ]] || { echo "This request was raised by automation, not an addressable agent" >&2; exit 2; }
role=${raiser#agent:}
prompt="Regarding decision request ${request_id}: ${message}"

ssh "${ssh_opts[@]}" "${user}@${host}" "$remote_cli wake --role $(printf %q "$role") --prompt $(printf %q "$prompt") --as-user $(printf %q "$user")" >/dev/null
printf 'Message sent to %s\n' "$role"
