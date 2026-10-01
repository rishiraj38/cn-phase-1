#!/usr/bin/env bash
# Run a command on one of the virtual machines, with its own hostname.
#   lab/on.sh mac4 scripts/verify.sh
#   lab/on.sh mac2 bash          # interactive shell "on" Mac 2
set -euo pipefail
h="$1"; shift
case "$h" in
  mac1) name="mac1-dns" ;; mac2) name="mac2-edge" ;;
  mac3) name="mac3-backend-a" ;; mac4) name="mac4-backend-b" ;;
  *) echo "usage: $0 mac1|mac2|mac3|mac4 <command...>" >&2; exit 1 ;;
esac
cd "$(dirname "$0")/.."
# own network namespace (= own NIC, IP, ports, resolv.conf) + own hostname
exec ip netns exec "$h" unshare --uts bash -c 'hostname "$0"; export PS1="[$0] \w \$ "; exec "$@"' "$name" "$@"
