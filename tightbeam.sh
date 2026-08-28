#!/usr/bin/env bash
# Resolves how to reach the Tightbeam CLI and exposes tb() to run it.
#
# Sourced by fetch.sh, reply.sh and message.sh so all three agree on the
# topology. Two cases, decided at run time rather than configured:
#
#   local   this machine is an assimilated Tightbeam node -- the CLI is on PATH
#           or in ~/.local/bin, and runs directly with no network hop.
#   remote  anything else, reached over ssh.
#
# TB_HOST empty, "local", "localhost" or this machine's own hostname selects
# local. Anything else is an ssh destination and may be a bare hostname, a
# user@host, or an alias from ~/.ssh/config -- the caller's ssh config is
# honoured (unlike the previous -F /dev/null), so a jump host, a port or a
# non-default key configured there just works.
#
# Key-based auth is the prerequisite for the remote case: BatchMode=yes never
# prompts, so an agent forwarding or a configured IdentityFile must already
# authenticate non-interactively.
#
# The CLI is never assumed to sit at a fixed path. Remotely it is resolved in
# the same command that runs it, so one round trip covers both.

TB_HOST="${TB_HOST:-}"
TB_AS_USER="${TB_AS_USER:-}"
TB_SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8)

tb_is_local() {
  case "$TB_HOST" in
    "" | local | localhost | 127.0.0.1 | ::1) return 0 ;;
  esac
  [[ "$TB_HOST" == "$(hostname -s 2>/dev/null)" || "$TB_HOST" == "$(hostname -f 2>/dev/null)" ]]
}

tb_local_cli() {
  command -v tightbeam 2>/dev/null && return 0
  [[ -x "${HOME}/.local/bin/tightbeam" ]] && printf '%s\n' "${HOME}/.local/bin/tightbeam" && return 0
  return 1
}

tb_where() { tb_is_local && printf 'this machine\n' || printf '%s\n' "$TB_HOST"; }

# Runs the Tightbeam CLI with the given arguments, appending --as-user unless
# the caller already passed one. A blank asUser setting means "whoever the CLI
# runs as", resolved on the machine that actually runs it.
tb() {
  local has_as_user=false argument
  for argument in "$@"; do [[ "$argument" == "--as-user" ]] && has_as_user=true; done

  if tb_is_local; then
    local cli
    cli=$(tb_local_cli) || {
      echo "No tightbeam CLI on this machine. Set a Tightbeam host, or install the CLI to make this an assimilated node." >&2
      return 127
    }
    if [[ $has_as_user == false ]]; then
      "$cli" "$@" --as-user "${TB_AS_USER:-$(id -un)}"
    else
      "$cli" "$@"
    fi
    return
  fi

  local quoted=""
  for argument in "$@"; do quoted+=" $(printf %q "$argument")"; done
  local as_user_clause=""
  if [[ $has_as_user == false ]]; then
    if [[ -n "$TB_AS_USER" ]]; then
      as_user_clause=" --as-user $(printf %q "$TB_AS_USER")"
    else
      as_user_clause=' --as-user "$(id -un)"'
    fi
  fi

  ssh "${TB_SSH_OPTS[@]}" "$TB_HOST" \
    "cli=\$(command -v tightbeam 2>/dev/null) || cli=\"\$HOME/.local/bin/tightbeam\"
     [ -x \"\$cli\" ] || { echo \"No tightbeam CLI on \$(hostname)\" >&2; exit 127; }
     \"\$cli\"${quoted}${as_user_clause}"
}
