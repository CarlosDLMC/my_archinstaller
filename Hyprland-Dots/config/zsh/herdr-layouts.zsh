#!/usr/bin/env zsh
# Herdr dev layouts - one command builds a pane layout and starts everything in it.
#
# Ported from Omarchy Quattro's default/bash/fns/herdr (omacom/omarchy, MIT, DHH).
# The layout algorithms are his; the code below is a zsh port with this machine's
# tools substituted. None of his code is copied verbatim - see the notes below for
# why a verbatim copy would not have run here at all.
#
#   hdl  [agent] [agent2]   editor left, agent(s) right, terminal along the bottom
#   hds                     2x2 square: editor, live diff, terminal, agent
#   hdlm [agent] [agent2]   one hdl tab per subdirectory of the current directory
#   hsl  <count> <command>  N panes in a grid, all running the same command
#
# Plus one thing that is not a layout at all:
#
#   herdr-off               stop the server so the session is actually saved,
#                           then power off. Run it OUTSIDE herdr - see its own
#                           comment for the shutdown race it works around.
#
# Three deliberate differences from Omarchy's originals:
#
#   1. zsh, not bash. Omarchy's are bash functions and arrays there are 0-indexed.
#      zsh arrays are 1-indexed, so his `for (( index = 0; index < cols; index++ ))`
#      over `${columns[index]}` would read an empty slot first and never reach the
#      last column - hsl would silently build one column fewer than asked. The loop
#      below runs 1..cols and the "extra row" test moved from `<` to `<=` to match.
#
#   2. The agent defaults to `claude`, not `opencode`. Omarchy's hds hardcodes
#      opencode and his hdl requires the agent as an argument; here both default to
#      Claude Code, and any other agent still works as `hdl codex`.
#
#   3. The editor is `nvim`, not `$EDITOR`. $EDITOR is `vim` on this machine
#      (UserConfigs/01-UserDefaults.lua) and these layouts exist for the LazyVim
#      file tree, which vim does not have. Naming it outright also means the layout
#      does not change meaning if $EDITOR is later repointed at something else.
#
# Everything here drives herdr over its socket API rather than through keybindings,
# so it is independent of config.toml and unaffected by a different keymap.

# Echo a split ratio as a float.
_herdr_ratio() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.4f", a / b }'
}

# Split a pane and echo the id of the new one.
# Usage: _herdr_split <pane_id> <right|down> <ratio> <cwd>
_herdr_split() {
  herdr pane split "$1" --direction "$2" --ratio "$3" --cwd "$4" --no-focus |
    jq -r '.result.pane.pane_id'
}

# Shared preflight. Herdr exports HERDR_PANE_ID into every pane it owns, so an
# empty one means we are in a plain terminal and there is nothing to split.
_herdr_layout_ready() {
  if [[ -z $HERDR_PANE_ID ]]; then
    echo "Not inside herdr - start it with \`herdr\` first." >&2
    return 1
  fi
  if ! command -v jq >/dev/null; then
    echo "jq is required by the herdr layouts but is not installed." >&2
    return 1
  fi
  return 0
}

# Warn about commands a layout is about to start that are not installed.
#
# The layout still builds - the pane exists and you can type in it - but a pane
# that only says "command not found" is otherwise a puzzle. It matters most on a
# fresh install: this repo installs no coding agent at all, so `claude` is not
# there until you install it yourself, exactly like the SUPER+T / SUPER+R binds
# in the README. nvim and hunk are only present if their install options were on.
_herdr_note_missing() {
  local c
  for c in "$@"; do
    [[ -n $c ]] || continue
    command -v "${c%% *}" >/dev/null 2>&1 ||
      print -u2 "herdr layout: '${c%% *}' is not installed - its pane will be empty."
  done
}

# Dev Layout: editor left, agent(s) right, terminal along the bottom.
# Usage: hdl [agent] [second_agent]
hdl() {
  _herdr_layout_ready || return 1

  local current_dir="$PWD"
  local ai="${1:-claude}"
  local ai2="${2:-}"
  local editor_pane ai_pane ai2_pane

  # HERDR_PANE_ID, not "the focused pane" - it stays correct if focus moves while
  # the layout is still being built.
  editor_pane="$HERDR_PANE_ID"

  _herdr_note_missing nvim "$ai" "$ai2"

  herdr tab rename "$HERDR_TAB_ID" "${current_dir:t}" >/dev/null

  # Terminal along the bottom (top keeps 85%), then the agent column on the right.
  _herdr_split "$editor_pane" down 0.85 "$current_dir" >/dev/null
  ai_pane=$(_herdr_split "$editor_pane" right 0.7 "$current_dir")

  if [[ -n $ai2 ]]; then
    ai2_pane=$(_herdr_split "$ai_pane" down 0.5 "$current_dir")
    herdr pane run "$ai2_pane" "$ai2" >/dev/null
  fi

  herdr pane run "$ai_pane" "$ai" >/dev/null
  herdr pane run "$editor_pane" "nvim ." >/dev/null
}

# Dev Square: editor, live diff, terminal, agent - one quadrant each.
# The diff pane is the point: `hunk diff --watch` re-renders the working tree as
# the agent writes to it, so the review is always on screen without being asked for.
# Usage: hds [agent]
hds() {
  _herdr_layout_ready || return 1

  local current_dir="$PWD"
  local ai="${1:-claude}"
  local editor_pane diff_pane terminal_pane ai_pane

  editor_pane="$HERDR_PANE_ID"

  _herdr_note_missing nvim hunk "$ai"

  herdr tab rename "$HERDR_TAB_ID" "${current_dir:t}" >/dev/null

  terminal_pane=$(_herdr_split "$editor_pane" down 0.5 "$current_dir")
  diff_pane=$(_herdr_split "$editor_pane" right 0.5 "$current_dir")
  ai_pane=$(_herdr_split "$terminal_pane" right 0.5 "$current_dir")

  herdr pane run "$editor_pane" "nvim ." >/dev/null
  herdr pane run "$diff_pane" "hunk diff --watch" >/dev/null
  herdr pane run "$ai_pane" "$ai" >/dev/null
}

# One hdl tab per subdirectory of the current directory.
# Usage: hdlm [agent] [second_agent]
hdlm() {
  _herdr_layout_ready || return 1

  local ai="${1:-claude}"
  local ai2="${2:-}"
  local base_dir="$PWD"
  local first=1
  local hdl_command dirpath pane_id

  herdr workspace rename "$HERDR_WORKSPACE_ID" "${base_dir:t}" >/dev/null

  for dirpath in "$base_dir"/*(/N); do
    dirpath="${dirpath%/}"

    printf -v hdl_command 'hdl %q' "$ai"
    [[ -n $ai2 ]] && printf -v hdl_command '%s %q' "$hdl_command" "$ai2"

    if (( first )); then
      # Reuse the tab we are standing in for the first project.
      printf -v hdl_command 'cd %q && %s' "$dirpath" "$hdl_command"
      herdr pane run "$HERDR_PANE_ID" "$hdl_command" >/dev/null
      first=0
    else
      pane_id=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$dirpath" --no-focus |
        jq -r '.result.root_pane.pane_id')
      herdr pane run "$pane_id" "$hdl_command" >/dev/null
    fi
  done
}

# Swarm: count panes tiled in a grid, all running the same command.
# Usage: hsl <count> <command>
hsl() {
  [[ -z $1 || -z $2 ]] && { echo "Usage: hsl <pane_count> <command>" >&2; return 1; }
  _herdr_layout_ready || return 1

  local count="$1"
  local cmd="$2"
  local current_dir="$PWD"
  local -a columns panes
  local cols=1 k index col rows j last pane

  _herdr_note_missing "$cmd"

  herdr tab rename "$HERDR_TAB_ID" "${current_dir:t}" >/dev/null

  # ceil(sqrt(count)) columns.
  while (( cols * cols < count )); do (( cols++ )); done

  # Peel each new column off the rightmost one at 1/(n-k+1), which keeps the
  # array in left-to-right order.
  columns=("$HERDR_PANE_ID")
  for (( k = 1; k < cols; k++ )); do
    columns+=("$(_herdr_split "${columns[-1]}" right "$(_herdr_ratio 1 $((cols - k + 1)))" "$current_dir")")
  done

  # Split each column into its share of rows. 1-based: the first (count % cols)
  # columns take the extra row, so the test is <= here where Omarchy's 0-based
  # loop used <.
  for (( index = 1; index <= cols; index++ )); do
    col="${columns[index]}"
    rows=$(( count / cols ))
    (( index <= count % cols )) && (( rows++ ))
    panes+=("$col")
    last="$col"
    for (( j = 1; j < rows; j++ )); do
      last=$(_herdr_split "$last" down "$(_herdr_ratio 1 $((rows - j + 1)))" "$current_dir")
      panes+=("$last")
    done
  done

  for pane in "${panes[@]}"; do
    herdr pane run "$pane" "$cmd" >/dev/null
  done
}

# Save the herdr session, then power off.
#
# herdr deletes session.json on shutdown whenever its workspace list is already
# empty - persist::clear() is a real remove_file(), and capture_session_save_job()
# takes that branch on `workspaces.is_empty()`. At poweroff systemd tears down the
# user session first, every pane shell exits, the emptied workspaces auto-close,
# and the shutdown save deletes the snapshot instead of writing one.
#
# Upstream #3415 fixed that race, but only for panes killed by a signal: the guard
# runs on ChildExitReason::Interrupted, and the shells here exit with code 1 and
# signal None, so 0.9.0 still loses the session. Stopping the server by hand makes
# the save run while the workspaces are still populated.
#
# Must run OUTSIDE herdr - a plain terminal, not a pane. Everything after the stop
# runs in a shell herdr would kill along with its panes, so from inside a pane the
# poweroff would never be reached.
herdr-off() {
  herdr server stop || return 1

  # `server stop` returns once the sockets are gone, which is ~50ms before the
  # snapshot is written. Wait for the process to exit, not for the socket.
  # Anchored so a command line that merely mentions the server - another shell,
  # an editor, this function in someone's scrollback - cannot match and stall us.
  local waited=0
  while pgrep -f '^\S+/herdr server$' >/dev/null; do
    sleep 0.2
    (( waited++ ))
    if (( waited > 75 )); then
      print -u2 "herdr-off: server still running after 15s - not powering off."
      return 1
    fi
  done

  # Refuse to power off if the shutdown deleted the session instead of saving it.
  local last
  last=$(grep -E 'persist\.(save|clear)' "$HOME/.config/herdr/herdr-server.log" | tail -1)
  if [[ $last != *persist.save* ]]; then
    print -u2 "herdr-off: session was cleared, not saved - not powering off."
    print -u2 "  ${last:-no persist events in the log}"
    return 1
  fi

  print "herdr-off: ${last#*event=}"
  systemctl poweroff
}
