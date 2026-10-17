#!/usr/bin/env bash
#
# Made and brought to by Kiran George
# /* -- ✨ https://github.com/SherLock707 ✨ -- */  ##
# Dropdown Terminal
# Usage: ./Dropdown.sh [-d] <terminal_command>
# Example: ./Dropdown.sh foot
#          ./Dropdown.sh -d foot (with debug output)
#          ./Dropdown.sh "kitty -e zsh"
#          ./Dropdown.sh "alacritty --working-directory /home/user"

DEBUG=false
SPECIAL_WS="special:scratchpad"
# Runtime state in the per-user runtime directory rather than /tmp: /run/user/$UID
# is mode 0700 and ours alone, while /tmp is world-writable, so any other uid on
# the box could have pre-created this path and chosen the window address this
# script then drives. XDG_RUNTIME_DIR is always set inside a session; the
# fallback covers a bare TTY without one.
runtime_dir="${XDG_RUNTIME_DIR:-$HOME/.cache}"
mkdir -p "$runtime_dir" 2>/dev/null
ADDR_FILE="$runtime_dir/dropdown_terminal_addr"

# Dropdown size and position configuration (percentages)
WIDTH_PERCENT=65  # Width as percentage of screen width
HEIGHT_PERCENT=65 # Height as percentage of screen height
Y_PERCENT=10      # Y position as percentage from top (X is auto-centered)

# The slide is Hyprland's own windowsMove animation (UserAnimations.lua): the
# window waits above the screen and is moved in or out with ONE move. It used to
# be stepped here - 7 moves 30 ms apart - and Hyprland animated every step, so
# the steps fought each other. Seconds to let the slide out finish before the
# window goes back to the scratchpad: windowsMove speed 3.79 = ~0.38 s.
# (Off-screen moves that must not be seen go through park, with no animation.)
SLIDE_OUT_WAIT=0.45

# Parse arguments
if [ "$1" = "-d" ]; then
  DEBUG=true
  shift
fi

TERMINAL_CMD="$1"

# Debug echo function
debug_echo() {
  if [ "$DEBUG" = true ]; then
    echo "$@"
  fi
}

# Validate input
if [ -z "$TERMINAL_CMD" ]; then
  echo "Missing terminal command. Usage: $0 [-d] <terminal_command>"
  echo "Examples:"
  echo "  $0 foot"
  echo "  $0 -d foot (with debug output)"
  echo "  $0 'kitty -e zsh'"
  echo "  $0 'alacritty --working-directory /home/user'"
  echo ""
  echo "Edit the script to modify size and position:"
  echo "  WIDTH_PERCENT  - Width as percentage of screen (default: 50)"
  echo "  HEIGHT_PERCENT - Height as percentage of screen (default: 50)"
  echo "  Y_PERCENT      - Y position from top as percentage (default: 5)"
  echo "  Note: X position is automatically centered"
  exit 1
fi

# Function to get window geometry
get_window_geometry() {
  local addr="$1"
  hyprctl clients -j | jq -r --arg ADDR "$addr" '.[] | select(.address == $ADDR) | "\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"'
}

# Where the dropdown waits while hidden: same x, its own height (plus 50 px)
# above its shown position - off the top of the screen.
hidden_y() { # shown_y height
  echo $(($1 - $2 - 50))
}

# Put the window where it waits, instantly: with animations off for just this
# window, so neither the move nor a workspace change is played on screen.
park() { # addr x hidden_y
  hyprctl dispatch "hl.dsp.window.set_prop({ prop = 'no_anim', value = '1', window = 'address:$1' })" >/dev/null 2>&1
  hyprctl dispatch "hl.dsp.window.move({ x = $2, y = $3, window = 'address:$1' })" >/dev/null 2>&1
  hyprctl dispatch "hl.dsp.window.set_prop({ prop = 'no_anim', value = '0', window = 'address:$1' })" >/dev/null 2>&1
}

# Show: the window is already waiting above the screen (see hidden_y), so moving
# it onto this workspace happens out of sight, and one move brings it down.
slide_down() { # addr x y width height
  local addr="$1" x="$2" y="$3" width="$4" height="$5" hy at
  hy=$(hidden_y "$y" "$height")
  # Not where it should wait (a new size or monitor)? Put it there first,
  # while it is still hidden - animated, it would appear mid-flight.
  at=$(get_window_geometry "$addr" | cut -d' ' -f1,2)
  [ "$at" != "$x $hy" ] && park "$addr" "$x" "$hy"
  hyprctl dispatch "hl.dsp.window.move({ workspace = '$CURRENT_WS', follow = false, window = 'address:$addr' })" >/dev/null 2>&1
  hyprctl dispatch "hl.dsp.window.pin({ window = 'address:$addr' })" >/dev/null 2>&1
  hyprctl dispatch "hl.dsp.window.move({ x = $x, y = $y, window = 'address:$addr' })" >/dev/null 2>&1
  debug_echo "Slid $addr down to $x,$y"
}

# Hide: one move up off the screen, then back to the scratchpad with animations
# off. Moving it there puts the window back on screen (Hyprland keeps a floating
# window inside the monitor) and fades it out - a ghost of the terminal flashed
# at the top. park then leaves it waiting above the screen for the next show.
slide_up() { # addr x y height
  local addr="$1" x="$2" y="$3" height="$4" hy
  hy=$(hidden_y "$y" "$height")
  hyprctl dispatch "hl.dsp.window.move({ x = $x, y = $hy, window = 'address:$addr' })" >/dev/null 2>&1
  sleep "$SLIDE_OUT_WAIT"
  hyprctl dispatch "hl.dsp.window.set_prop({ prop = 'no_anim', value = '1', window = 'address:$addr' })" >/dev/null 2>&1
  hyprctl dispatch "hl.dsp.window.pin({ window = 'address:$addr' })" >/dev/null 2>&1 # unpin (toggle)
  hyprctl dispatch "hl.dsp.window.move({ workspace = '$SPECIAL_WS', follow = false, window = 'address:$addr' })" >/dev/null 2>&1
  park "$addr" "$x" "$hy"
  debug_echo "Slid $addr up and into $SPECIAL_WS"
}

# Function to get monitor info including scale and name of focused monitor
# width/height are the mode's, before rotation: a rotated (odd transform)
# monitor swaps them, as in ScreenShot.sh - on a portrait screen the dropdown
# was sized for landscape and spilled onto the next monitor.
get_monitor_info() {
  local monitor_data=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true)
    | (if (.transform % 2) == 1 then "\(.height) \(.width)" else "\(.width) \(.height)" end) as $wh
    | "\(.x) \(.y) \($wh) \(.scale) \(.name)"')
  if [ -z "$monitor_data" ] || [[ "$monitor_data" =~ ^null ]]; then
    debug_echo "Error: Could not get focused monitor information"
    return 1
  fi
  echo "$monitor_data"
}

# Function to calculate dropdown position with proper scaling and centering
calculate_dropdown_position() {
  local monitor_info=$(get_monitor_info)

  if [ $? -ne 0 ] || [ -z "$monitor_info" ]; then
    debug_echo "Error: Failed to get monitor info, using fallback values"
    echo "100 100 800 600 fallback-monitor"
    return 1
  fi

  local mon_x=$(echo $monitor_info | cut -d' ' -f1)
  local mon_y=$(echo $monitor_info | cut -d' ' -f2)
  local mon_width=$(echo $monitor_info | cut -d' ' -f3)
  local mon_height=$(echo $monitor_info | cut -d' ' -f4)
  local mon_scale=$(echo $monitor_info | cut -d' ' -f5)
  local mon_name=$(echo $monitor_info | cut -d' ' -f6)

  debug_echo "Monitor info: x=$mon_x, y=$mon_y, width=$mon_width, height=$mon_height, scale=$mon_scale"

  # Validate scale value and provide fallback
  if [ -z "$mon_scale" ] || [ "$mon_scale" = "null" ] || [ "$mon_scale" = "0" ]; then
    debug_echo "Invalid scale value, using 1.0 as fallback"
    mon_scale="1.0"
  fi

  # Calculate logical dimensions by dividing physical dimensions by scale
  local logical_width logical_height
  if command -v bc >/dev/null 2>&1; then
    # Use bc for precise floating point calculation
    logical_width=$(echo "scale=0; $mon_width / $mon_scale" | bc | cut -d'.' -f1)
    logical_height=$(echo "scale=0; $mon_height / $mon_scale" | bc | cut -d'.' -f1)
  else
    # Fallback to integer math (multiply by 100 for precision, then divide)
    local scale_int=$(echo "$mon_scale" | sed 's/\.//' | sed 's/^0*//')
    if [ -z "$scale_int" ]; then scale_int=100; fi

    logical_width=$(((mon_width * 100) / scale_int))
    logical_height=$(((mon_height * 100) / scale_int))
  fi

  # Ensure we have valid integer values
  if ! [[ "$logical_width" =~ ^-?[0-9]+$ ]]; then logical_width=$mon_width; fi
  if ! [[ "$logical_height" =~ ^-?[0-9]+$ ]]; then logical_height=$mon_height; fi

  debug_echo "Physical resolution: ${mon_width}x${mon_height}"
  debug_echo "Logical resolution: ${logical_width}x${logical_height} (physical ÷ scale)"

  # Calculate window dimensions based on LOGICAL space percentages
  local width=$((logical_width * WIDTH_PERCENT / 100))
  local height=$((logical_height * HEIGHT_PERCENT / 100))

  # Calculate Y position from top based on percentage of LOGICAL height
  local y_offset=$((logical_height * Y_PERCENT / 100))

  # Calculate centered X position in LOGICAL space
  local x_offset=$(((logical_width - width) / 2))

  # Apply monitor offset to get final positions in logical coordinates
  local final_x=$((mon_x + x_offset))
  local final_y=$((mon_y + y_offset))

  debug_echo "Window size: ${width}x${height} (logical pixels)"
  debug_echo "Final position: x=$final_x, y=$final_y (logical coordinates)"
  debug_echo "Hyprland will scale these to physical coordinates automatically"

  echo "$final_x $final_y $width $height $mon_name"
}

# Get the current workspace
CURRENT_WS=$(hyprctl activeworkspace -j | jq -r '.id')

# Function to get stored terminal address
get_terminal_address() {
  if [ -f "$ADDR_FILE" ] && [ -s "$ADDR_FILE" ]; then
    cut -d' ' -f1 "$ADDR_FILE"
  fi
}

# Function to get stored monitor name
get_terminal_monitor() {
  if [ -f "$ADDR_FILE" ] && [ -s "$ADDR_FILE" ]; then
    cut -d' ' -f2- "$ADDR_FILE"
  fi
}

# Function to check if terminal exists
terminal_exists() {
  local addr=$(get_terminal_address)
  if [ -n "$addr" ]; then
    hyprctl clients -j | jq -e --arg ADDR "$addr" 'any(.[]; .address == $ADDR)' >/dev/null 2>&1
  else
    return 1
  fi
}

# Function to check if terminal is in special workspace
terminal_in_special() {
  local addr=$(get_terminal_address)
  if [ -n "$addr" ]; then
    hyprctl clients -j | jq -e --arg ADDR "$addr" 'any(.[]; .address == $ADDR and .workspace.name == "special:scratchpad")' >/dev/null 2>&1
  else
    return 1
  fi
}

# Function to spawn terminal and capture its address
spawn_terminal() {
  debug_echo "Creating new dropdown terminal with command: $TERMINAL_CMD"

  # Calculate dropdown position for later use
  local pos_info=$(calculate_dropdown_position)
  if [ $? -ne 0 ]; then
    debug_echo "Warning: Using fallback positioning"
  fi

  local target_x=$(echo $pos_info | cut -d' ' -f1)
  local target_y=$(echo $pos_info | cut -d' ' -f2)
  local width=$(echo $pos_info | cut -d' ' -f3)
  local height=$(echo $pos_info | cut -d' ' -f4)
  local monitor_name=$(echo $pos_info | cut -d' ' -f5)

  debug_echo "Target position: ${target_x},${target_y}, size: ${width}x${height}"

  # Get window count before spawning
  local windows_before=$(hyprctl clients -j)

  # Launch terminal directly in special workspace to avoid visible spawn
  # exec with window rules: float, size, and open silently on the scratchpad.
  # The command goes in a Lua long string so quotes inside $TERMINAL_CMD survive.
  hyprctl dispatch "hl.dsp.exec_cmd([==[$TERMINAL_CMD]==], { float = true, size = '$width $height', move = '$target_x $(hidden_y "$target_y" "$height")', workspace = 'special:scratchpad silent' })"

  # Wait for the new window: compare the client list with the one taken before
  # the spawn, polling for up to ~2 s. It used to look once after 0.1 s and then
  # fall back to "sort_by(.focusHistoryID) | .[-1]" - but focusHistoryID 0 is
  # the FOCUSED window, so that picked the least recently focused one: a slow
  # terminal start moved, pinned and slid in some other window, and left the new
  # terminal hidden in the scratchpad. No match means no guess.
  local new_addr="" _try
  for _try in $(seq 1 20); do
    sleep 0.1
    new_addr=$(comm -13 \
      <(echo "$windows_before" | jq -r '.[].address' | sort) \
      <(hyprctl clients -j | jq -r '.[].address' | sort) |
      head -1)
    [ -n "$new_addr" ] && break
  done

  if [ -n "$new_addr" ] && [ "$new_addr" != "null" ]; then
    # Store the address and monitor name
    echo "$new_addr $monitor_name" >"$ADDR_FILE"
    debug_echo "Terminal created with address: $new_addr in special workspace on monitor $monitor_name"

    # Small delay to ensure it's properly in special workspace
    sleep 0.2

    # Now bring it in the same way as every later show
    slide_down "$new_addr" "$target_x" "$target_y" "$width" "$height"

    return 0
  fi

  debug_echo "Failed to get terminal address"
  return 1
}

# Main logic
if terminal_exists; then
  TERMINAL_ADDR=$(get_terminal_address)
  debug_echo "Found existing terminal: $TERMINAL_ADDR"
  focused_monitor=$(get_monitor_info | awk '{print $6}')
  dropdown_monitor=$(get_terminal_monitor)
  if [ "$focused_monitor" != "$dropdown_monitor" ]; then
    debug_echo "Monitor focus changed: moving dropdown to $focused_monitor"
    # Calculate new position for focused monitor
    pos_info=$(calculate_dropdown_position)
    target_x=$(echo $pos_info | cut -d' ' -f1)
    target_y=$(echo $pos_info | cut -d' ' -f2)
    width=$(echo $pos_info | cut -d' ' -f3)
    height=$(echo $pos_info | cut -d' ' -f4)
    monitor_name=$(echo $pos_info | cut -d' ' -f5)
    # Move and resize window
    hyprctl dispatch "hl.dsp.window.move({ x = $target_x, y = $target_y, window = 'address:$TERMINAL_ADDR' })"
    hyprctl dispatch "hl.dsp.window.resize({ x = $width, y = $height, window = 'address:$TERMINAL_ADDR' })"
    # Update ADDR_FILE
    echo "$TERMINAL_ADDR $monitor_name" >"$ADDR_FILE"
  fi

  if terminal_in_special; then
    debug_echo "Bringing terminal from scratchpad with slide down animation"

    # Calculate target position
    pos_info=$(calculate_dropdown_position)
    target_x=$(echo $pos_info | cut -d' ' -f1)
    target_y=$(echo $pos_info | cut -d' ' -f2)
    width=$(echo $pos_info | cut -d' ' -f3)
    height=$(echo $pos_info | cut -d' ' -f4)

    # Size it while it is still hidden, then slide it down
    hyprctl dispatch "hl.dsp.window.resize({ x = $width, y = $height, window = 'address:$TERMINAL_ADDR' })"
    slide_down "$TERMINAL_ADDR" "$target_x" "$target_y" "$width" "$height"

    hyprctl dispatch "hl.dsp.focus({ window = 'address:$TERMINAL_ADDR' })"
  else
    debug_echo "Hiding terminal to scratchpad with slide up animation"

    # Get current geometry for animation
    geometry=$(get_window_geometry "$TERMINAL_ADDR")
    if [ -n "$geometry" ]; then
      curr_x=$(echo $geometry | cut -d' ' -f1)
      curr_y=$(echo $geometry | cut -d' ' -f2)
      curr_width=$(echo $geometry | cut -d' ' -f3)
      curr_height=$(echo $geometry | cut -d' ' -f4)

      debug_echo "Current geometry: ${curr_x},${curr_y} ${curr_width}x${curr_height}"

      slide_up "$TERMINAL_ADDR" "$curr_x" "$curr_y" "$curr_height"
    else
      debug_echo "Could not get window geometry, moving to scratchpad without animation"
      hyprctl dispatch "hl.dsp.window.pin({ window = 'address:$TERMINAL_ADDR' })"
      hyprctl dispatch "hl.dsp.window.move({ workspace = '$SPECIAL_WS', follow = false, window = 'address:$TERMINAL_ADDR' })"
    fi
  fi
else
  debug_echo "No existing terminal found, creating new one"
  if spawn_terminal; then
    TERMINAL_ADDR=$(get_terminal_address)
    if [ -n "$TERMINAL_ADDR" ]; then
      hyprctl dispatch "hl.dsp.focus({ window = 'address:$TERMINAL_ADDR' })"
    fi
  fi
fi
