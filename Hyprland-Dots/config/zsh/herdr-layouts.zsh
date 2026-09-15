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
