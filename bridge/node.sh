#!/usr/bin/env bash
# Runs node for the window host. The host is a long-lived user service whose
# environment is whatever the systemd user manager had when it started; on a
# fresh session that can be before the desktop exported the user's PATH
# (Scottland, 2026-09-29), leaving node, codex and claude unfindable for the
# host's whole life. Read the manager's current PATH at each launch instead.
manager_path=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^PATH=//p')
export PATH="${manager_path:+$manager_path:}${PATH:-/usr/local/bin:/usr/bin}:$HOME/.local/bin"
exec node "$@"
