# Private Network Service Platform: CN Project, Phase 1

A client types `https://app.team.test`. The name gets resolved by **our own DNS server**, the connection goes over **HTTPS to our own nginx edge**, and the edge **load-balances** the request across **two backend servers**. Every step of that journey is captured with dig, curl, Wireshark and the browser.

> The application stays simple. The network is the project.

## Team

**Team name:** team · **Section:** `<section>` · **Infrastructure:** Type 3, virtual machines (4 virtual hosts on one virtual LAN)

| Enrollment no. | Name | Role |
|---|---|---|
| `<enroll-no>` | Rishi Raj | Edge: nginx, TLS, load balancer (Mac 2) |
| `<enroll-no>` | `<name>` | DNS server: dnsmasq (Mac 1) |
| `<enroll-no>` | `<name>` | Backend A (Mac 3) |
| `<enroll-no>` | `<name>` | Backend B + client (Mac 4) |
| `<enroll-no>` | `<name>` | Packet capture, evidence + documentation |

## Topology

![topology](docs/topology.png)

```
 Client (Mac 1 or Mac 4)            all four hosts on the virtual LAN 192.168.50.0/24
   │
   │ 1. DNS query   UDP 53  ─────▶  Mac 1  dnsmasq    192.168.50.11   "app.team.test is 192.168.50.12"
   │
   │ 2. HTTPS       TCP 443 ─────▶  Mac 2  nginx      192.168.50.12   TLS ends here, round-robin LB
                                       ├── HTTP :3001 ──▶ Mac 3  Backend A   192.168.50.13
                                       └── HTTP :3002 ──▶ Mac 4  Backend B   192.168.50.14
```

Full diagrams, the IP table and the layer-by-layer request flow are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### Our infrastructure (Type 3)

`lab/virtual-lan.sh up` creates the four machines as **virtual hosts**. Each one is an isolated Linux network namespace with its own `eth0`, IP address, MAC address, routing table, open ports and `/etc/resolv.conf`. They connect through one virtual switch (Linux bridge `cnlan`, gateway 192.168.50.1). From the network's point of view these are four separate computers on one LAN. Traffic between them is real Ethernet/IP/TCP that tcpdump and Wireshark capture like any other.

`lab/on.sh <mac1|mac2|mac3|mac4> <command>` runs a command on one of the machines, under that machine's own hostname (`mac1-dns`, `mac2-edge`, `mac3-backend-a`, `mac4-backend-b`).

The scripts in `scripts/` are the same ones you'd run on four physical Macs (Type 1). They detect macOS vs Linux and use `networksetup`/keychain on a Mac and `/etc/resolv.conf`/system CA store on Linux.

## Repository layout

```
team.env                  ← the ONLY config file: team id + the 4 IPs + ports
backend/server.py         ← the REST backend (stdlib Python, no installs)
dns/                      ← dnsmasq template (+ the exact config we ran, .example)
edge/                     ← nginx template (+ the exact config we ran, .example)
tls/make-certs.sh         ← local CA + server certificate (OpenSSL)
scripts/                  ← one script per job (setup, verify, capture, failures)
lab/                      ← Type 3 virtual LAN: create hosts, run commands on them, failure driver
docs/                     ← architecture, TLS, caching, Wireshark guide, failures, demo script, viva prep
evidence/                 ← everything we captured: inventory, pcaps, text output, screenshots, failures
```

## How to run the backends (and everything else)

Requirements: Linux with root (`iproute2`, `nginx`, `dnsmasq`, `python3`, `openssl`, `dnsutils`, `tcpdump`; Wireshark for viewing captures).
On Ubuntu: `sudo apt install nginx dnsmasq dnsutils tcpdump iputils-ping netcat-openbsd wireshark`

```bash
# 0. the virtual LAN (Task A)
sudo lab/virtual-lan.sh up
for h in mac1 mac2 mac3 mac4; do sudo lab/on.sh $h scripts/inventory.sh "$h"; sudo lab/on.sh $h scripts/ping-matrix.sh; done

# 1. backends (Task C)  - Backend A on Mac 3 :3001, Backend B on Mac 4 :3002
sudo lab/on.sh mac3 scripts/backend.sh start A      # or: scripts/backend.sh run A  (foreground)
sudo lab/on.sh mac4 scripts/backend.sh start B
#    plain python works too:  python3 backend/server.py --name A --port 3001

# 2. edge: certificates + nginx (Tasks D, E)
sudo lab/on.sh mac2 scripts/edge.sh certs
sudo lab/on.sh mac2 scripts/edge.sh start

# 3. DNS (Task B)
sudo lab/on.sh mac1 scripts/dns.sh start

# 4. clients use Mac 1 for DNS and trust the team CA
sudo lab/on.sh mac1 scripts/client-dns.sh use
sudo lab/on.sh mac4 scripts/client-dns.sh use
sudo lab/on.sh mac4 scripts/trust-ca.sh

# 5. evidence (Tasks B, D, E, F, G) + failure demos (6.3)
sudo lab/on.sh mac4 scripts/verify.sh          # dig, curl -v, load balancing, caching/304, HTTP/2, ports, TLS
sudo lab/on.sh mac4 scripts/capture.sh         # one full DNS→TCP→TLS→HTTP request into a pcap
sudo lab/on.sh mac2 scripts/capture-edge.sh 20 # both legs at the edge (run verify.sh lb meanwhile)
sudo lab/run-failures.sh                       # all five failure scenarios

# tear down
sudo lab/virtual-lan.sh down
```

**On real Macs (Type 1/2)** skip `lab/`. Put each Mac's IP in `team.env`, then run the same `scripts/...` commands directly on the right Mac (`brew install nginx dnsmasq` first). For 2–3 Macs, reuse IPs in `team.env`.

## Backend API

| Endpoint | Response | Caching |
|---|---|---|
| `GET /` | HTML page saying which backend answered (A = blue, B = green) | `Cache-Control: no-store` |
| `GET /api/status` | `{"backend":"A","status":"ok", ...}` | `no-store` (live data) |
| `GET /api/info` | Same JSON on both backends | `Cache-Control: public, max-age=60` + `ETag`, answers `If-None-Match` with **304** |
| `GET /healthz` | `ok` | `no-store` |

Every response carries **`X-Backend: A`** or **`X-Backend: B`**.

## Phase 1 checklist (PDF section 6.2) → where the proof is

| Task | Config / code | Evidence |
|---|---|---|
| A: Private LAN | `lab/virtual-lan.sh`, `scripts/inventory.sh`, `scripts/ping-matrix.sh` | `evidence/inventory/`, `screenshots/00-topology.png`, `18-terminal-ping-matrix.png` |
| B: Private DNS | `dns/dnsmasq.conf.example`, `scripts/dns.sh`, `scripts/client-dns.sh` | `screenshots/17-terminal-dig-app.png`, `23-terminal-dnsmasq-query-log.png`, `01-dns-query-response.png` |
| C: Two backends | `backend/server.py`, `scripts/backend.sh` | `evidence/text/verify-*-all.txt`, `screenshots/12/13-browser-*.png` |
| D: Reverse proxy + LB | `edge/nginx.conf.example` (round robin + passive health check) | `screenshots/20-terminal-load-balancing.png`, `22-terminal-nginx-access-log.png` |
| E: HTTPS / TLS | `tls/make-certs.sh`, `scripts/trust-ca.sh`, [docs/TLS.md](docs/TLS.md) | `screenshots/14/15-browser-*.png`, `19-terminal-curl-v-https.png`, `24-terminal-tls-openssl.png`, `04–07` |
| F: HTTP caching | `/api/info` (Cache-Control + ETag), [docs/CACHING.md](docs/CACHING.md) | `screenshots/21-terminal-cache-304.png`, `16-browser-devtools-304-cache-headers.png` |
| G: Full protocol flow | `scripts/capture.sh`, `scripts/capture-edge.sh`, [docs/WIRESHARK.md](docs/WIRESHARK.md) | `evidence/pcap/*.pcap`, `screenshots/01–11` |
| 6.3: Failure demos | `scripts/failure-demo.sh`, `lab/run-failures.sh`, [docs/FAILURES.md](docs/FAILURES.md) | `evidence/failures/`, `screenshots/25–29` |

Viva prep: [docs/VIVA.md](docs/VIVA.md).
