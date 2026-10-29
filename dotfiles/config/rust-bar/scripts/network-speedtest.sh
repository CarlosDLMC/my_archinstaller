#!/usr/bin/env bash
# Measure throughput in one direction, printing one Mbps sample per second.
#
# Ported from Omarchy's omarchy-network-speedtest (omacom/omarchy, MIT, DHH):
# the fast.com endpoint discovery, the parallel curl workers and measuring the
# result off /sys byte counters rather than curl's own timing are his.
#
# Changed here: this one STOPS. The original's workers loop forever and the
# script runs until its caller kills it, which means a panel that closes while
# a test is running leaves eight curls saturating the link. This takes a
# duration, tears the workers down itself, and exits.
#
# Usage: network-speedtest.sh <down|up> [seconds]

set -uo pipefail

direction="${1:-}"
duration="${2:-8}"
probe=1.1.1.1
parallel=8

case "$direction" in
  down|up) ;;
  *) echo "usage: network-speedtest.sh <down|up> [seconds]" >&2; exit 2 ;;
esac

for c in curl jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "error: $c is required" >&2; exit 1; }
done

iface=$(ip route get "$probe" 2>/dev/null | awk '{ for (i=1;i<=NF;i++) if ($i=="dev") { print $(i+1); exit } }')
[[ -n $iface && -r /sys/class/net/$iface/statistics/rx_bytes ]] || {
  echo "error: no active network interface" >&2; exit 1; }

# The public fast.com API token, as used by fast.com's own web client and
# copied from the original script. It is NOT a credential: it identifies the
# fast.com app, carries no account or session, and base64-decodes to the
# keyboard mash "asdfasdlfnsdafhasdfhkalf". Nothing of yours is sent.
#
# It is undocumented API surface, so Netflix can rotate it whenever they like;
# when that happens the endpoint fetch below returns nothing and the script
# exits with "could not reach the speed test endpoints" rather than hanging.
# Override it without editing this file by exporting FAST_TOKEN.
token="${FAST_TOKEN:-YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm}"
urls=$(curl -fsS --max-time 8 \
  "https://api.fast.com/netflix/speedtest/v2?https=true&token=$token&urlCount=3" 2>/dev/null \
  | jq -r '.targets[]?.url // empty')
[[ -n $urls ]] || { echo "error: could not reach the speed test endpoints" >&2; exit 1; }

pids=()
cleanup() {
  # TERM first, then KILL without ceremony. A curl mid-transfer can sit on a
  # TERM long enough to be noticeable, and this only ever runs when the user
  # has already asked for the test to stop.
  for pid in "${pids[@]:-}"; do
    [[ -n ${pid:-} ]] || continue
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${pids[@]:-}"; do
    [[ -n ${pid:-} ]] || continue
    pkill -KILL -P "$pid" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
# EXIT only. Trapping TERM as well ran cleanup twice - once from the TERM
# handler and again from EXIT - and each pass ends in `wait`, so stopping the
# test took about three seconds instead of well under one. With no TERM trap,
# bash's default disposition kills the script and the EXIT trap still runs.
trap cleanup EXIT

worker() {
  local list=("$@") n=$# idx=$RANDOM
  while true; do
    local url=${list[$((idx % n))]}
    if [[ $direction == "down" ]]; then
      curl -fsS --max-time 30 -o /dev/null "$url" 2>/dev/null || return
    else
      dd if=/dev/zero bs=1M count=32 2>/dev/null \
        | curl -fsS --max-time 30 -o /dev/null -X POST --data-binary @- "$url" 2>/dev/null || return
    fi
    idx=$((idx + 1))
  done
}

# shellcheck disable=SC2086
for ((i = 0; i < parallel; i++)); do
  worker $urls &
  pids+=("$!")
done

counter="/sys/class/net/$iface/statistics/$([[ $direction == down ]] && echo rx_bytes || echo tx_bytes)"
before=$(cat "$counter")

# `sleep 1 &  wait` rather than a bare `sleep 1`: bash does not run a trap
# until the current foreground command finishes, so a TERM arriving mid-sleep
# sat for the rest of the second before cleanup even started. Backgrounding it
# and waiting makes the signal interrupt the wait immediately.
for ((s = 0; s < duration; s++)); do
  sleep 1 & wait $! 2>/dev/null || break
  after=$(cat "$counter")
  awk -v b="$before" -v a="$after" 'BEGIN {
    if (a < b) print "0.0"
    else { v = (a - b) * 8 / 1000000; if (v < 10) printf "%.1f\n", v; else printf "%.0f\n", v }
  }'
  before=$after
done
