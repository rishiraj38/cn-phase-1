# Packet Evidence Guide (Task G)

## Capture

On the client (Kaustubh's Mac):
```bash
scripts/capture.sh
```
It flushes the DNS cache (so a real DNS query happens), starts `tcpdump` with the filter
`(udp port 53 and host MAC1) or (tcp port 443 and host MAC2)`, makes **one** HTTPS request by name, and stops. You get:

- `evidence/pcap/full-flow-<host>-<time>.pcap`: open it in Wireshark
- `evidence/text/capture-<host>-<time>.txt`: a text decode (tcpdump + tshark)
- `evidence/pcap/sslkeys-<host>-<time>.log`: TLS secrets (if your curl supports it)


## Screenshots (in `evidence/screenshots/`, from `evidence/pcap/full-flow-tls1.2-mac4-20261004-005943.pcap`)

Client 10.7.3.40 (Kaustubh) ↔ DNS/edge 10.7.16.15 (Rishi). One request: `curl --tls-max 1.2 https://app.team.test/api/status`.

| # | Wireshark display filter | What it shows | File |
|---|---|---|---|
| 20 | `dns.qry.name == "app.team.test"` | Query 10.7.3.40:64246 → 10.7.16.15:**53/UDP**; the response has answer **10.7.16.15**, TTL 60, flag "Server is an authority for domain" | `20-ws-dns.png` |
| 21 | `tcp.port == 443 && (tcp.flags.syn == 1 \|\| (tcp.seq == 1 && tcp.ack == 1 && tcp.len == 0))` | **SYN → SYN, ACK → ACK**, ephemeral port 63991 → **443** | `21-ws-tcp-handshake.png` |
| 22 | `tcp.stream eq 0`, SYN-ACK selected | Server seq 0 (raw 264361562), **ack 1 (raw 2029005160 = client's ISN 2029005159 + 1)**, window 65535 | `22-ws-tcp-seq-ack.png` |
| 23 | `tls.handshake.type == 1` | **ClientHello**, extension `server_name` = **app.team.test** (SNI) | `23-ws-tls-client-hello.png` |
| 24 | `tls.handshake`, packet 13 | **Certificate**: issuer `team Local Root CA`, subject `app.team.test` (plus Server Key Exchange, Server Hello Done) | `24-ws-tls-certificate.png` |
| 25 | `tls.record.content_type == 20` | Client Key Exchange → **Change Cipher Spec** → Encrypted Handshake Message (and the same from the server) | `25-ws-change-cipher-spec.png` |
| 26 | `tls.app_data` | **Application Data**: the HTTP/2 request is just encrypted bytes | `26-ws-encrypted-data.png` |
| 27 | Statistics → Flow Graph | The whole DNS → TCP → TLS → data timeline between the two Macs | `27-ws-flow-graph.png` |

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
| DNS | 10.7.3.40 : **ephemeral** (64246 in our capture) / UDP | 10.7.16.15 : **53** / UDP |
| HTTPS | 10.7.3.40 : **ephemeral** (63991 in our capture) / TCP | 10.7.16.15 : **443** / TCP |
| Edge → backend | 10.7.16.15 : **ephemeral** / TCP | 10.7.16.15 : **3001** (A) or 10.7.3.40 : **3002** (B) / TCP |

A socket pair (client IP, client port, server IP, server port) + protocol identifies a single connection. `scripts/verify.sh ports` prints it for a live request.

## Decrypting the HTTP inside TLS (bonus)

Wireshark → Settings → Protocols → TLS → (Pre)-Master-Secret log filename → choose `evidence/pcap/sslkeys-*.log`. Now `http2` / `http` packets appear inside the TLS stream. This works because we hold the session keys. Someone sniffing the Wi-Fi doesn't, which is exactly the point.
