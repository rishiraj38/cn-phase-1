#!/usr/bin/env bash
# Run ONCE on Mac 2 before the real 4-Mac run. It:
#   - removes the evidence, certificates and runtime files from the earlier virtual-lab run
#   - switches README / docs from "Type 3 virtual" to "Type 1, four Macs"
#   - blanks the IP table and the observed failure results, ready to fill in
#   scripts/fresh-start.sh
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -p "Delete old evidence and switch the docs to the real 4-Mac run? [y/N] " yn
[ "$yn" = "y" ] || [ "$yn" = "Y" ] || exit 1

git rm -rq --ignore-unmatch evidence/inventory evidence/text evidence/pcap evidence/failures evidence/screenshots \
  tls/out dns/dnsmasq.conf.example edge/nginx.conf.example docs/topology.png >/dev/null || true
rm -rf evidence/inventory evidence/text evidence/pcap evidence/failures evidence/screenshots tls/out runtime dns/out edge/out docs/topology.png
mkdir -p evidence/{inventory,pcap,screenshots,text,failures}
for d in inventory pcap screenshots text failures; do touch "evidence/$d/.gitkeep"; done

python3 - <<'PY'
import re
def edit(p, f):
    s = open(p).read(); s2 = f(s); open(p, "w").write(s2)

def readme(s):
    s = s.replace("**Infrastructure:** Type 3, virtual machines (4 virtual hosts on one virtual LAN)",
                  "**Infrastructure:** Type 1, four macOS laptops on the same Wi-Fi")
    s = s.replace("![topology](docs/topology.png)\n\n", "")
    s = re.sub(r"### Our infrastructure \(Type 3\).*?(?=## Repository layout)", "", s, flags=re.S)
    s = s.replace("lab/                      ← Type 3 virtual LAN: create hosts, run commands on them, failure driver\n", "")
    s = s.replace("all four hosts on the virtual LAN 192.168.50.0/24", "all four Macs on the same Wi-Fi")
    s = re.sub(r"192\.168\.50\.1[1-4]", "<IP>", s)
    s = s.replace("`lab/virtual-lan.sh`, ", "").replace("`screenshots/00-topology.png`, ", "")
    s = s.replace(", `lab/run-failures.sh`", "")
    run = """## How to run it (four Macs)

Install once: `xcode-select --install`, Homebrew, then `brew install dnsmasq` (Mac 1) and `brew install nginx` (Mac 2); Wireshark on Mac 2 and Mac 4.
Put the four IPs in `team.env`, then on each Mac (inside `~/cn-phase1`):

```bash
# every Mac (Task A)
scripts/inventory.sh "Mac N - role" && scripts/ping-matrix.sh

# Mac 3 / Mac 4 - the backends (Task C). The code is backend/server.py
scripts/backend.sh run A          # Mac 3, port 3001
scripts/backend.sh run B          # Mac 4, port 3002
#   same thing without the script: python3 backend/server.py --name A --port 3001

# Mac 2 - certificate + nginx edge (Tasks D, E)
scripts/edge.sh certs && scripts/edge.sh start && scripts/edge.sh status

# Mac 1 - DNS server (Task B)
scripts/dns.sh start

# Mac 1 and Mac 4 - clients
scripts/client-dns.sh use         # DNS = Mac 1
scripts/trust-ca.sh               # trust the team CA (no -k needed after this)
scripts/verify.sh                 # dig, curl -v, load balancing, caching/304, ports, TLS
scripts/failure-demo.sh 1         # ... 5: the failure scenarios

# when finished (Mac 1 and Mac 4)
scripts/client-dns.sh restore && scripts/trust-ca.sh remove
```

"""
    s = re.sub(r"## How to run the backends \(and everything else\).*?(?=## Backend API)", lambda m: run, s, flags=re.S)
    return s
edit("README.md", readme)

def arch(s):
    s = s.replace("![topology](topology.png)\n\n", "")
    s = re.sub(r"\*\*Infrastructure: Type 3 \(virtual machines\)\.\*\*.*?\n\n", "**Infrastructure: Type 1.** Four physical MacBooks on one Wi-Fi network.\n\n", s, flags=re.S)
    s = s.replace('R(("virtual switch cnlan<br/>gateway 192.168.50.1"))', 'R(("Wi-Fi router<br/>default gateway"))')
    s = re.sub(r"(\| Mac \d: [^|]+\|) [^|]+\| eth0 \| [^|]+\| [^|]+\| [^|]+\| [^|]+\|",
               r"\1  | en0 |  |  |  |  |", s)
    s = s.replace("192.168.50.0/24", "our Wi-Fi subnet")
    return s
edit("docs/ARCHITECTURE.md", arch)

def fail(s):
    i = s.find("## Observed results")
    if i < 0: return s
    return s[:i] + """## Observed results (our run, client = Mac 4)

| # | Observed | Evidence |
|---|---|---|
| F1 |  | `evidence/failures/F1-*.txt`, `screenshots/25-failure-F1-wrong-dns-server.png` |
| F2 |  | `evidence/failures/F2-*.txt`, `screenshots/26-failure-F2-wrong-dns-record.png` |
| F3 |  | `evidence/failures/F3-*.txt`, `screenshots/27-failure-F3-one-backend-down.png` |
| F4 |  | `evidence/failures/F4-*.txt`, `screenshots/28-failure-F4-both-backends-down.png` |
| F5 |  | `evidence/failures/F5-*.txt`, `screenshots/29-failure-F5-wrong-port.png` |
"""
edit("docs/FAILURES.md", fail)
PY

echo "Clean. Now:"
echo "  1) after the IPs are known: put them in team.env"
echo '  2) git add -A && git commit -m "Start real 4-Mac run" && git push'
