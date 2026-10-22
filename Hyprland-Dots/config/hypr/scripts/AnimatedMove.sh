#!/usr/bin/env bash
# Move or swap a window with the slide Hyprland had (SUPER+CTRL / SUPER+ALT +
# arrows).
#
#   AnimatedMove.sh DISPATCHER DIRECTION    e.g. exchange_client left
#
# animations.conf keeps mango's move animation off: while a window shrinks
# beside a new one, mango stretches its smaller frame up to the animated box.
# A move or a swap keeps the sizes, so it is turned on for this one action
# (379 ms, the old value) and off again after it. setoption resets the
# keyboard layout; mango then runs the exec= lines again, and the one in
# startup.conf puts the layout back.

DURATION_MS=379

dispatcher=${1:?usage: AnimatedMove.sh DISPATCHER DIRECTION}
direction=${2:?usage: AnimatedMove.sh DISPATCHER DIRECTION}

# A press during another one's animation keeps the animation on: only the
# last press turns it off.
stamp="${XDG_RUNTIME_DIR:-/tmp}/mango-animated-move"
token="$$.$EPOCHREALTIME"
echo "$token" >"$stamp"

mmsg dispatch "setoption,animation_duration_move,$DURATION_MS" >/dev/null
mmsg dispatch "$dispatcher,$direction" >/dev/null

sleep "$(( DURATION_MS + 100 ))e-3"
[ "$(cat "$stamp" 2>/dev/null)" = "$token" ] || exit 0
mmsg dispatch "setoption,animation_duration_move,0" >/dev/null
