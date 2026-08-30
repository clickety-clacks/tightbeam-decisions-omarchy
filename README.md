# Tightbeam Decisions

An [Omarchy](https://omarchy.org/) bar widget for open [Tightbeam](https://github.com/clickety-clacks/tightbeam)
decision requests. It lists what is waiting on you, explains a request in
plain terms, and records a ruling — without opening a terminal.

Recording a ruling wakes the agent that raised it.

## Topologies

The widget does not assume where Tightbeam runs. It resolves the transport at
run time from one setting:

| `host` | Behaviour |
|---|---|
| blank (default) | This machine is an assimilated Tightbeam node. The CLI runs locally, no network hop. |
| anything else | An ssh destination — a hostname, `user@host`, or an alias from `~/.ssh/config`. |

`local`, `localhost` and this machine's own hostname are also treated as local,
so pointing the widget at the node you are sitting on does not force a
pointless ssh round trip.

The CLI is never assumed to live at a fixed path. It is looked up on `PATH`
first, then `~/.local/bin/tightbeam`, on whichever machine ends up running it.

## Prerequisites

**Local:** this machine has to be an assimilated Tightbeam node. Assimilation
is driven *from* an existing node, not from here — run this on one of them:

```sh
tightbeam assimilate <this-machine>
```

That installs the CLI and adapters and registers the host. Credentials never
transit between machines, so run `tightbeam onboard` here afterwards.

**Remote:** key-based ssh to the host. Connections use `BatchMode=yes` and will
never prompt, so an agent or a configured `IdentityFile` must already
authenticate non-interactively. Verify with:

```sh
ssh -o BatchMode=yes <host> tightbeam decision-requests --status open
```

Your `~/.ssh/config` is honoured, so a jump host, a non-default port or a
per-host key belong there rather than in this widget.

**Chat (optional):** the explain-and-discuss pane runs on the ACP bridge
shipped with the [Ask](https://github.com/clickety-clacks/omarchy-ask) plugin,
at `~/.config/omarchy/plugins/clickety-clacks.ask/bridge/bridge.js`. Listing
and ruling work without it; only the chat needs it, and it says so plainly if
the bridge is absent.

## Settings

| Key | Default | Meaning |
|---|---|---|
| `host` | blank | Where Tightbeam runs. See Topologies. |
| `asUser` | blank | Tightbeam identity for `--as-user`. Blank uses the account the CLI runs as. |
| `refreshIntervalSec` | `30` | Poll interval, floored at 10s. |

The older `user` key is still read as a fallback for `asUser`, so an existing
`shell.json` keeps working.

## Kind toggles

Each decision-request kind the org is currently raising gets an on/off button.
The buttons are built from what the org raises, not from what is visible, so
switching a kind off never removes the control that switches it back on.

Choices persist to `~/.config/omarchy/tightbeam-decisions.json`. `effort` is
off by default; every other kind, including one introduced after this was
written, defaults to shown.

## Window lifetime

The bar widget is only the list and launcher. Decision detail windows are
owned by a separate Quickshell instance (`WindowHost.qml`) reached through
`decision-window-host.sh`. An open window therefore survives both Omarchy
Shell plugin reloads and Hyprland configuration reloads. The host starts with
the widget and is recovered automatically when a menu item or notification is
opened.

## Agent skill

Installing agents should also expose the bundled `show-decision-request` skill
to both Codex and Claude. It lets any agent with a decision-request ID open the
standalone window directly, without going through the bar menu.

From the installed plugin directory, create the two skill links:

```sh
plugin_dir="$HOME/.config/omarchy/plugins/mike.tightbeam-decisions"
mkdir -p "$HOME/.codex/skills" "$HOME/.claude/skills"
ln -sfn "$plugin_dir/skills/show-decision-request" "$HOME/.codex/skills/show-decision-request"
ln -sfn "$plugin_dir/skills/show-decision-request" "$HOME/.claude/skills/show-decision-request"
```

If either destination is an actual directory rather than a symbolic link,
preserve it and reconcile its contents instead of deleting it. New agent
sessions will discover the skill automatically. The skill is intentionally
machine-specific: it opens the local plugin configured for Gibson as Mike.

## Files

| File | Role |
|---|---|
| `Panel.qml` | Bar widget, request list, kind toggles |
| `WindowHost.qml` | Independent process that owns decision windows and polls their status |
| `decision-window-host.sh` | Starts the window host and forwards open requests over IPC |
| `DecisionWindow.qml` | Standalone decision detail window |
| `skills/show-decision-request/SKILL.md` | Shared Codex/Claude skill for opening a request by ID |
| `DecisionChat.qml` | Explain-and-discuss pane, ruling control |
| `tightbeam.sh` | Transport resolution; `tb()` runs the CLI locally or over ssh |
| `fetch.sh` | Open requests plus the kinds present, as JSON |
| `reply.sh` | Records a ruling and wakes the raiser |
| `message.sh` | Sends a message to the raising agent |
| `mark-seen.sh` | Tracks which request ids have been seen |
