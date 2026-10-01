# Viva Prep: Phase 1

Every member should be able to answer all of these about **any** part of the system, not just their own Mac. The answers are kept short and in plain words. Say them in your own words in the viva.

### DNS

**What's the difference between DNS resolution and the HTTPS connection that follows?**
DNS is just a lookup. The client asks Mac 1 "what's the address of app.team.test?" over UDP port 53 and gets back Mac 2's IP. Nothing is connected yet. Only after that does the client open a brand-new TCP connection to that IP on port 443 and start TLS. Two different servers, two different protocols, two different ports.

**Why `.test` and not `.local`?**
`.test` is reserved for exactly this kind of testing, so it never collides with a real domain. macOS uses `.local` for Bonjour/mDNS (multicast on the LAN), so `.local` names would never even reach our DNS server.

**What does the TTL mean in the dig output?**
How many seconds the client (and any resolver in between) may cache the answer before asking again. Ours is 60 s. Short TTL = changes spread fast but more queries. Long TTL = fewer queries but slow changes.

**Why is DNS on UDP?**
One small question and one small answer, so a TCP handshake would cost more than the query itself. If the answer is too big or gets truncated, DNS falls back to TCP 53.

**What happens if the client asks for google.com?**
dnsmasq doesn't know it, so it forwards to the upstream resolver (1.1.1.1) and passes the answer back. For anything under team.test it answers itself (`local=/team.test/`) and never forwards.

### TCP and ports

**Explain the three-way handshake.**
Client sends SYN with its starting sequence number. The server replies SYN-ACK with its own sequence number, acknowledging the client's +1. The client sends ACK. Now both sides know each other's starting numbers and the connection is open. No application data is sent before this.

**What are sequence and acknowledgement numbers for?**
Every byte gets a number. The ack says "I've received everything up to here, send me the next one." That's how TCP notices loss (no ack, so it retransmits), drops duplicates, and puts out-of-order segments back in order.

**What's an ephemeral port?**
The random high port (like 53128) the OS picks for the client side of a connection. The server side uses a well-known port (53, 443) so clients know where to go.

**What's a socket pair?**
Client IP + client port + server IP + server port (+ protocol). It uniquely identifies one connection. That's how Mac 2 keeps hundreds of clients apart on the same port 443.

**Ping works but the website doesn't. What layer is it?**
Ping is ICMP at the IP layer, so the network path is fine. Check the port (`nc -vz ip 443`). Refused means nothing is listening (an application/port problem). If TCP connects, check TLS (`curl -v`), then HTTP.

### TLS

**Walk through the TLS handshake.**
ClientHello (versions, ciphers, random, SNI = which site, ALPN = h2 or http/1.1) → ServerHello (choices + random) → Certificate (proves identity) → key exchange (both sides derive the same secret with ECDHE; the server signs its part with its private key) → ChangeCipherSpec/Finished from both sides → after that everything is encrypted Application Data.

**What does the browser check on the certificate?**
That it chains up to a CA in its trust store (our team CA, which we installed), the signatures are valid, the name typed is in the SAN, the dates are valid, and the server holds the private key (it signed the handshake).

**Why did we have to install our CA on the clients?**
Our CA isn't one of the public CAs that ship with macOS. Without it in the keychain, the browser has no reason to trust a cert we signed ourselves, so it would show a warning. `-k` would just switch the checking off, which proves nothing.

**What does "TLS termination at the edge" mean?**
The encrypted connection ends at nginx on Mac 2. nginx decrypts the request, reads it, picks a backend and forwards it as plain HTTP. Only Mac 2 has the private key, and the backends stay simple. Our edge capture shows the same request encrypted on :443 and readable on :3001.

**Why can't Wireshark show the HTTP request?**
It's inside TLS Application Data records, encrypted with session keys only the client and server know. With the key log file we can decrypt our own capture, but a Wi-Fi eavesdropper can't.

**TLS 1.2 vs 1.3?**
1.3 needs one round trip instead of two, drops old weak ciphers, always uses forward-secret key exchange, and encrypts the certificate too. That's why our capture uses 1.2: so we can actually see the Certificate message.

### HTTP, REST, caching

**HTTP/1.1 vs HTTP/2?**
1.1 is text, one request at a time per connection. HTTP/2 is binary, multiplexes many requests as streams over one connection, and compresses headers. It's negotiated via ALPN inside the TLS handshake. Our nginx does both (`verify.sh http2`). HTTP/3 runs over QUIC on UDP. We only explain it.

**Fresh hit vs conditional request vs full request?**
Fresh hit: within max-age, so the browser doesn't touch the network at all. Conditional: the copy is stale, so it sends If-None-Match with the ETag, and the server says 304 with no body. Full: no copy or the content changed, so it's a 200 with the whole body.

**Why does a 304 work even when the other backend answers?**
Both backends serve identical bytes for /api/info and the ETag is a hash of those bytes, so they agree on it.

### Load balancing and the edge

**Why doesn't the client need the backend IPs?**
DNS gives the client only the edge's IP. The backend list lives inside nginx's config. Backends can change without any client noticing. That's the same idea as an AWS ALB with a target group.

**What algorithm do you use and why?**
Round robin, nginx's default. Both backends are identical, so taking turns spreads load evenly. least_conn would help if some requests were much slower than others.

**What happens when one backend dies?**
nginx gets "connection refused", retries the same request on the other backend (proxy_next_upstream), and marks the dead one failed for 10 s. The user sees no error.

**When do you see 502?**
When nginx itself is fine but none of its upstreams answer. DNS, TCP and TLS still succeed because they all end at the edge.

**What's still a single point of failure?**
Mac 2 (the only edge) and Mac 1 (the only DNS server). Phase 2 adds a backup DNS server and a standby edge with a DNS cutover.

### Layers

**Map our request onto OSI / TCP-IP.**
DNS and HTTP are application layer. TLS sits between application and transport (session/presentation in OSI). TCP and UDP are transport. IPv4 is network. Wi-Fi/Ethernet frames with MAC addresses are the link layer. ARP connects IP addresses to MAC addresses on our LAN.

**Why does the backend see Mac 2's IP and not the client's?**
Because there are two TCP connections. The backend's TCP peer really is the edge. nginx passes the original client in X-Forwarded-For / X-Real-IP.
