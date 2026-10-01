#!/usr/bin/env bash
# Run ONCE on Mac 2 before the real 4-Mac run: removes the evidence, certs and
# runtime files from our earlier virtual-lab run so nothing old gets mixed in.
#   scripts/fresh-start.sh
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -p "Delete old evidence/, tls/out/ and runtime/ ? [y/N] " yn
[ "$yn" = "y" ] || [ "$yn" = "Y" ] || exit 1
git rm -rq --ignore-unmatch evidence/inventory evidence/text evidence/pcap evidence/failures evidence/screenshots tls/out dns/dnsmasq.conf.example edge/nginx.conf.example >/dev/null || true
rm -rf evidence/inventory evidence/text evidence/pcap evidence/failures evidence/screenshots tls/out runtime dns/out edge/out
mkdir -p evidence/{inventory,pcap,screenshots,text,failures}
for d in inventory pcap screenshots text failures; do touch "evidence/$d/.gitkeep"; done
echo "Clean. Now edit team.env (your 4 real IPs), commit and push:"
echo '  git add -A && git commit -m "Start real 4-Mac run" && git push'
