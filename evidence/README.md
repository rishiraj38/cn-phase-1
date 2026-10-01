# Evidence

Everything here is produced by the scripts on our real machines. The evaluator should be able to find any item within 30 seconds.

| Folder | What | Produced by |
|---|---|---|
| `inventory/` | Each Mac's IP, mask, gateway, interface, MAC address + the ping matrix (Task A) | `scripts/inventory.sh`, `scripts/ping-matrix.sh` |
| `text/` | dig / nslookup, `curl -v` headers, load-balancing run, caching + 304, HTTP/2, ports, TLS details (Tasks B, D, E, F) | `scripts/verify.sh` |
| `pcap/` | Wireshark captures: one full DNS → TCP → TLS → HTTP request from a client, plus both legs at the edge (Task G) | `scripts/capture.sh`, `scripts/capture-edge.sh` |
| `screenshots/` | Wireshark + browser screenshots, named as in `docs/WIRESHARK.md` | by hand |
| `failures/` | The five failure scenarios (section 6.3) | `scripts/failure-demo.sh` |

## Index

| Requirement | File |
|---|---|
| Topology diagram | `../docs/ARCHITECTURE.md` |
| IP table | `inventory/*.txt` |
| Ping between all machines | `inventory/ping-*.txt` |
| dig app.teamx.test → Mac 2 | `text/verify-*-all.txt` (section B) · `screenshots/01-dns.png` |
| HTTPS by name, no cert warning | `text/verify-*-all.txt` (section E) · `screenshots/10-browser-padlock.png` |
| X-Backend A/B alternating | `text/verify-*-all.txt` (section D) |
| Cache-Control + 304 | `text/verify-*-all.txt` (section F) |
| TCP handshake, TLS handshake | `pcap/full-flow-*.pcap` · `screenshots/02…08` |
| Failure scenarios | `failures/F1…F5-*.txt` |
