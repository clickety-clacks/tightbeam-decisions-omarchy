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

**Agent integration:** this package owns its ACP bridge and installs pinned ACP
adapters locally. It uses the system-installed `codex` or `claude` executable;
install and authenticate that harness separately. Ask is not required.

From this plugin directory run `npm ci --prefix bridge --ignore-scripts --omit=optional`.
The adapter's transitive Codex package is not used: execution is explicitly
directed to the system executable. No system harness is installed or upgraded
by this step.

`summarizers.json` configures `main` and `parentNotes` models and reasoning
effort separately. Use full model IDs (for example `gpt-5.6-luna`).
The optional top-level `provider` selects `codex` or `claude`; otherwise
Omarchy's `~/.config/omarchy/defaults/agent` is used. A `DR_AGENT` environment
override is also supported. Ask settings and `ASK_*` variables are ignored.
The main chat uses permission prompts by default. Its own permission settings
are stored in `~/.config/omarchy/tightbeam-decisions-agent.json`.
The parent/notes/choice summarizer denies tool permission requests.

Develop in a separate checkout. Installing QML under the live plugin directory
can reload the window host and close open windows; arrange installation with
the user first.

## Settings

### Agent settings (Ctrl+,)

The settings window (Ctrl+, from any decision window; Ctrl+, or Esc closes it)
holds agent settings and scroll motion. It is an ordinary window, so it can be
moved, and on Scottland scaled or turned into a widget. It also auto-saves the selected harness/model atomically to
`~/.config/omarchy/tightbeam-decisions-model.json`. This shared override applies
to both summarizer roles when a bridge starts. Every menu rereads it on open;
existing conversations are preserved until explicitly re-summarized.
Tools always auto-approve (YOLO). The older permission-mode description above
is superseded by this policy.

No additional window-manager binding or separate settings menu is needed.
Thinking level also auto-saves for both summarizers; Codex choices are filtered
to levels supported by the selected model. Model default leaves the harness default
unchanged. The Close button stays visible above the scrolling settings content.
QML installation can reload open DR windows: obtain approval before installing.

The model catalog uses the installed adapters' identifiers. `bridge/probe-models.js`
exercises real ACP selection and a minimal generation. All six Codex entries
passed on Plumbus with system Codex 0.154.0 on September 13; results are in
`bridge/model-probe-results-codex-plumbus.json`. All five Claude entries passed
on osanwe with system Claude Code 2.1.280 on September 23; results are in
`bridge/model-probe-results-claude-osanwe.json`. Earlier failed Plumbus probes,
from when Claude was not logged in there, are preserved in
`bridge/model-probe-results-plumbus.json`.

Claude aliases such as `opus[1m]` follow the installed Claude Code release. The
picker asks the harness which version each alias names (no prompt is sent) and
shows it, e.g. "Opus 5.5 (1M)". The answer is cached per Claude Code version in
`~/.local/state/omarchy-tightbeam-decisions/claude-model-versions.json`; if the
lookup fails, the catalog label is shown instead.

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

Kinds are shown by what they ask of you, with the same icon on the toggle, on
each row, and on the decision window:

| Kind | Shown as | Meaning |
|---|---|---|
| `operator` | 󱜸 Agent questions | An agent is asking you to choose |
| `effort` | 󰗶 Substrate issues | Tightbeam flagged an agent that was prodded and produced nothing |
| anything else | 󰋗 its raw name | A kind this plugin does not know yet |

Choices persist to `~/.config/omarchy/tightbeam-decisions.json`. `effort` is
off by default; every other kind, including one introduced after this was
written, defaults to shown.

## Window lifetime

The bar widget is only the list and launcher. Decision detail windows are
owned by a separate Quickshell instance (`WindowHost.qml`) reached through
`decision-window-host.sh`. The launcher runs that instance as the transient
`mike-tightbeam-decision-windows.service` user service, so an open window
survives the launching process, Omarchy Shell plugin reloads, and Hyprland
configuration reloads. The host starts with the widget and is recovered
automatically when a menu item or notification is opened.

Each request has at most one window. Opening a request that already has one,
from the bar, a notification or the `show-decision-request` skill, brings that
window to you instead of opening a second. The settings window (Ctrl+,) works
the same way.

The host is a long-lived service, so its environment is fixed when it starts,
which can be before the desktop has exported the user's `PATH`. It runs node
through `bridge/node.sh`, which reads the user manager's current `PATH` at each
launch so the bridge, `codex` and `claude` are always found.

## Compositors

The plugin runs on Hyprland and on Scottland. `bridge/compositor.js` is the
only code that talks to the compositor, adapted from Ask's module of the same
name. It picks a backend from `XDG_CURRENT_DESKTOP`; window lookup goes through
the Hyprland IPC, which Scottland's shim also serves. Bringing a window to you
("present") differs:

| | Hyprland | Scottland |
|---|---|---|
| Window in view | focused | raised and focused |
| Window scaled down at a side | — | flies to the middle at full size, focused |
| Window turned into a rail widget | — | opens back into its window in the middle |

When an agent finishes a reply in a window you are not using, the window asks
for attention (xdg-activation). Scottland shows that as its attention halo on
the window or its widget and does not take focus.

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
| `DecisionMenu.qml` | Bar dropdown: request list, kind toggles |
| `DecisionMenuIndicator.qml` | Bar button: flag mark and open-request count |
| `FlagIcon.qml` | The flag mark, drawn as vector paths in any color |
| `kinds.js` | Icon, label and description for each decision-request kind |
| `ModelSettings.qml` | Harness, model and thinking-level picker |
| `WindowHost.qml` | Independent process that owns decision windows and polls their status |
| `decision-window-host.sh` | Starts the window host and forwards open requests over IPC |
| `DecisionWindow.qml` | Standalone decision detail window |
| `MotionTuner.qml` | Settings window (Ctrl+,): agent settings and scroll motion |
| `bridge/compositor.js` | Hyprland and Scottland backends: find and present a window |
| `bridge/present-window.js` | Presents one of the window host's own windows by title |
| `bridge/node.sh` | Runs node with the user manager's current `PATH` |
| `skills/show-decision-request/SKILL.md` | Shared Codex/Claude skill for opening a request by ID |
| `DecisionChat.qml` | Explain-and-discuss pane, ruling control |
| `tightbeam.sh` | Transport resolution; `tb()` runs the CLI locally or over ssh |
| `fetch.sh` | Open requests plus the kinds present, as JSON |
| `reply.sh` | Records a ruling and wakes the raiser |
| `message.sh` | Sends a message to the raising agent |
| `mark-seen.sh` | Tracks which request ids have been seen |
