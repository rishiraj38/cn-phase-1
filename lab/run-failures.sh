#!/usr/bin/env bash
# Virtual lab only: runs scripts/failure-demo.sh on the client (mac4) and does
# the "go break something on another machine" steps for you at each prompt.
#   lab/run-failures.sh            all five
#   lab/run-failures.sh 2 4        just F2 and F4
set -uo pipefail
cd "$(dirname "$0")/.."
ON=lab/on.sh

drive() {   # drive <scenario> <action-for-prompt-1> <action-for-prompt-2> ...
  local n="$1"; shift
  local fifo log; fifo="$(mktemp -u)"; log="$(mktemp)"; mkfifo "$fifo"
  $ON mac4 scripts/failure-demo.sh "$n" <"$fifo" >"$log" 2>&1 &
  local pid=$!; exec 3>"$fifo"
  local k=0 action
  for action in "$@"; do
    k=$((k + 1))
    until [ "$(grep -c '>>>' "$log")" -ge "$k" ] || ! kill -0 "$pid" 2>/dev/null; do sleep 0.3; done
    echo "    [lab] $action" >>"$log"
    bash -c "$action" >/dev/null 2>&1
    sleep 1; echo >&3
  done
  wait "$pid"; exec 3>&-; rm -f "$fifo"
  sed 's/\x1b\[[0-9;]*m//g' "$log"; rm -f "$log"
}

for n in ${*:-1 5 2 3 4}; do
  case "$n" in
    1|5) drive "$n" ;;
    2) drive 2 "$ON mac1 scripts/dns.sh wrong-record" "$ON mac1 scripts/dns.sh fix" ;;
    3) drive 3 "$ON mac3 scripts/backend.sh stop A" ;;
    4) drive 4 "$ON mac4 scripts/backend.sh stop B" \
               "$ON mac3 scripts/backend.sh start A; $ON mac4 scripts/backend.sh start B" ;;
  esac
done
sed -i 's/\x1b\[[0-9;]*m//g' evidence/failures/*.txt 2>/dev/null || true
