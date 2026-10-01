# Phase 1 Demo Video: Recording Script (5:00 max)

**File name:** `CN_Phase1_<Section><TeamName><InfraType>.mp4`, e.g. `CN_Phase1_A_TeamX_Type1.mp4`
**Limits:** ≤ 5 min, ≤ 500 MB, 1080p .mp4. Drive → Share → *Anyone with the link can view*. Test the link in an incognito window.

**Recording setup:** QuickTime → File → New Screen Recording (or ⌘⇧5) on the client Mac. Bump the Terminal font to 18pt+ (⌘+) so text is readable at 1080p. Before you hit record, have these open in tabs:
Terminal (client), Terminal SSH'd into or screen-shared from Mac 2 (`scripts/edge.sh logs`), browser, Wireshark with the saved pcap, `docs/ARCHITECTURE.md` on GitHub.

Do a full dry run first. Everything must already be **running** when you start recording. Setup is *explained*, not performed live.

---

## Part 1: Team intro + setup flow (0:00 – 2:00)

| Time | Show | Say (roughly) |
|---|---|---|
| 0:00 | Camera or the README team table | "We're <team>. I'm Rishi, I handled the edge (Mac 2). <name> did DNS on Mac 1, <name> Backend A on Mac 3, <name> Backend B on Mac 4. We're Type 1: four MacBooks on one Wi-Fi." |
| 0:20 | `docs/ARCHITECTURE.md` topology diagram + IP table | "All four Macs are on 192.168.1.0/24. Clients only ever talk to two machines: Mac 1 for DNS and Mac 2 for HTTPS. Only Mac 2 talks to the backends." |
| 0:45 | Terminal: `cat evidence/inventory/ping-*.txt` (or run `scripts/ping-matrix.sh`) | "Every machine reaches every other machine. That's Task A." |
| 1:00 | `dig app.teamx.test` | "The answer is Mac 2's IP, and look at the SERVER line: it came from Mac 1 on port 53, our own DNS, with a 60-second TTL." |
| 1:20 | Browser → `https://app.teamx.test` → click padlock → refresh 3× | "Name in the URL, never the IP. The padlock is valid because every client trusts our team CA. Refresh, and it flips between Backend A (blue) and B (green)." |
| 1:45 | `curl -I https://app.teamx.test/api/status` (no `-k`) | "Same from curl. No -k, so the certificate is really being verified. X-Backend shows who answered." |

## Part 2: How the configuration works (2:00 – 4:00)

| Time | Show | Say |
|---|---|---|
| 2:00 | `dns/out/dnsmasq.conf` (the `host-record` + `local=` + `server=` lines) | "dnsmasq answers for teamx.test itself. app and api both point at the edge, not at a backend. Everything else gets forwarded to 1.1.1.1, so internet still works." |
| 2:20 | `edge/out/nginx.conf`: upstream block | "The upstream pool has Mac 3:3001 and Mac 4:3002. The default is round robin. max_fails plus proxy_next_upstream means a dead backend gets skipped." |
| 2:40 | Same file: `listen 443 ssl`, `ssl_certificate`, `proxy_pass` | "TLS terminates here. The cert is signed by our own CA, and the SAN covers app and api. After nginx decrypts, it forwards plain HTTP to the backend and adds X-Forwarded-For." |
| 3:00 | `scripts/verify.sh lb` + split screen `scripts/edge.sh logs` | "Ten requests, A B A B… and the access log shows the upstream address nginx chose for each one." |
| 3:15 | Wireshark: filter `dns`, then `tcp.flags.syn==1`, then `tls.handshake` | "Here's the DNS query to port 53 and the answer. Then SYN, SYN-ACK, ACK to 443 from an ephemeral port. Then ClientHello with SNI app.teamx.test, ServerHello, Certificate, ChangeCipherSpec. After that it's all Application Data, so the HTTP is encrypted." |
| 3:40 | `scripts/verify.sh cache` | "/api/info sends Cache-Control max-age=60 and an ETag. If we send the ETag back, we get 304 Not Modified with no body, from either backend, because both hash the same content." |

## Part 3: Failure demonstration, D3 (4:00 – 5:00)

Pick the fast, visual ones. Have the second terminal ready on Mac 3 / Mac 4.

| Time | Do | Say |
|---|---|---|
| 4:00 | Mac 3: Ctrl+C Backend A → client `scripts/verify.sh lb` | "Backend A is down. Every request is still 200, now all from B. nginx retried and took A out of the pool." |
| 4:15 | Mac 4: Ctrl+C Backend B → `curl -v https://app.teamx.test/api/status` | "Both down. DNS works, TCP works, TLS even says 'certificate verify ok'. Then it's 502 Bad Gateway from nginx. That's exactly where the edge ends and the backends begin." |
| 4:35 | `curl https://app.teamx.test:444` + `nc -vz <Mac2> 443` | "Wrong port: same machine, connection refused. The IP picks the machine, the port picks the program." |
| 4:45 | `scripts/client-dns.sh set <Mac3 IP>` → `dig` fails, `ping <Mac2 IP>` works → `client-dns.sh use` | "Wrong DNS server: the name fails, but ping by IP still works. DNS and IP are independent. Thanks!" |

Restart both backends afterwards (wait ~10 s before load balancing resumes).
