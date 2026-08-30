---
name: show-decision-request
description: Show a Tightbeam decision-request window on this machine when an agent is asked to open, display, or surface a decision request and has its ID.
---

# Show a decision request

Open the requested ID with the machine-local standalone window host:

```sh
/home/mike/.config/omarchy/plugins/mike.tightbeam-decisions/decision-window-host.sh \
  open-id gibson mike '<decision-request-id>'
```

Replace only `<decision-request-id>` with the exact ID supplied by the user or
the current task. Pass it as one shell argument. Do not route through
`omarchy-shell` or require the bar menu to be open: the launcher starts the
independent Quickshell window host when necessary.

Run the command when showing the window is explicitly requested. A successful
command means the request was delivered to the host; if the ID is no longer an
open decision request, the host logs that fact and does not fabricate a window.

This is a graphical desktop action. Run it as `mike` in the active Wayland
desktop session. Do not use it from another machine or user session unless the
request explicitly targets this desktop.
