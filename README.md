# Private Network Service Platform: CN Project, Phase 1

A client types `https://app.teamx.test`. The name gets resolved by **our own DNS server**, the connection goes over **HTTPS to our own nginx edge**, and the edge **load-balances** the request across **two backend servers**. Every step of that journey is captured with dig, curl and Wireshark.

> The application stays simple. The network is the project.

## Team

| Enrollment no. | Name | Machine / role |
|---|---|---|
| `<enroll-no>` | Rishi Raj | Mac 2: Edge (nginx, TLS, load balancer) |
| `<enroll-no>` | `<name>` | Mac 1: DNS server (dnsmasq) + test client |
| `<enroll-no>` | `<name>` | Mac 3: Backend A |
| `<enroll-no>` | `<name>` | Mac 4: Backend B + test client |

**Team name:** `<team name / number>` · **Infrastructure:** Type 1, four macOS laptops on the same LAN

## Topology

```
 Client (Mac 1 or Mac 4)            all four Macs on the same Wi-Fi / LAN
   │
   │ 1. DNS query   UDP 53  ─────▶  Mac 1  dnsmasq    "app.teamx.test is Mac 2"
   │
   │ 2. HTTPS       TCP 443 ─────▶  Mac 2  nginx      TLS ends here, round-robin LB
                                       ├── HTTP :3001 ──▶ Mac 3  Backend A
                                       └── HTTP :3002 ──▶ Mac 4  Backend B
```

Full diagrams, the IP table and the layer-by-layer request flow are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Repository layout

```
team.env                  ← the ONLY file you edit: team id + the 4 IPs
backend/server.py         ← the REST backend (stdlib Python, no installs)
dns/dnsmasq.conf.template ← Mac 1 DNS config
edge/nginx.conf.template  ← Mac 2 reverse proxy + load balancer + TLS
tls/make-certs.sh         ← local CA + server certificate (OpenSSL)
scripts/                  ← one script per job, see below
docs/                     ← architecture, setup, Wireshark guide, failures, demo script, viva prep
evidence/                 ← everything we captured (inventory, pcaps, text, screenshots, failures)
```

## How to run it

Everything is driven by `team.env`. Fill in the IPs once, commit, and `git pull` on every Mac.

**Requirements:** macOS, Homebrew. `brew install nginx dnsmasq` (only on Mac 1 / Mac 2), plus Wireshark on the client used for captures (`brew install --cask wireshark`). Python 3 comes with the Xcode command line tools.

### Step 0: on every Mac
```bash
git clone <this repo> ~/cn-phase1 && cd ~/cn-phase1
scripts/inventory.sh "Mac N - <role>"   # records IP, mask, gateway, interface, MAC
```
Put the four IPs into `team.env`, commit, push, then `git pull` everywhere.
```bash
scripts/ping-matrix.sh                    # every Mac pings every other Mac
```

### Mac 3 and Mac 4: the backends
```bash
scripts/backend.sh run A      # on Mac 3 → listens on 0.0.0.0:3001
scripts/backend.sh run B      # on Mac 4 → listens on 0.0.0.0:3002
```
`run` keeps it in the foreground so you can see each request arrive. Use `start`/`stop`/`status` to run it in the background.
Or run it directly with `python3 backend/server.py --name A --port 3001`.

### Mac 2: the edge
```bash
scripts/edge.sh certs         # local CA + cert for app/api.teamx.test, prints CA fingerprint
scripts/edge.sh start         # renders edge/out/nginx.conf, nginx -t, starts nginx on 80 + 443
scripts/edge.sh status        # checks that both backends are reachable from the edge
scripts/edge.sh logs          # live access log: shows upstream=<backend> for every request
```

### Mac 1: DNS
```bash
scripts/dns.sh start          # dnsmasq on UDP/TCP 53: app/api.teamx.test → Mac 2
scripts/dns.sh status
scripts/dns.sh logs           # live query log
```

### Client Macs (Mac 1 and Mac 4)
```bash
scripts/client-dns.sh use     # DNS = Mac 1 (same as System Settings → Network → DNS)
scripts/trust-ca.sh           # download CA from the edge, compare fingerprint, add to keychain
scripts/verify.sh             # DNS, HTTPS, load balancing, caching, HTTP/2, ports, TLS → evidence/text/
scripts/capture.sh            # one full DNS→TCP→TLS→HTTP request → evidence/pcap/*.pcap
scripts/failure-demo.sh all   # the five required failure scenarios → evidence/failures/
```
Then open `https://app.teamx.test` in Safari or Chrome. There's no warning, the padlock shows, and refreshing alternates between Backend A (blue) and Backend B (green).

When you're done: `scripts/client-dns.sh restore`.

Port 443/80 blocked? Set `HTTPS_PORT=8443` and `HTTP_PORT=8080` in `team.env`; everything else adapts on its own.
Only 2 or 3 Macs? Reuse IPs in `team.env` (e.g. `MAC4_IP=$MAC3_IP`). Both backends can run on one Mac because they use different ports.

## Backend API

| Endpoint | Response | Caching |
|---|---|---|
| `GET /` | HTML page saying which backend answered | `Cache-Control: no-store` |
| `GET /api/status` | `{"backend":"A","status":"ok", ...}` | `no-store` (live data) |
| `GET /api/info` | Same JSON on both backends | `Cache-Control: public, max-age=60` + `ETag`, answers `If-None-Match` with **304** |
| `GET /healthz` | `ok` | `no-store` |

Every response carries **`X-Backend: A`** or **`X-Backend: B`**.

## Phase 1 checklist (PDF section 6.2)

| Task | Where |
|---|---|
| A: Private LAN | `scripts/inventory.sh`, `scripts/ping-matrix.sh` → `evidence/inventory/`, topology in `docs/ARCHITECTURE.md` |
| B: Private DNS | `dns/dnsmasq.conf.template`, `scripts/dns.sh`, `scripts/client-dns.sh`, `verify.sh dns` |
| C: Two backends | `backend/server.py`, `scripts/backend.sh` |
| D: Reverse proxy + LB | `edge/nginx.conf.template` (round robin + passive health check), `verify.sh lb` |
| E: HTTPS / TLS | `tls/make-certs.sh`, `scripts/trust-ca.sh`, `verify.sh https tls`, `docs/TLS.md` |
| F: HTTP caching | `/api/info` with Cache-Control + ETag → 304, `verify.sh cache`, `docs/CACHING.md` |
| G: Full protocol flow | `scripts/capture.sh`, `scripts/capture-edge.sh`, `docs/WIRESHARK.md` |
| 6.3: Failure demos | `scripts/failure-demo.sh`, `docs/FAILURES.md` |
