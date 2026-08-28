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

**Local:** the `tightbeam` CLI installed and on `PATH` (or in `~/.local/bin`).

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

## Files

| File | Role |
|---|---|
| `Panel.qml` | Bar widget, request list, kind toggles |
| `DecisionChat.qml` | Explain-and-discuss pane, ruling control |
| `tightbeam.sh` | Transport resolution; `tb()` runs the CLI locally or over ssh |
| `fetch.sh` | Open requests plus the kinds present, as JSON |
| `reply.sh` | Records a ruling and wakes the raiser |
| `message.sh` | Sends a message to the raising agent |
| `mark-seen.sh` | Tracks which request ids have been seen |
