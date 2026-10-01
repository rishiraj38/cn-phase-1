#!/usr/bin/env bash
# Task A - prove every machine can reach every other one.  Run on EVERY Mac.
# Saves evidence/inventory/ping-<hostname>.txt
set -uo pipefail
source "$(dirname "$0")/common.sh"

OUT="$EVID/inventory/ping-$(host_tag).txt"
{
  echo "# Ping matrix from $(host_tag) - $(date)"
  for pair in "Mac1:$MAC1_IP" "Mac2:$MAC2_IP" "Mac3:$MAC3_IP" "Mac4:$MAC4_IP"; do
    name="${pair%%:*}"; ip="${pair#*:}"
    echo; echo "## $name ($ip)"
    if is_mac; then W=1000; else W=1; fi      # -W is ms on macOS, seconds on Linux
    if ping -c 3 -W "$W" "$ip" >/tmp/ping.$$ 2>&1; then
      tail -2 /tmp/ping.$$; echo "RESULT: $name reachable"
    else
      tail -3 /tmp/ping.$$; echo "RESULT: $name UNREACHABLE"
    fi
  done
  rm -f /tmp/ping.$$
} | tee "$OUT"
echo; ok "saved $OUT"
