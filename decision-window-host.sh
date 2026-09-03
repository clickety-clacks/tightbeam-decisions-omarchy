#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_path="$plugin_dir/WindowHost.qml"
target=mike.tightbeam-decision-windows
unit=mike-tightbeam-decision-windows.service
action=${1:-ensure}
host=${2:-}
as_user=${3:-}
payload=${4:-}
log_dir=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-tightbeam-decisions

# Omarchy creates a panel with its default empty settings before injecting the
# saved bar-entry settings. Do not let that transient `ensure "" ""` switch a
# persistent remote host into local mode. Resolve omitted values from the
# installed widget entry; a genuinely local configuration has no saved host
# and therefore remains blank.
plugin_settings=$HOME/.config/omarchy/tightbeam-decisions.json
shell_settings=$HOME/.config/omarchy/shell.json
if [[ -r "$shell_settings" && ( -z "$host" || -z "$as_user" ) ]]; then
  saved_plugin='{}'
  if [[ -r "$plugin_settings" ]]; then
    saved_plugin=$(/usr/bin/jq -c '.' "$plugin_settings" 2>/dev/null || printf '{}')
  fi
  saved_widget=$(/usr/bin/jq -c '
    first(.. | objects | select(.id? == "mike.tightbeam-decisions")) // {}
  ' "$shell_settings" 2>/dev/null || printf '{}')
  if [[ -z "$host" ]]; then
    if [[ $(/usr/bin/jq -r '.topologyConfigured // false' <<<"$saved_plugin") == true ]]; then
      host=$(/usr/bin/jq -r '.host // ""' <<<"$saved_plugin")
      [[ -n "$host" ]] || host=local
    else
      saved_host=$(/usr/bin/jq -r '.host // empty' <<<"$saved_widget")
      host=${saved_host:-local}
    fi
  fi
  if [[ -z "$as_user" ]]; then
    saved_user=$(/usr/bin/jq -r '.asUser // empty' <<<"$saved_plugin")
    if [[ -z "$saved_user" ]]; then
      saved_user=$(/usr/bin/jq -r '.asUser // .user // empty' <<<"$saved_widget")
    fi
    [[ -n "$saved_user" ]] && as_user=$saved_user
  fi
fi

# Empty is a transient/uninitialized value at the IPC boundary. `local` is the
# explicit marker for a genuinely local topology; WindowHost normalizes it.
[[ -n "$host" ]] || host=local

mkdir -p -- "$log_dir"
exec 9>"$log_dir/window-host.lock"
flock 9

host_call() {
  qs ipc --any-display -p "$config_path" call "$target" "$@" >/dev/null 2>&1
}

if ! host_call ping; then
  systemctl --user stop "$unit" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  import_path="/usr/share/omarchy/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
  systemd-run --user --quiet --collect --unit="$unit" \
    --description="Tightbeam decision window host" \
    --property=Restart=on-failure \
    --property=RestartSec=1 \
    --property="StandardOutput=append:$log_dir/window-host.log" \
    --property="StandardError=append:$log_dir/window-host.log" \
    --setenv="QML_IMPORT_PATH=$import_path" \
    qs -p "$config_path"
  for _ in $(seq 1 50); do
    host_call ping && break
    sleep 0.1
  done
fi

case "$action" in
  ensure) host_call configure "$host" "$as_user" ;;
  open-json) host_call openJson "$payload" "$host" "$as_user" ;;
  open-id) host_call openId "$payload" "$host" "$as_user" ;;
  *) printf 'unknown action: %s\n' "$action" >&2; exit 2 ;;
esac
