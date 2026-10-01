# Evidence

Everything here came out of real runs on our virtual LAN (4 hosts, 192.168.50.0/24), produced by the scripts in `scripts/` and `lab/`, on 1 Oct 2026. The evaluator should be able to find any item within 30 seconds.

| Folder | What | Produced by |
|---|---|---|
| `inventory/` | Each machine's hostname, interface, IP, mask, gateway, MAC address, routes, listening ports + the ping matrix from every machine | `scripts/inventory.sh`, `scripts/ping-matrix.sh` |
| `text/` | dig/nslookup, `curl -v`, 10-request load-balancing run, caching + 304, HTTP/1.1 vs HTTP/2, socket pair, openssl TLS details, cert creation, CA trust | `scripts/verify.sh`, `scripts/edge.sh certs`, `scripts/trust-ca.sh` |
| `pcap/` | Wireshark captures (see below) | `scripts/capture.sh`, `scripts/capture-edge.sh` |
| `screenshots/` | Wireshark, browser and terminal screenshots (see index) | taken from the running system |
| `failures/` | Output of the five failure scenarios | `scripts/failure-demo.sh` via `lab/run-failures.sh` |

## Captures (`pcap/`)

| File | Contents |
|---|---|
| `full-flow-tls1.2-mac4-backend-b-*.pcap` | One request from Mac 4: DNS query/answer → SYN/SYN-ACK/ACK → ClientHello → ServerHello, Certificate, ServerKeyExchange → ChangeCipherSpec → encrypted Application Data → FIN. TLS 1.2, so every handshake message is visible. |
| `full-flow-tls1.3-mac4-backend-b-*.pcap` | Same request with TLS 1.3. The Certificate is encrypted. Load `sslkeys-…084042.log` in Wireshark to decrypt the HTTP/2 inside. |
| `edge-both-legs-*.pcap` | Captured on Mac 2 during 10 requests: client↔edge on :443 (encrypted) and edge↔backends on :3001/:3002 (plain HTTP, `X-Forwarded-For`, `X-Backend`) |
| `sslkeys-*.log` | TLS session secrets written by curl (`SSLKEYLOGFILE`), for decrypting our own captures |

## Screenshot index (`screenshots/`)

| # | Shows | PDF item |
|---|---|---|
| 00 | Topology + IP/service map | Task A, Arch. doc |
| 01 | Wireshark: DNS query → answer 192.168.50.12, TTL 60, UDP 53 | Task G: DNS |
| 02 | Wireshark: SYN → SYN-ACK → ACK, port 53072 → 443 | Task G: TCP handshake |
| 03 | Wireshark: TCP stream with seq/ack numbers | Reliable data transfer |
| 04 | Wireshark: ClientHello (SNI app.team.test, ciphers, ALPN) | Task G: TLS |
| 05 | Wireshark: ServerHello + Certificate (subject app.team.test, issuer team Local Root CA) | Task G: TLS |
| 06 | Wireshark: ChangeCipherSpec | Task G: TLS |
| 07 | Wireshark: encrypted Application Data | Task G: HTTP encrypted |
| 08 | Wireshark flow graph of the whole request | Task G |
| 09 | Wireshark on Mac 2: edge→backend plain HTTP | TLS termination |
| 10 | TLS 1.3: certificate hidden inside encrypted records | TLS explanation |
| 11 | TLS 1.3 decrypted with key log: HTTP/2 headers | TLS explanation |
| 12, 13 | Browser: https://app.team.test, Backend B then A on refresh, no warning | Tasks D, E |
| 14, 15 | Browser: "Connection is secure", certificate viewer | Task E |
| 16 | Browser DevTools: 304 Not Modified, Cache-Control, ETag, X-Backend | Task F |
| 17 | `dig app.team.test` → 192.168.50.12 from SERVER 192.168.50.11#53 | Task B |
| 18 | Ping matrix: every machine reachable | Task A |
| 19 | `curl -v`: TLS handshake, certificate verify ok, HTTP/2, X-Backend | Tasks E, G |
| 20 | 10 requests alternating X-Backend A/B | Task D |
| 21 | `curl -I` 200 with Cache-Control/ETag, then 304 | Task F |
| 22 | nginx access log: client ip:port, TLS version, upstream chosen | Task D, ports |
| 23 | dnsmasq query log: queries from the clients | Task B |
| 24 | `openssl s_client`: chain, TLS 1.3, ALPN h2, verify return 0 | Task E |
| 25–29 | Failure scenarios F1–F5 | Section 6.3 |
