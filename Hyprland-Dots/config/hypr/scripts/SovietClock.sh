#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# ly-style bigclock in block glyphs, for the hyprlock Soviet TUI lock screen.
#
# Why this is shell and not another mode of SovietLock.py: hyprlock re-runs the
# clock once per second per monitor for as long as the screen is locked, and
# with the AC-aware blanking in IdleDpms.sh that is indefinitely. The Python
# version cost ~43 ms a run - 17 ms of interpreter startup plus locale/re/
# subprocess imports the clock never used - which is ~4.4% of one core,
# continuously, on a two-monitor setup. This costs ~2 ms and forks nothing:
# the time comes from bash's printf builtin, not from date(1).
#
# Output is byte-identical to the SovietLock.py --clock it replaces.
#
# Two things have to hold or the clock misbehaves:
#
#   1. Every row must be the exact same rendered width. hyprlock centres each
#      line of a multi-line label independently and Pango trims trailing
#      whitespace before measuring, so padding with plain spaces shears the
#      digits apart. NBSP is not trimmed and shares the monospace advance.
#
#   2. The *ink* must be centred, not the character box. Glyphs like "1" do
#      not reach the edges of their 4-cell box, so a label centred on the box
#      drifts sideways whenever such a digit lands first or last - once an
#      hour, and once a second for the trailing digit. Balancing the blank
#      columns on each side pins the ink to the centre whatever the time.
#
# Takes an optional HH:MM:SS argument in place of the current time, which is
# what the equivalence test against the Python original drives.

# 4x5 block digits, ly bigclock style, one array per glyph row. '#' is ink.
declare -A R0=( [0]="####" [1]="  ##" [2]="####" [3]="####" [4]="#  #" [5]="####" [6]="####" [7]="####" [8]="####" [9]="####" [":"]="  " )
declare -A R1=( [0]="#  #" [1]="   #" [2]="   #" [3]="   #" [4]="#  #" [5]="#   " [6]="#   " [7]="   #" [8]="#  #" [9]="#  #" [":"]="# " )
declare -A R2=( [0]="#  #" [1]="   #" [2]="####" [3]="####" [4]="####" [5]="####" [6]="####" [7]="   #" [8]="####" [9]="####" [":"]="  " )
declare -A R3=( [0]="#  #" [1]="   #" [2]="#   " [3]="   #" [4]="   #" [5]="   #" [6]="#  #" [7]="   #" [8]="#  #" [9]="   #" [":"]="# " )
declare -A R4=( [0]="####" [1]="   #" [2]="####" [3]="####" [4]="   #" [5]="####" [6]="####" [7]="   #" [8]="####" [9]="   #" [":"]="  " )

INK='#'
BLOCK=$'█'
NBSP=$' '

stamp=${1:-}
[[ -n $stamp ]] || printf -v stamp '%(%H:%M:%S)T' -1

rows=('' '' '' '' '')
last=$(( ${#stamp} - 1 ))
for (( i = 0; i <= last; i++ )); do
    ch=${stamp:i:1}
    # Unknown character: contributes nothing at all, separator included.
    [[ -n ${R0[$ch]+set} ]] || continue
    sep=' '
    (( i == last )) && sep=''
    rows[0]+="${R0[$ch]}$sep"
    rows[1]+="${R1[$ch]}$sep"
    rows[2]+="${R2[$ch]}$sep"
    rows[3]+="${R3[$ch]}$sep"
    rows[4]+="${R4[$ch]}$sep"
done

# Leftmost and rightmost inked column across all five rows.
width=${#rows[0]}
left=-1
right=-1
for (( c = 0; c < width; c++ )); do
    if [[ ${rows[0]:c:1} == "$INK" || ${rows[1]:c:1} == "$INK" \
       || ${rows[2]:c:1} == "$INK" || ${rows[3]:c:1} == "$INK" \
       || ${rows[4]:c:1} == "$INK" ]]; then
        (( left < 0 )) && left=$c
        right=$c
    fi
done

lpad=''
rpad=''
if (( left >= 0 )); then
    gap=$(( width - 1 - right ))
    pad=$(( left > gap ? left : gap ))
    printf -v lpad '%*s' "$(( pad - left ))" ''
    printf -v rpad '%*s' "$(( pad - gap ))" ''
fi

out=''
for r in 0 1 2 3 4; do
    line="$lpad${rows[r]}$rpad"
    line=${line//"$INK"/"$BLOCK"}
    line=${line//" "/"$NBSP"}
    out+=$line$'\n'
done
printf '%s' "$out"
