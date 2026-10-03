# Private Network Service Platform: CN Project, Phase 1

A client types `https://app.team.test`. **Our own DNS server** resolves the name. The connection then goes over **HTTPS to our own nginx edge**, and the edge **load-balances** the request across **two backend servers**. We captured every step of that journey with dig, curl, Wireshark and the browser, on two real MacBooks on the college Wi-Fi.

> The application stays simple. The network is the project.

## Team

**Team name:** team · **Section:** `<section>` · **Infrastructure:** `<Type N>`, two physical MacBooks on the same Wi-Fi, with the four roles combined (PDF section 3: *"Teams of 2–3 may combine machine roles"*)

| Enrollment no. | Name | Mac | Roles |
|---|---|---|---|
| `<enroll-no>` | Rishi Raj | Rishi's MacBook Pro, **10.7.16.15** | DNS server (dnsmasq), edge (nginx reverse proxy, TLS, load balancer), Backend A |
| `<enroll-no>` | Kaustubh Ranjan Mishra | Kaustubh's MacBook Pro, **10.7.3.40** | Backend B, test client (browser, curl, dig), Wireshark capture |

## Topology

```
          College Wi-Fi  10.7.0.0/19   (gateway 10.7.0.1)
  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │  Rishi's Mac  10.7.16.15                Kaustubh's Mac 10.7.3.40
  │  ┌──────────────────────────┐            ┌──────────────────────┐
  │  │ dnsmasq   :53  (Mac 1)   │◀── DNS ────│ client: browser/curl │
  │  │ nginx :80/:443 (Mac 2)   │◀── HTTPS ──│                      │
  │  │   ├─ HTTP ─▶ Backend A :3001 (Mac 3)  │                      │
  │  │   └─ HTTP ───────────────────────────▶│ Backend B :3002 (Mac 4)
  │  └──────────────────────────┘            └──────────────────────┘
  └──────────────────────────────────────────────────────────────┘
```

1. **DNS:** the client asks `10.7.16.15:53/UDP` for `app.team.test`. The answer is `10.7.16.15` (the edge), with TTL 60.
2. **HTTPS:** the client opens TCP to `10.7.16.15:443` and does the TLS handshake. The certificate is signed by our own CA.
3. **Load balancing:** nginx decrypts the request and forwards plain HTTP, in round robin, to Backend A `10.7.16.15:3001` or Backend B `10.7.3.40:3002`.

The PDF names the roles "Mac 1 to Mac 4". We kept those names in `team.env` (`MAC1_IP` … `MAC4_IP`). On a 2-Mac team, Mac 1, 2 and 3 share Rishi's IP and Mac 4 is Kaustubh's. Full diagrams, the IP table and the layer-by-layer flow are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Repository layout

```
team.env                  ← the ONLY config file: team id, the 2 IPs, which role runs where, ports
backend/server.py         ← the REST backend (stdlib Python, no installs)
dns/                      ← dnsmasq template + the exact config we ran (dnsmasq.conf.example)
edge/                     ← nginx template + the exact config we ran (nginx.conf.example)
tls/make-certs.sh         ← local CA + server certificate (OpenSSL); tls/out/*.crt = the public certs we used
scripts/                  ← one script per job (DNS, edge, backends, client setup, verify, capture, failures)
docs/                     ← architecture, TLS, caching, Wireshark guide, failures, demo video script, viva prep
evidence/                 ← everything from our real run: inventory, pcap, text output, 32 screenshots
```

## How to run it (two Macs)

**Before you start:** both Macs on the **same Wi-Fi**, the macOS firewall off, and Homebrew installed. Then `brew install dnsmasq nginx` on the server Mac. Wireshark goes on the client.
Put both IPs in `team.env` (`SERVER_IP`, `CLIENT_IP`). It must be identical on both Macs. Run everything from inside `cn-phase1`.

```bash
# both Macs - Task A
scripts/inventory.sh "Server Mac - DNS + Edge + Backend A"     # (client: "Client Mac - Backend B + client")
scripts/ping-matrix.sh

# Task C - the two backends. Each runs in its own terminal and stays open.
scripts/backend.sh run A          # server Mac, port 3001
scripts/backend.sh run B          # client Mac, port 3002
#   same thing without the script:  python3 backend/server.py --name A --port 3001

# server Mac - certificate + nginx edge (Tasks D, E), then DNS (Task B)
scripts/edge.sh certs             # prints the CA fingerprint
scripts/edge.sh start && scripts/edge.sh status
scripts/dns.sh start

# client Mac - use our DNS, trust our CA, verify everything
scripts/client-dns.sh use         # DNS = server Mac
scripts/trust-ca.sh               # compare the fingerprint, then trust (no -k needed after this)
scripts/verify.sh                 # dig, curl -v, load balancing, caching/304, HTTP/2, ports, TLS
scripts/capture.sh                # one full DNS→TCP→TLS→HTTP request into evidence/pcap/
scripts/failure-demo.sh 1         # … 5 : the five failure scenarios (section 6.3)

# client Mac - when finished, undo the DNS and CA changes
scripts/client-dns.sh restore && scripts/trust-ca.sh remove
```

## Backend API

| Endpoint | Response | Caching |
|---|---|---|
| `GET /` | HTML page saying which backend answered (A = blue, B = green) | `Cache-Control: no-store` |
| `GET /api/status` | `{"backend":"A","status":"ok", ...}` | `no-store` (live data) |
| `GET /api/info` | Same JSON on both backends | `Cache-Control: public, max-age=60` + `ETag`, answers `If-None-Match` with **304** |
| `GET /healthz` | `ok` | `no-store` |

Every response carries **`X-Backend: A`** or **`X-Backend: B`**.

## Phase 1 checklist (PDF section 6.2) → where the proof is

All screenshots are in [`evidence/screenshots/`](evidence/screenshots/). The index is in [evidence/README.md](evidence/README.md).

| Task | Config / code | Evidence |
|---|---|---|
| A: Private LAN | `team.env`, `scripts/inventory.sh`, `scripts/ping-matrix.sh` | `01`–`04` (both Macs: IP, /19 mask, gateway, MAC, ping matrix), `evidence/inventory/` |
| B: Private DNS | `dns/dnsmasq.conf.example`, `scripts/dns.sh`, `scripts/client-dns.sh` | `10` (answer from our server, `aa` flag, TTL 60), `11` (client uses our DNS: `SERVER: 10.7.16.15#53`), `20` (Wireshark) |
| C: Two backends | `backend/server.py`, `scripts/backend.sh` | `05`, `06` (A on :3001, B on :3002, requests from the edge with `X-Forwarded-For`) |
| D: Reverse proxy + LB | `edge/nginx.conf.example` (round robin + passive health check) | `08` (nginx on :80/:443, both backends reachable), `09`, `14` (A/B alternating), `15`, `16` (browser) |
| E: HTTPS / TLS | `tls/make-certs.sh`, `scripts/trust-ca.sh`, [docs/TLS.md](docs/TLS.md) | `07` (cert + SAN + CA fingerprint), `12` (client trusts CA, `verify_result=0`), `13` (`curl -v`, no `-k`), `17` (browser certificate), `23`–`26` (Wireshark) |
| F: HTTP caching | `/api/info` (Cache-Control + ETag), [docs/CACHING.md](docs/CACHING.md) | `18` (200 → 304 from both backends), `19` (DevTools 304) |
| G: Full protocol flow | `scripts/capture.sh`, [docs/WIRESHARK.md](docs/WIRESHARK.md) | `evidence/pcap/full-flow-tls1.2-*.pcap`, `20`–`27` (DNS → TCP → TLS → encrypted data, flow graph) |
| 6.3: Failure demos | `scripts/failure-demo.sh`, [docs/FAILURES.md](docs/FAILURES.md) | `28`–`32` |

Viva prep: [docs/VIVA.md](docs/VIVA.md). Demo video script: [docs/DEMO_VIDEO.md](docs/DEMO_VIDEO.md).
