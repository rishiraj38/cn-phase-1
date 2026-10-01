# Failure Demonstrations (PDF section 6.3)

Run from a client Mac: `scripts/failure-demo.sh all` (or `1` … `5` for one scenario). Each run is saved in `evidence/failures/`.

Every scenario uses the same three probes, so you can see exactly **which layer** broke:
`dig app.teamx.test` (DNS) → `ping <Mac 2 IP>` (IP) → `curl https://app.teamx.test/api/status` (TCP + TLS + HTTP).

| # | What we break | How | DNS | IP ping | Service | What it proves |
|---|---|---|---|---|---|---|
| F1 | Wrong DNS server on the client | `client-dns.sh set <Mac 3 IP>` (a machine with no DNS server) | ✗ times out | ✓ | ✗ `Could not resolve host` | DNS and IP are independent. The network is fine, only the name lookup is broken. |
| F2 | DNS record points to a wrong IP | on Mac 1 `dns.sh wrong-record` (app → Mac 3) | ✓ but **wrong IP** | ✓ | ✗ `Connection refused` on :443 | DNS is only a directory. It gives an address and has no idea if anything is listening there. |
| F3 | One backend stopped | Ctrl+C Backend A on Mac 3 | ✓ | ✓ | ✓ 200, every reply `X-Backend: B` | The edge hides backend failure: nginx retries on B (`proxy_next_upstream`) and skips A for 10 s. |
| F4 | Both backends stopped | Ctrl+C Backend B too | ✓ | ✓ | TLS handshake ✓, then **502 Bad Gateway** | DNS, TCP and TLS all end at the edge, so they still work. The 502 comes from nginx itself: "I'm fine, my upstream isn't." That's the line between edge and backend. |
| F5 | Wrong destination port | `curl https://app.teamx.test:444` | ✓ | ✓ | ✗ `Connection refused` (TCP RST) | The IP picks the machine and the port picks the program. Nothing listens on 444, so the OS rejects the SYN. |

## Explanations in plain words

**F1: Wrong DNS server.** The client sends its question to a machine that has no DNS server running. Nobody answers (or the OS answers "port unreachable"), so the lookup times out. But `ping 192.168.1.12` and `nc -vz 192.168.1.12 443` still work, because they skip DNS completely. So the cable, the Wi-Fi, IP and TCP are all fine. Only the "phone book" is missing.

**F2: Record points to a wrong IP.** `dig` happily returns an answer. It's just the wrong one. curl then opens a TCP connection to that address, and that Mac has nothing on port 443, so it replies with a TCP RST ("connection refused"). If that machine *did* run a web server, you'd reach the wrong service, or get a certificate name mismatch. DNS never checks whether the address actually works.

**F3: One backend down.** nginx tries Backend A, gets "connection refused" within milliseconds, and since `proxy_next_upstream error` is set it sends the **same request** to B. The client just sees a normal 200. A is marked failed for `fail_timeout=10s`, so the next requests go straight to B. After A comes back, round robin resumes on its own once the 10 s are up.

**F4: Both backends down.** The client still resolves the name, still completes the TCP handshake, and still gets a valid certificate. curl -v shows `SSL certificate verify ok`. All of that is the edge's job, and the edge is healthy. Only when nginx tries to forward the request does it find nobody behind it, so it answers **502 Bad Gateway**. Note: after restarting the backends, wait ~10 s (fail_timeout) before traffic flows again.

**F5: Wrong port.** Same host, same IP, ping works. But TCP connections are addressed to IP **and** port. The kernel on Mac 2 has no socket listening on 444, so it answers the SYN with RST. Port 443 on the same IP connects fine.

## Observed results (fill in after running)

| # | Observed | Evidence file |
|---|---|---|
| F1 | | `evidence/failures/F1-wrong-dns-server-*.txt` |
| F2 | | `evidence/failures/F2-wrong-dns-record-*.txt` |
| F3 | | `evidence/failures/F3-one-backend-down-*.txt` |
| F4 | | `evidence/failures/F4-both-backends-down-*.txt` |
| F5 | | `evidence/failures/F5-wrong-port-*.txt` |
