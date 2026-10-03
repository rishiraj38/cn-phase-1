# Evidence

Everything here comes from our real run on 3–4 Oct 2026. Two MacBooks on the college Wi-Fi (10.7.0.0/19):

- **Rishi's Mac, 10.7.16.15:** DNS (dnsmasq), edge (nginx + TLS + load balancer), Backend A :3001
- **Kaustubh's Mac, 10.7.3.40:** Backend B :3002 and the test client

| Folder | What | Produced by |
|---|---|---|
| `inventory/` | Hostname, interface, IP, mask, gateway, MAC address, routes and the ping matrix, for each Mac | `scripts/inventory.sh`, `scripts/ping-matrix.sh` |
| `pcap/` | `full-flow-tls1.2-mac4-20261004-005943.pcap`: one request from Kaustubh's Mac, DNS query/answer → SYN/SYN-ACK/ACK → ClientHello → ServerHello, Certificate → ChangeCipherSpec → encrypted Application Data. We forced TLS 1.2 so the Certificate is visible. | `scripts/capture.sh` |
| `screenshots/` | 32 screenshots, indexed below | taken during the run |

## Screenshot index (`screenshots/`)

| # | File | Mac | Shows | PDF item |
|---|---|---|---|---|
| 01 | `01-rishi-inventory.png` | Rishi | en0, IP 10.7.16.15, mask /19, gateway 10.7.0.1, MAC address | Task A |
| 02 | `02-rishi-ping-matrix.png` | Rishi | Both Macs reachable, 0% loss | Task A |
| 03 | `03-kaustubh-inventory.png` | Kaustubh | en0, IP 10.7.3.40, same /19 and gateway, DNS = 10.7.16.15 | Task A |
| 04 | `04-kaustubh-ping-matrix.png` | Kaustubh | Both Macs reachable, 0% loss | Task A |
| 05 | `05-backend-A-running.png` | Rishi | Backend A on 0.0.0.0:3001, requests arriving from the edge | Task C |
| 06 | `06-backend-B-running.png` | Kaustubh | Backend B on 0.0.0.0:3002, peer = edge 10.7.16.15, `xff` = real client | Task C |
| 07 | `07-certificate.png` | Rishi | Server cert: subject app.team.test, issuer team Local Root CA, SAN app/api.team.test, CA SHA-256 fingerprint | Task E |
| 08 | `08-nginx-status.png` | Rishi | nginx listening on *:80 and *:443, both backends reachable from the edge | Task D |
| 09 | `09-https-load-balancing.png` | Rishi | HTTPS with our CA, no `-k`: HTTP/2 200, x-backend B/A/B/A | Task D, E |
| 10 | `10-dns-server-answer.png` | Rishi | `dig @10.7.16.15 app.team.test` → 10.7.16.15, TTL 60, flag `aa` | Task B |
| 11 | `11-kaustubh-dig-uses-our-dns.png` | Kaustubh | `client-dns.sh use`, then plain `dig` → `SERVER: 10.7.16.15#53` | Task B |
| 12 | `12-kaustubh-trusts-ca.png` | Kaustubh | CA downloaded, fingerprint matches, trusted → `HTTP 200 ssl_verify_result=0` | Task E |
| 13 | `13-kaustubh-curl-v-https.png` | Kaustubh | `curl -v`: resolved via our DNS, TLS 1.3, ALPN h2, cert subject/issuer, `SSL certificate verify ok`, X-Backend | Task E, G |
| 14 | `14-kaustubh-load-balancing.png` | Kaustubh | 10 requests: A=5, B=5 (round robin) | Task D |
| 15 | `15-browser-backend-A.png` | Kaustubh | Browser on https://app.team.test, Backend A (blue), no certificate warning | Task D, E |
| 16 | `16-browser-backend-B.png` | Kaustubh | After a refresh: Backend B (green) | Task D |
| 17 | `17-browser-certificate.png` | Kaustubh | Chrome certificate viewer: issued to app.team.test by team Local Root CA | Task E |
| 18 | `18-cache-200-then-304.png` | Kaustubh | 200 with `Cache-Control: public, max-age=60` + ETag, then 304 (from A and from B), `/api/status` = no-store | Task F |
| 19 | `19-browser-devtools-304.png` | Kaustubh | DevTools: `/api/info` → 304 Not Modified, cache-control, etag, x-backend | Task F |
| 20 | `20-ws-dns.png` | Wireshark | DNS query/response, UDP 53, answer 10.7.16.15, TTL 60, authoritative | Task G |
| 21 | `21-ws-tcp-handshake.png` | Wireshark | SYN → SYN,ACK → ACK, port 63991 → 443 | Task G |
| 22 | `22-ws-tcp-seq-ack.png` | Wireshark | SYN-ACK: raw ack 2029005160 = client ISN 2029005159 + 1, window | Reliable transfer |
| 23 | `23-ws-tls-client-hello.png` | Wireshark | Client Hello, SNI = app.team.test | Task G |
| 24 | `24-ws-tls-certificate.png` | Wireshark | Certificate message: issuer team Local Root CA, subject app.team.test | Task G |
| 25 | `25-ws-change-cipher-spec.png` | Wireshark | Client Key Exchange, Change Cipher Spec, Encrypted Handshake Message | Task G |
| 26 | `26-ws-encrypted-data.png` | Wireshark | Application Data, HTTP/2 inside TLS is unreadable | Task G |
| 27 | `27-ws-flow-graph.png` | Wireshark | Flow graph: DNS → TCP → TLS → data | Task G |
| 28 | `28-failure-F1-wrong-dns.png` | Kaustubh | Wrong DNS server: lookup times out, ping and TCP 443 by IP still work | 6.3 |
| 29 | `29-failure-F5-wrong-port.png` | Kaustubh | :443 connects, :444 Connection refused | 6.3 |
| 30 | `30-failure-F2-wrong-record.png` | Kaustubh | dig → 10.7.3.40 (wrong), curl refused there; after the fix → 200 | 6.3 |
| 31 | `31-failure-F3-one-backend-down.png` | Kaustubh | Backend A stopped: 6/6 requests 200 from B | 6.3 |
| 32 | `32-failure-F4-both-down-502.png` | Kaustubh | Both stopped: DNS ok, TLS verify ok, then HTTP/2 502 Bad Gateway | 6.3 |
