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
