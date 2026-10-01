# Packet Evidence Guide (Task G)

## Capture

On a client Mac (Mac 1 or Mac 4):
```bash
scripts/capture.sh
```
It flushes the DNS cache (so a real DNS query happens), starts `tcpdump` with the filter
`(udp port 53 and host MAC1) or (tcp port 443 and host MAC2)`, makes **one** HTTPS request by name, and stops. You get:

- `evidence/pcap/full-flow-<host>-<time>.pcap`: open it in Wireshark
- `evidence/text/capture-<host>-<time>.txt`: a text decode (tcpdump + tshark)
- `evidence/pcap/sslkeys-<host>-<time>.log`: TLS secrets (if your curl supports it)

On Mac 2 (optional but impressive): `scripts/capture-edge.sh 20` while a client runs `scripts/verify.sh lb`. You'll see the same requests **encrypted** on :443 and **in plain text** on :3001/:3002. That's TLS termination, proven.

## What to screenshot (save into `evidence/screenshots/`)

| # | Wireshark display filter | Point at | Screenshot name |
|---|---|---|---|
| 1 | `dns` | Query `A app.teamx.test` from client:ephemeral → Mac1:**53/UDP**. Response with **Mac 2's IP**, TTL 60, flag `aa` (authoritative) | `01-dns.png` |
| 2 | `tcp.flags.syn==1 or (tcp.seq==1 and tcp.ack==1 and tcp.len==0)` | **SYN → SYN-ACK → ACK**, client ephemeral port → **443** | `02-tcp-handshake.png` |
| 3 | `tcp.stream eq 0` then the SYN packet → expand TCP | Sequence number, ack number, window, MSS option | `03-tcp-seq-ack.png` |
| 4 | `tls.handshake.type == 1` → expand TLS | **ClientHello**: SNI `app.teamx.test`, cipher suites, ALPN `h2` | `04-client-hello.png` |
| 5 | `tls.handshake` | **ServerHello, Certificate** (expand it: subject `app.teamx.test`, issuer `Team X Local Root CA`), key exchange | `05-server-hello-cert.png` |
| 6 | `tls.record.content_type == 20` | **ChangeCipherSpec** from both sides | `06-change-cipher-spec.png` |
| 7 | `tls.app_data` | **Application Data**: the HTTP is unreadable in the bytes pane | `07-encrypted-http.png` |
| 8 | Statistics → Flow Graph | The whole DNS → TCP → TLS → data → FIN timeline on one screen | `08-flow-graph.png` |
| 9 | (Mac 2 capture) `http` | Backend leg: `GET /api/status`, `X-Forwarded-For`, `X-Backend: A` in clear text | `09-backend-leg-plain-http.png` |

Tip: View → Time Display Format → Seconds Since Previous Displayed Packet makes it easy to show that DNS happens *before* the SYN.

## How to explain TCP sequence / acknowledgement numbers

Wireshark shows *relative* numbers (start at 0) by default. The text file has the real ones (`tcpdump -S`).

- **SYN** (client): `seq = x`. "I'll start numbering my bytes from x."
- **SYN-ACK** (server): `seq = y, ack = x+1`. "Got your SYN (it counts as 1 byte). I start at y."
- **ACK** (client): `seq = x+1, ack = y+1`. Connection is open, and **no application data has been sent yet**.
- After that, each side's `ack` = "the next byte I expect from you". If a 517-byte ClientHello goes out with `seq=1`, the server's reply carries `ack=518`.
- That's how TCP is reliable: anything not acknowledged in time gets retransmitted, duplicates are spotted by their sequence numbers, and the window field tells the sender how much it may send before waiting (flow control).

## Ports for each layer

| Layer | Source | Destination |
|---|---|---|
| DNS | client IP : **ephemeral** (e.g. 53012) / UDP | Mac 1 : **53** / UDP |
| HTTPS | client IP : **ephemeral** (e.g. 53128) / TCP | Mac 2 : **443** / TCP |
| Edge → backend | Mac 2 : **ephemeral** / TCP | Mac 3 : **3001** or Mac 4 : **3002** / TCP |

A socket pair (client IP, client port, server IP, server port) + protocol identifies a single connection. `scripts/verify.sh ports` prints it for a live request.

## Decrypting the HTTP inside TLS (bonus)

Wireshark → Settings → Protocols → TLS → (Pre)-Master-Secret log filename → choose `evidence/pcap/sslkeys-*.log`. Now `http2` / `http` packets appear inside the TLS stream. This works because we hold the session keys. Someone sniffing the Wi-Fi doesn't, which is exactly the point.
