#!/usr/bin/env bash
# Task G (bonus evidence) - run on Mac 2 while a client makes requests.
# Captures BOTH legs at the edge:
#   client -> nginx  on :HTTPS_PORT  (encrypted TLS)
#   nginx  -> backend on :3001/:3002 (plain HTTP - TLS was terminated here)
# Seeing the same request encrypted on one side and readable on the other is
# the clearest possible proof of "TLS termination at the edge".
#
#   scripts/capture-edge.sh [seconds]      default 20 s
set -uo pipefail
source "$(dirname "$0")/common.sh"

SECS="${1:-20}"; IFACE="${IFACE:-$(default_iface)}"
T="$(stamp)"; PCAP="$EVID/pcap/edge-both-legs-$T.pcap"; TXT="$EVID/text/edge-backend-leg-$T.txt"
FILTER="tcp port ${HTTPS_PORT} or tcp port ${BACKEND_A_PORT} or tcp port ${BACKEND_B_PORT}"
# If both backends live on this same Mac (2-Mac team) traffic goes over lo0
sudo -v
say "Capturing on $IFACE for ${SECS}s - make some requests from a client now (scripts/verify.sh lb)"
sudo tcpdump -i "$IFACE" -s 0 -U -w "$PCAP" "$FILTER" >/dev/null 2>&1 &
PID=$!; sleep "$SECS"; sudo kill -INT "$PID" 2>/dev/null; wait "$PID" 2>/dev/null   # (macOS has no `timeout`)
sudo chown "$RUN_USER" "$PCAP" 2>/dev/null || true
{
  echo "# Backend leg (nginx -> backends) is plain HTTP - readable:"
  tcpdump -nn -A -r "$PCAP" "tcp port ${BACKEND_A_PORT} or tcp port ${BACKEND_B_PORT}" 2>/dev/null \
    | grep -aE "IP |GET |HTTP/1.1 [0-9]|X-Backend|X-Forwarded-For|Host:" | head -60
} | tee "$TXT"
ok "pcap: $PCAP"; ok "text: $TXT"
echo "Wireshark: filter 'http' shows the backend leg in clear text; 'tls' shows the client leg encrypted."
