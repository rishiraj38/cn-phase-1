# Architecture Document: Phase 1

## 1. Network topology

**Infrastructure: two physical MacBooks on the college Wi-Fi, with the four roles combined.** The PDF (section 3) allows this: *"Teams of 2–3 may combine machine roles."* The PDF's four roles still exist. Two of the machines just run more than one of them:

| PDF role | Runs on | Address |
|---|---|---|
| Mac 1: DNS server | Rishi's Mac | 10.7.16.15:53 |
| Mac 2: Edge (nginx, TLS, load balancer) | Rishi's Mac | 10.7.16.15:80/443 |
| Mac 3: Backend A | Rishi's Mac | 10.7.16.15:3001 |
| Mac 4: Backend B + test client | Kaustubh's Mac | 10.7.3.40:3002 |

Both Macs are on the same Wi-Fi subnet 10.7.0.0/19 with the same default gateway 10.7.0.1. There's no routing between subnets, no NAT between our machines and no cloud. We kept Backend B on the *other* Mac on purpose, so load balancing really crosses the network: requests to B leave the edge over Wi-Fi.

```mermaid
flowchart LR
  subgraph LAN["College Wi-Fi 10.7.0.0/19 (one broadcast domain)"]
    subgraph R["Rishi's Mac 10.7.16.15"]
      DNS["dnsmasq :53<br/>(Mac 1 role)"]
      EDGE["nginx :80/:443<br/>TLS + load balancer<br/>(Mac 2 role)"]
      A["Backend A :3001<br/>(Mac 3 role)"]
    end
    subgraph K["Kaustubh's Mac 10.7.3.40"]
      C["Client: browser, curl, dig"]
      B["Backend B :3002<br/>(Mac 4 role)"]
    end
    GW(("Wi-Fi router<br/>10.7.0.1"))
  end
  R --- GW
  K --- GW
  C -. "DNS UDP 53" .-> DNS
  C == "HTTPS TCP 443" ==> EDGE
  EDGE -- "HTTP TCP 3001 (local)" --> A
  EDGE -- "HTTP TCP 3002 (over Wi-Fi)" --> B
```

Physically both Macs talk to the Wi-Fi router (a star). Logically, the client only ever talks to the DNS server and the edge. Only the edge talks to the backends.

## 2. Machine roles and IP / service table

From `evidence/inventory/` and screenshots `01`–`04`:

| Machine | Hostname | Interface | IPv4 | Mask / prefix | Gateway | MAC address |
|---|---|---|---|---|---|---|
| Rishi's Mac (DNS + edge + Backend A) | Rishis-MacBook-Pro.local | en0 (Wi-Fi) | 10.7.16.15 | 255.255.224.0 (/19) | 10.7.0.1 | b2:bb:00:bb:a2:b6 |
| Kaustubh's Mac (Backend B + client) | Kaustubhs-MacBook-Pro.local | en0 (Wi-Fi) | 10.7.3.40 | 255.255.224.0 (/19) | 10.7.0.1 | 0a:00:71:48:7d:13 |

A /19 mask means 10.7.0.0 to 10.7.31.255 is one network. So 10.7.3.40 and 10.7.16.15 are on the same subnet, even though the third number looks different.

### Service map

| Machine | Service | Listens on | Protocol | Who connects to it |
|---|---|---|---|---|
| Rishi's Mac (Mac 1 role) | dnsmasq | `MAC1_IP:53`, `127.0.0.1:53` | DNS over UDP (TCP for big answers) | Every client |
| Rishi's Mac (Mac 2 role) | nginx | `*:80` | HTTP, only redirects to HTTPS and serves `/ca.crt` | Clients |
| Rishi's Mac (Mac 2 role) | nginx | `*:443` | HTTPS (TLS 1.2/1.3, HTTP/1.1 + HTTP/2 via ALPN) | Clients |
| Rishi's Mac (Mac 3 role) | backend A (`server.py`) | `0.0.0.0:3001` | Plain HTTP/1.1 | Only the edge |
| Kaustubh's Mac (Mac 4 role) | backend B (`server.py`) | `0.0.0.0:3002` | Plain HTTP/1.1 | Only the edge |

### DNS records (dnsmasq on Rishi's Mac)

| Name | Type | Value | TTL |
|---|---|---|---|
| `app.team.test` | A | 10.7.16.15 (edge) | 60 s |
| `api.team.test` | A | 10.7.16.15 (edge) | 60 s |
| `mac1…mac4.team.test` | A | the IP of the Mac running that role | 60 s |
| anything else under `team.test` | | NXDOMAIN (we are authoritative, `local=/team.test/`) | |
| everything else (google.com …) | | forwarded to `8.8.8.8` | |

Both service names point at the **edge**, never at a backend. That's why clients never need to know backend IPs: the backends can move, scale or die, and the client still just asks for `app.team.test`.

## 3. Request flow, layer by layer

What happens when the client on Kaustubh's Mac runs `curl https://app.team.test/api/status`:

```mermaid
sequenceDiagram
  autonumber
  participant C as Client (Kaustubh 10.7.3.40)
  participant D as DNS (Rishi 10.7.16.15:53)
  participant E as Edge nginx (Rishi 10.7.16.15:443)
  participant A as Backend A (Rishi :3001)
  C->>D: DNS query A? app.team.test   (UDP 50xxx → 53)
  D-->>C: A = 10.7.16.15, TTL 60
  C->>E: TCP SYN          (ephemeral port → 443)
  E-->>C: TCP SYN-ACK
  C->>E: TCP ACK          (connection established)
  C->>E: TLS ClientHello  (SNI=app.team.test, ALPN h2/http1.1)
  E-->>C: ServerHello + Certificate (signed by our CA) + key exchange
  C->>E: key exchange + ChangeCipherSpec + Finished
  E-->>C: ChangeCipherSpec + Finished   (from here on everything is encrypted)
  C->>E: [encrypted] GET /api/status  Host: app.team.test
  Note over E: TLS terminated. Round robin picks next backend
  E->>A: plain HTTP GET /api/status  + X-Forwarded-For, X-Real-IP  (TCP → 3001)
  A-->>E: 200 OK, X-Backend: A, JSON body
  E-->>C: [encrypted] 200 OK, X-Backend: A
```

### Which layer does what

| Step | OSI layer | TCP/IP layer | Protocol | Ports | What it is used for |
|---|---|---|---|---|---|
| Name → IP | 7 Application | Application | DNS | client ephemeral → **UDP 53** | Find *where* the service is |
| Carry DNS | 4 Transport | Transport | UDP | | One question, one answer, no connection needed |
| Reliable byte stream | 4 Transport | Transport | TCP | client ephemeral → **TCP 443** | 3-way handshake, sequence/ack numbers, retransmission |
| Encryption + server identity | 5/6 Session/Presentation | (between Transport and Application) | TLS 1.2 / 1.3 | inside TCP 443 | Confidentiality, integrity, proving the server is really app.team.test |
| The request itself | 7 Application | Application | HTTP/1.1 or HTTP/2 | | GET, headers, status codes, caching |
| Getting between Macs | 3 Network | Internet | IPv4 | | Source/destination IP addresses on the same subnet |
| On the Wi-Fi | 2 Data link | Link | 802.11 / Ethernet frames, ARP | | MAC addresses, the router delivers the frame |
| Edge → backend | 7 + 4 | App + Transport | HTTP over TCP | edge ephemeral → **3001 / 3002** | A second, separate TCP connection. TLS has already ended. |

Notice that **two separate TCP connections** carry each request: client to edge (encrypted) and edge to backend (plain). The backend sees the edge's IP as its TCP peer, which is why nginx adds `X-Forwarded-For` / `X-Real-IP` so the backend still knows who the real client is.

## 4. Our setup vs the cloud

| Our component | What it does | Cloud equivalent |
|---|---|---|
| dnsmasq | Answers for a private zone, forwards the rest | AWS Route 53 private hosted zone, Cloud DNS |
| nginx edge | One public entry point, TLS termination, spreads load, health checks | AWS ALB / NLB, GCP HTTPS Load Balancer, CDN edge node (CloudFront) |
| Backends A and B | Identical stateless app servers | EC2 instances / containers in a target group |
| Our local CA | Issues the server certificate that clients trust | AWS ACM / Let's Encrypt (publicly trusted CAs) |
| The Wi-Fi LAN | Private network between machines | VPC + subnet |
| `Cache-Control` / `ETag` | Lets clients and caches reuse responses | CDN caching (CloudFront, Cloudflare) |

## 5. Design choices

- **Round robin** (nginx default) because both backends are identical. `least_conn` would matter only if requests took very different amounts of time.
- **Passive health checks** (`max_fails=1 fail_timeout=10s` + `proxy_next_upstream`): if a backend refuses a connection, nginx retries the same request on the other one and skips the dead one for 10 s. The client never sees an error. (Active health checks are an nginx Plus feature.)
- **TLS terminates at the edge.** The backends stay simple HTTP, and there's one place to manage certificates. The trade-off is that the edge→backend hop is plaintext on the LAN (fine for a private network; production would use mTLS or a private VPC).
- **Same content = same ETag on both backends.** `/api/info` hashes identical bytes on A and B, so a conditional request gets a 304 no matter which backend the load balancer picks.
- **Combining roles (2-Mac team):** DNS, edge and Backend A share Rishi's Mac. That's allowed by the PDF, but it makes Rishi's Mac a single point of failure for DNS *and* the edge. Phase 2 adds a backup resolver and a standby edge.
- **Backend A on the edge Mac:** nginx reaches it at 10.7.16.15:3001. That traffic never leaves the Mac (it goes over the loopback interface), while traffic to Backend B crosses the Wi-Fi. Round robin treats both the same.
