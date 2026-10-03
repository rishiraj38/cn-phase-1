# Failure Demonstrations (PDF section 6.3)

We ran every scenario from the **client (Kaustubh's Mac, 10.7.3.40)** with `scripts/failure-demo.sh 1 … 5`. When the script pauses, you break something on the other Mac. The output of each run is saved in `evidence/failures/`.

Every scenario uses the same three probes, so you can see exactly **which layer** broke:
`dig app.team.test` (DNS) → `ping 10.7.16.15` (IP) → `curl https://app.team.test/api/status` (TCP + TLS + HTTP).

| # | What we break | How | DNS | IP ping | Service | What it proves |
|---|---|---|---|---|---|---|
| F1 | Wrong DNS server on the client | `client-dns.sh set 10.7.3.40` (a machine with no DNS server) | ✗ times out | ✓ | ✗ `Could not resolve host` / resolving timed out | DNS and IP are independent. The network is fine, only the name lookup is broken. |
| F2 | DNS record points to a wrong IP | on Rishi's Mac `dns.sh wrong-record` (app → 10.7.3.40) | ✓ but **wrong IP** | ✓ | ✗ `Connection refused` on 10.7.3.40:443 | DNS is only a directory. It gives an address and has no idea if anything is listening there. |
| F3 | One backend stopped | Ctrl+C Backend A on Rishi's Mac | ✓ | ✓ | ✓ 200, every reply `X-Backend: B` | The edge hides backend failure: nginx retries on B (`proxy_next_upstream`) and skips A for 10 s. |
| F4 | Both backends stopped | Ctrl+C Backend B on Kaustubh's Mac too | ✓ | ✓ | TLS handshake ✓ (`certificate verify ok`), then **502 Bad Gateway** | DNS, TCP and TLS all end at the edge, so they still work. The 502 comes from nginx itself: "I'm fine, my upstream isn't." That's the line between edge and backend. |
| F5 | Wrong destination port | `curl https://app.team.test:444` | ✓ | ✓ | ✗ `Connection refused` (TCP RST) | The IP picks the machine and the port picks the program. Nothing listens on 444, so the OS rejects the SYN. |

## Explanations in plain words

**F1: Wrong DNS server.** The client sends its DNS question to 10.7.3.40, a machine with no DNS server running. Nobody answers, so the lookup times out. But `ping 10.7.16.15` and `nc -vz 10.7.16.15 443` still work, because they skip DNS completely. So the Wi-Fi, IP and TCP are all fine. Only the "phone book" is missing.

**F2: Record points to a wrong IP.** `dig` happily returns an answer. It's just the wrong one (10.7.3.40). curl then opens a TCP connection to that address, and that Mac has nothing on port 443, so it replies with a TCP RST ("connection refused"). If that machine *did* run a web server, you'd reach the wrong service, or get a certificate name mismatch. DNS never checks whether the address actually works.

**F3: One backend down.** nginx tries Backend A, gets "connection refused" within milliseconds, and since `proxy_next_upstream error` is set, it sends the **same request** to B. The client just sees a normal 200. A is marked failed for `fail_timeout=10s`, so the next requests go straight to B. After A comes back, round robin resumes on its own once the 10 s are up.

**F4: Both backends down.** The client still resolves the name, still completes the TCP handshake, and still gets a valid certificate (`SSL certificate verify ok`). All of that is the edge's job, and the edge is healthy. Only when nginx tries to forward the request does it find nobody behind it, so it answers **502 Bad Gateway**. After restarting the backends, wait about 10 s (fail_timeout) before traffic flows again.

**F5: Wrong port.** Same host, same IP, and ping works. But TCP connections are addressed to IP **and** port. The kernel on Rishi's Mac has no socket listening on 444, so it answers the SYN with RST. Port 443 on the same IP connects fine.

## Observed results (our run, 4 Oct 2026, client = Kaustubh's Mac)

| # | Observed | Evidence |
|---|---|---|
| F1 | `dig`: "connection timed out; no servers could be reached"; curl: "Resolving timed out after 6005 milliseconds", HTTP 000. Ping to 10.7.16.15 fine, `nc` to :443 "succeeded". After restoring DNS: 10.7.16.15, HTTP 200. | `screenshots/28-failure-F1-wrong-dns.png` |
| F2 | `dig +short app.team.test` → **10.7.3.40**; curl "Trying 10.7.3.40:443… Connection refused". Ping to the real edge still fine. After `dns.sh fix`: 10.7.16.15, HTTP 200. | `screenshots/30-failure-F2-wrong-record.png` |
| F3 | 6/6 requests `HTTP/2 200 X-Backend: B` while A was stopped. | `screenshots/31-failure-F3-one-backend-down.png` |
| F4 | DNS ok, ping ok, TLSv1.3, `subject: CN=app.team.test`, `SSL certificate verify ok`, then `HTTP/2 502` / "502 Bad Gateway". Back to 200 after restarting both and waiting 10 s. | `screenshots/32-failure-F4-both-down-502.png` |
| F5 | `nc` :443 "succeeded", :444 "Connection refused", curl "Failed to connect to app.team.test port 444 after 8 ms". | `screenshots/29-failure-F5-wrong-port.png` |
