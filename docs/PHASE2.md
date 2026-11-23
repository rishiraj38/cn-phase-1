# Phase 2: Extensions

Phase 2 builds on the Phase 1 platform, which has DNS, an HTTPS edge, and load balancing across two backends. We added five extensions and tested each one live on the same two MacBooks. All evidence is in [`evidence/phase2/`](../evidence/phase2/).

**Team:** team · Section D · Rishi Raj (2401010380), Kaustubh Ranjan Mishra (2401020116)

## Setup for this session (23 Nov 2026)

The college Wi-Fi gave both Macs new DHCP addresses, so we updated `SERVER_IP` and `CLIENT_IP` in `team.env` on both Macs before starting.

| Mac | IP | Phase 2 roles |
|---|---|---|
| Rishi's MacBook Pro | **10.7.17.145** | primary DNS (dnsmasq), primary edge (nginx, X-Edge `mac2-nginx`), Backend A :3001 |
| Kaustubh's MacBook Pro | **10.7.17.133** | **backup DNS** (dnsmasq), **standby edge** (nginx, X-Edge `standby-nginx`), Backend B :3002, test client |

```
                 College Wi-Fi 10.7.0.0/19
  Rishi 10.7.17.145                         Kaustubh 10.7.17.133
  ┌───────────────────────────┐             ┌───────────────────────────┐
  │ dnsmasq :53   (primary)   │◀── DNS ─────│ client  (DNS list:        │
  │ nginx  :443   mac2-nginx  │◀── HTTPS ───│   .145 first, .133 second)│
  │ Backend A :3001           │             │ dnsmasq :53   (backup)    │
  │   pf: block :3001 on en0  │── HTTP ────▶│ Backend B :3002           │
  └───────────────────────────┘             │   pf: :3002 only from .145│
                                            │ nginx :443 standby-nginx  │
                                            └───────────────────────────┘
```

We restarted Phase 1 first and checked it from Kaustubh's Mac:
- `dig` returned `10.7.17.145`.
- `curl https://app.team.test/` alternated between Backend A and Backend B.

The Wi-Fi change forced one fix. Rishi's clone of the repo was fresh, so `tls/out/` held a newly generated CA. Kaustubh's first HTTPS request failed with `SSL certificate problem: self signed certificate in certificate chain`. We removed the old CA, ran `scripts/trust-ca.sh`, compared the SHA-256 fingerprint with Rishi's, and the request then returned `HTTP 200 ssl_verify_result=0`. The full output is in [text/p2-A-ca-trust-and-curl-during-dns-failover.txt](../evidence/phase2/text/p2-A-ca-trust-and-curl-during-dns-failover.txt).

---

## Extension A: Backup DNS server

**Goal:** `app.team.test` keeps resolving when the primary DNS server goes down.

**How:** Kaustubh's Mac runs a second dnsmasq with the same zone. We did not write a new config by hand. We made a copy of `team.env` in which the DNS role (`MAC1_IP`) is Kaustubh's IP, and started the normal script with it:

```
sed 's/^MAC1_IP=.*/MAC1_IP="${CLIENT_IP}"/' team.env > team-backup.env
TEAM_ENV=$PWD/team-backup.env bash scripts/dns.sh start
```

The backup listens on `10.7.17.133:53`, but `app.team.test` still points to the edge at `10.7.17.145`, so both servers give the same answer. The client gets both servers, primary first:

```
sudo networksetup -setdnsservers Wi-Fi 10.7.17.145 10.7.17.133
```

**Test:**
1. We stopped dnsmasq on Rishi's Mac.
2. We flushed the macOS cache on the client (`dscacheutil -flushcache`, `killall -HUP mDNSResponder`).
3. We resolved the name again.

| Evidence | What it shows |
|---|---|
| [p2-A1](../evidence/phase2/p2-A1-both-dns-answer.png) | `dig @10.7.17.145` and `dig @10.7.17.133` both return `10.7.17.145` |
| [p2-A2](../evidence/phase2/p2-A2-client-two-dns-servers.png) | `scutil --dns` on the client lists both name servers |
| [p2-A3](../evidence/phase2/p2-A3-primary-down-name-still-resolves.png) | Primary stopped, but `dscacheutil -q host` still resolves to `10.7.17.145` |
| [p2-A4](../evidence/phase2/p2-A4-failover-site-still-works.png) | Primary still down, but HTTPS still load-balances A/B. Each name appears twice because the page has it in both the `<title>` and the `<h1>` |

**Problem we hit:** at first the client still used `192.168.1.10` as its DNS server. Kaustubh's Mac had a VPN service (Turbo VPN) that had set it. Setting the servers again on the `Wi-Fi` service and checking `scutil --dns` fixed it.

**Why it works:** the macOS resolver tries the first server in the list. When that server doesn't answer in time, it moves on to the next one. The first lookup after the primary dies takes a little longer, and later lookups are answered by the backup.

---

## Extension B: TTL 30 and a record change

**Goal:** show how the TTL controls how quickly a DNS change reaches clients.

**How:** we set `DNS_TTL=30` in `team.env` (Rishi) and in `team-backup.env` (Kaustubh), then restarted both dnsmasq servers. Then we changed the record with `scripts/dns.sh wrong-record`, which points `app.team.test` at `10.7.17.133`, while the client ran this loop:

```
while true; do date +%T; dscacheutil -q host -a name app.team.test | grep ip; sleep 5; done
```

We used `dscacheutil` instead of `dig` on purpose. `dig` sends its query straight to the server and skips the macOS cache, so it would see the change at once. `dscacheutil` goes through the system resolver and its cache, the same path a browser uses, so it shows what the TTL actually does.

| Evidence | What it shows |
|---|---|
| [p2-B1](../evidence/phase2/p2-B1-ttl-30.png) | The answer section now shows TTL **30** (it was 60 in Phase 1) |
| [p2-B2](../evidence/phase2/p2-B2-record-change-propagates.png) | The client sees `10.7.17.145` until **19:11:16**, then `10.7.17.133` from **19:11:21** |

**Result:** the client switched to the new address within one TTL of the change. Until then it used the cached answer, and after that it asked again and got the new record. A short TTL makes changes reach clients faster, but it means more DNS queries. A long TTL means fewer queries but slower changes. We undid the change with `scripts/dns.sh fix`.

---

## Extension C: Host firewall (pf), backends reachable only through the edge

**Goal:** nobody on the LAN can bypass nginx and talk to a backend directly.

**How:** we used macOS `pf` rules in **our own anchor** `com.apple/cn-phase2`. Apple's `/etc/pf.conf` already loads `com.apple/*` anchors, so we didn't edit any system file, and the rollback only clears our anchor.

Rishi's Mac (Backend A):
```
echo "block drop in quick on en0 proto tcp from any to any port 3001" | sudo pfctl -a com.apple/cn-phase2 -f -
sudo pfctl -E
```

Kaustubh's Mac (Backend B allows only the edge):
```
printf "pass in quick on en0 proto tcp from 10.7.17.145 to any port 3002\nblock drop in quick on en0 proto tcp from any to any port 3002\n" | sudo pfctl -a com.apple/cn-phase2 -f -
sudo pfctl -E
```

nginx still reaches Backend A even though 3001 is blocked. Both run on Rishi's Mac, so that connection goes over loopback (`lo0`) and never touches `en0`, which is the only interface the rule covers.

| Evidence | What it shows |
|---|---|
| [p2-C0](../evidence/phase2/p2-C0-direct-access-before.png) | **Before:** the client opens `http://10.7.17.145:3001/` directly and gets Backend A |
| [p2-C1](../evidence/phase2/p2-C1-rishi-pf-rules.png) | Rishi's anchor rule loaded, pf enabled (token shown) |
| [p2-C2](../evidence/phase2/p2-C2-kaustubh-pf-rules.png) | Kaustubh's pass and block rules loaded |
| [p2-C3](../evidence/phase2/p2-C3-direct-blocked-site-works.png) | **After:** the same direct request gives `curl: (28) Connection timed out after 3005 ms`, while `https://app.team.test` still gives B, A, B, A |
| [p2-C4](../evidence/phase2/p2-C4-pf-rollback.png) | Rollback: the anchor is flushed and the pf token released, so pf is disabled |

**Why the request times out instead of being refused:** `block drop` silently throws the SYN away. The client never gets a reply, so it waits until its timeout. `block return` would send back a TCP RST, and the client would see "Connection refused" immediately.

**Rollback (both Macs):** `sudo pfctl -a com.apple/cn-phase2 -F all` then `sudo pfctl -X <token>`.

---

## Extension D: Backend failover (high availability)

**Goal:** when a backend dies, users see no errors.

**How:** this uses the Phase 1 nginx config without changes:
- `max_fails=1 fail_timeout=10s` on each upstream server.
- `proxy_next_upstream error timeout http_502 http_503 http_504` with `proxy_next_upstream_tries 2`.

The client ran a loop with one request per second, and we stopped Backend A in the middle of it.

| Evidence | What it shows |
|---|---|
| [p2-D1](../evidence/phase2/p2-D1-only-B-no-errors.png) | The loop goes A/B, then only **B**, with no errors and no blank lines |
| [p2-D2](../evidence/phase2/p2-D2-nginx-log-failover.png) | The nginx access log line at **19:15:46** reads `upstream=10.7.17.145:3001, 10.7.17.133:3002 upstream_status=502, 200` |
| [p2-D3](../evidence/phase2/p2-D3-backend-A-restarted.png) | Backend A restarted, and round robin resumes after `fail_timeout` |

**Reading the 19:15:46 line:**
1. nginx sent the request to A and the connection failed, which it logs as a 502.
2. In the same request it retried on B and got a 200, so the client got a 200 and never saw the failure.
3. A is then marked down for 10 seconds, so the next requests go straight to B, with only one upstream in the log.
4. After A restarted, the next check after the 10 s window succeeded and the A/B alternation came back.

---

## Extension E: Standby edge and DNS cutover

**Goal:** survive the loss of the edge itself, which Extension D can't do because nginx is the single entry point.

**How:**
1. **Standby edge:** we copied the server certificate and key (`server-chain.crt`, `server.key`) from Rishi's Mac to Kaustubh's by AirDrop. The key is never committed. We changed the `X-Edge` header in Kaustubh's copy of the template to `standby-nginx` and started nginx with the normal script. It has the same upstreams as the primary edge, so it load-balances to the same two backends.
2. **Check before cutover:** `curl --resolve app.team.test:443:10.7.17.133 https://app.team.test/` returned `x-edge: standby-nginx`. That confirmed the standby works and the certificate is valid for the name.
3. **Failure plus cutover:** we stopped nginx on Rishi's Mac and pointed `app.team.test` at `10.7.17.133` on **both** DNS servers (`scripts/dns.sh wrong-record`, which uses `WRONG_IP = CLIENT_IP`). Meanwhile the client polled the `X-Edge` header every 3 s.

| Evidence | What it shows |
|---|---|
| [p2-E1](../evidence/phase2/p2-E1-standby-ready.png) | The standby nginx passes its config test and starts, and answers `x-edge: standby-nginx` |
| [p2-E2](../evidence/phase2/p2-E2-cutover-to-standby.png) | `mac2-nginx` at 19:20:23, **empty** at 19:20:26 and 19:20:30, then `standby-nginx` from 19:20:33 onwards |

**Result:** about 7 seconds of downtime. The empty lines are the gap between the edge dying and the client's cached DNS answer running out. The 30 s TTL from Extension B puts an upper limit on that gap.

The `X-Edge` header shows which nginx answered, so the screenshot shows clearly which edge served each request. Both Macs use the same CA, so the cutover caused no certificate warning.

**Undo:** `dns.sh fix` on both DNS servers, `edge.sh start` on Rishi's Mac, `edge.sh stop` on Kaustubh's Mac, and the template header changed back to `mac2-nginx`.

---

## Extension F: Diagnosing a fault (live in the viva)

When something is broken, we go up the stack one layer at a time and stop at the first layer that fails:

| Layer | Command (on the client) | Healthy result | If it fails |
|---|---|---|---|
| DNS | `dig app.team.test` / `dscacheutil -q host -a name app.team.test` | `10.7.17.145` | wrong IP: check the record. No answer: check that dnsmasq is running and the client's DNS list (`scutil --dns`) |
| IP | `ping -c 3 10.7.17.145` | 0% loss | Wi-Fi, a changed IP, or client isolation |
| TCP | `nc -vz 10.7.17.145 443` (and `3001` / `3002` on the edge) | `succeeded` | "refused" means the service is down. A timeout means a firewall (pf) |
| TLS | `curl -v https://app.team.test/` | `SSL certificate verify ok` | the CA isn't trusted, or the certificate doesn't match the name |
| App | `curl -s -o /dev/null -w "%{http_code}" https://app.team.test/` plus the nginx access log | `200`, `upstream_status=200` | 502/504 means a backend is down. Check `upstream=` in the log |

We met most of these on the day itself:
- The VPN overriding DNS was a DNS-layer problem.
- The untrusted new CA was a TLS-layer problem.
- The pf timeouts were TCP-layer problems.
- The 502 in the D2 log line was an app/upstream-layer problem.

## Commands index

Every command above is in `scripts/` or was run as shown. Nothing in Phase 2 needed changes to the committed scripts. `team-backup.env`, `tls/out/*.key` and every `runtime/` file stay out of git.
