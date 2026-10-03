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
# A backend on THIS Mac (2-Mac team: Backend A sits on the edge Mac) is reached
# over the loopback interface, not Wi-Fi - so capture lo0 as well and merge.
LO=""; for b in "$MAC3_IP" "$MAC4_IP"; do [ "$b" = "$MAC2_IP" ] && LO="$(is_mac && echo lo0 || echo lo)"; done
sudo -v
say "Capturing on $IFACE${LO:+ + $LO} for ${SECS}s - make some requests from a client now (scripts/verify.sh lb)"
sudo tcpdump -i "$IFACE" -s 0 -U -w "$PCAP.wifi" "$FILTER" >/dev/null 2>&1 &
PID=$!; PID2=""
if [ -n "$LO" ]; then
  sudo tcpdump -i "$LO" -s 0 -U -w "$PCAP.lo" "tcp port ${BACKEND_A_PORT} or tcp port ${BACKEND_B_PORT}" >/dev/null 2>&1 &
  PID2=$!
fi
sleep "$SECS"; sudo kill -INT $PID $PID2 2>/dev/null; wait $PID $PID2 2>/dev/null   # (macOS has no `timeout`)
MERGECAP="$(command -v mergecap || ls /Applications/Wireshark.app/Contents/MacOS/mergecap 2>/dev/null || true)"
if [ -n "$LO" ] && [ -n "$MERGECAP" ]; then
  sudo "$MERGECAP" -F pcapng -w "$PCAP" "$PCAP.wifi" "$PCAP.lo" && sudo rm -f "$PCAP.wifi" "$PCAP.lo"
elif [ -n "$LO" ]; then
  sudo mv "$PCAP.wifi" "$PCAP"; sudo mv "$PCAP.lo" "${PCAP%.pcap}-loopback.pcap"
  sudo chown "$RUN_USER" "${PCAP%.pcap}-loopback.pcap" 2>/dev/null || true
  warn "no mergecap - Backend A leg is in ${PCAP%.pcap}-loopback.pcap"
else
  sudo mv "$PCAP.wifi" "$PCAP"
fi
sudo chown "$RUN_USER" "$PCAP" 2>/dev/null || true
{
  echo "# Backend leg (nginx -> backends) is plain HTTP - readable:"
  for f in "$PCAP" "${PCAP%.pcap}-loopback.pcap"; do [ -f "$f" ] && tcpdump -nn -A -r "$f" "tcp port ${BACKEND_A_PORT} or tcp port ${BACKEND_B_PORT}" 2>/dev/null; done \
    | grep -aE "IP |GET |HTTP/1.1 [0-9]|X-Backend|X-Forwarded-For|Host:" | head -60
} | tee "$TXT"
ok "pcap: $PCAP"; ok "text: $TXT"
echo "Wireshark: filter 'http' shows the backend leg in clear text; 'tls' shows the client leg encrypted."
