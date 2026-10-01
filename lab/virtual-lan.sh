#!/usr/bin/env bash
# Type 3 infrastructure - builds the four "Macs" as virtual hosts on a virtual
# LAN, on any Linux machine/VM (needs root + iproute2).
#
#   lab/virtual-lan.sh up      create the LAN
#   lab/virtual-lan.sh down    tear it all down
#   lab/virtual-lan.sh show
#
# Each host is a Linux network namespace: its own network stack, its own
# interface (eth0), its own IP, MAC address, routing table, ports and
# /etc/resolv.conf - exactly what a separate machine has from the network's
# point of view. They are plugged into one virtual switch (Linux bridge
# "cnlan"); the bridge also holds the gateway address, playing the Wi-Fi
# router.
#
#          cnlan bridge = switch + router 192.168.50.1/24
#        ┌──────────┬──────────┬──────────┬──────────┐
#      mac1       mac2       mac3       mac4
#      .11 DNS    .12 edge   .13 A      .14 B
#
# Run a command "on" a machine with:   lab/on.sh mac2 <command...>
set -euo pipefail
source "$(dirname "$0")/../scripts/common.sh"

BR=cnlan
GW="${MAC1_IP%.*}.1"
HOSTS=(mac1 mac2 mac3 mac4)
IPS=("$MAC1_IP" "$MAC2_IP" "$MAC3_IP" "$MAC4_IP")

hostname_for() { case "$1" in mac1) echo mac1-dns;; mac2) echo mac2-edge;; mac3) echo mac3-backend-a;; mac4) echo mac4-backend-b;; esac; }

up() {
  ip link show "$BR" >/dev/null 2>&1 || {
    run ip link add "$BR" type bridge
    run ip addr add "$GW/24" dev "$BR"
    run ip link set "$BR" up
  }
  for i in 0 1 2 3; do
    local h="${HOSTS[$i]}" ip="${IPS[$i]}" n=$((i + 1))
    ip netns list | grep -qw "$h" && continue
    run ip netns add "$h"
    run ip link add "veth-$h" type veth peer name eth0 netns "$h"
    run ip link set "veth-$h" master "$BR" up
    run ip -n "$h" link set eth0 address "02:42:c0:a8:32:1$n"
    run ip -n "$h" addr add "$ip/24" dev eth0
    run ip -n "$h" link set eth0 up
    run ip -n "$h" link set lo up
    run ip -n "$h" route add default via "$GW"
    mkdir -p "/etc/netns/$h"
    # resolver of each machine; clients get pointed at Mac 1 later by client-dns.sh
    echo "nameserver $GW" > "/etc/netns/$h/resolv.conf"
    printf '127.0.0.1 localhost\n127.0.1.1 %s\n' "$(hostname_for "$h")" > "/etc/netns/$h/hosts"
  done
  # bridged frames must not be filtered by the host firewall
  sysctl -qw net.bridge.bridge-nf-call-iptables=0 2>/dev/null || true
  ok "virtual LAN up"; show
}

down() {
  for h in "${HOSTS[@]}"; do ip netns del "$h" 2>/dev/null || true; rm -rf "/etc/netns/$h"; done
  ip link del "$BR" 2>/dev/null || true
  ok "virtual LAN removed"
}

show() {
  printf '%-6s %-10s %-16s %-19s %s\n' HOST IFACE IPV4 MAC GATEWAY
  for h in "${HOSTS[@]}"; do
    ip netns list | grep -qw "$h" || continue
    printf '%-6s %-10s %-16s %-19s %s\n' "$h" eth0 \
      "$(ip -n "$h" -4 -o addr show eth0 | awk '{print $4}')" \
      "$(ip -n "$h" link show eth0 | awk '/ether/{print $2}')" \
      "$(ip -n "$h" route show default | awk '{print $3}')"
  done
}

case "${1:-}" in up) up ;; down) down ;; show) show ;; *) sed -n '2,8p' "$0"; exit 1 ;; esac
