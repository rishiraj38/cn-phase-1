#!/usr/bin/env bash
# Task B - point a client Mac at the team DNS server (Mac 1).
# Same thing as System Settings -> Network -> <Wi-Fi> -> Details -> DNS.
#
#   scripts/client-dns.sh use        DNS = Mac 1   (saves your old setting first)
#   scripts/client-dns.sh set <ip>   DNS = any IP  (used by the failure demo)
#   scripts/client-dns.sh restore    put back what you had before
#   scripts/client-dns.sh show
set -euo pipefail
source "$(dirname "$0")/common.sh"
is_mac || die "this script uses macOS networksetup"

IFACE="$(default_iface)"; SVC="$(mac_service_for_iface "$IFACE")"
[ -n "$SVC" ] || die "could not find the network service for $IFACE"
BACKUP="$RUNTIME/dns-backup-$(echo "$SVC" | tr ' /' '__').txt"

current() { networksetup -getdnsservers "$SVC" | grep -E '^[0-9a-fA-F:.]+$' || true; }
apply() {
  [ -f "$BACKUP" ] || { current > "$BACKUP"; ok "saved previous DNS ($(tr '\n' ' ' < "$BACKUP")) to $BACKUP"; }
  run sudo networksetup -setdnsservers "$SVC" "$@"
  flush_dns_cache
  show
}
show() {
  say "DNS servers for \"$SVC\" ($IFACE):"; networksetup -getdnsservers "$SVC"
  say "What the resolver is actually using:"; scutil --dns | awk '/resolver #1/,/^$/' | grep -E "nameserver|search" || true
}

case "${1:-}" in
  use)     apply "$MAC1_IP" ;;
  set)     [ -n "${2:-}" ] || die "usage: $0 set <ip>"; apply "$2" ;;
  restore) if [ -s "$BACKUP" ]; then run sudo networksetup -setdnsservers "$SVC" $(cat "$BACKUP")
           else run sudo networksetup -setdnsservers "$SVC" empty; fi
           rm -f "$BACKUP"; flush_dns_cache; show ;;
  show)    show ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
