# Phase 1 Demo Video: Recording Plan (5:00 max)

**File name:** `CN_Phase1_<Section>_team_<Type>.mp4` · **Limits:** ≤ 5 min, ≤ 500 MB · Drive → Share → *Anyone with the link can view* (test the link in an incognito window).

You can't screen-record two Macs in one recording, so we record **5 short clips** and join them in iMovie.

**Before recording:**
- Everything must already be running: both backends, nginx and dnsmasq, and Kaustubh's Mac using our DNS and trusting the CA.
- Turn on the mic: ⌘⇧5 → Options → Microphone.
- Make the terminal font big (⌘+).
- Record with ⌘⇧5 → "Record Entire Screen".

| Clip | Mac | Time | PDF part | On screen | Say (roughly) |
|---|---|---|---|---|---|
| 1 | Rishi | 0:00–1:00 | Team intro + setup | `team.env` (the 2 IPs and roles) → `scripts/ping-matrix.sh` → `scripts/edge.sh status` → `scripts/dns.sh status` | "We're team *team*: Rishi and Kaustubh, two MacBooks on the college Wi-Fi. The PDF allows combining roles, so my Mac runs DNS, the nginx edge and Backend A, and Kaustubh's runs Backend B and is the client. Both Macs are on 10.7.0.0/19 and reach each other." |
| 2 | Kaustubh | 1:00–2:00 | Setup flow | `dig app.team.test` (ANSWER + SERVER line) → Chrome `https://app.team.test`, refresh (blue A / green B) → click the padlock → certificate | "The name resolves through our own DNS on Rishi's Mac, port 53. HTTPS uses a certificate from our own CA, which we trusted on this Mac, so there's no warning. Each refresh, nginx sends us to the other backend." |
| 3 | Rishi | 2:00–3:00 | How the config works | `cat dns/out/dnsmasq.conf`: `host-record`, `local=/team.test/`, `server=8.8.8.8`, `local-ttl=60` → `cat edge/out/nginx.conf`: `upstream app_backends`, `listen 443 ssl`, `ssl_certificate`, `proxy_pass`, `proxy_next_upstream`, `X-Forwarded-For` | "dnsmasq answers for team.test itself and forwards everything else. app and api both point at the edge, never at a backend. nginx has both backends in one upstream with round robin. TLS ends here, and nginx forwards plain HTTP, adding X-Forwarded-For so the backend knows the real client." |
| 4 | Kaustubh | 3:00–4:00 | Config in action | `scripts/verify.sh lb` → `scripts/verify.sh cache` → Wireshark on the pcap: filter `dns`, the handshake filter, `tls.handshake`, Statistics → Flow Graph | "Ten requests alternate A and B. /api/info sends Cache-Control and an ETag, so sending the ETag back gives 304 with no body, from either backend. In Wireshark: the DNS query on port 53, SYN/SYN-ACK/ACK to 443, ClientHello with SNI, the certificate from our CA, then only encrypted Application Data." |
| 5 | Kaustubh | 4:00–5:00 | Failure demo (D3) | `scripts/failure-demo.sh 3` (Rishi does Ctrl+C on Backend A) → `scripts/failure-demo.sh 4` (Ctrl+C on Backend B) → `scripts/failure-demo.sh 5` | "Backend A down: every request is still 200, now all from B. Both down: DNS, TCP and TLS still work, but nginx returns 502, which is exactly where the edge ends and the backends begin. Wrong port: same IP, connection refused, because the port picks the program." |

After clip 5, restart both backends (`scripts/backend.sh run A` on Rishi's Mac, `scripts/backend.sh run B` on Kaustubh's).

**Joining:**
1. AirDrop all clips to one Mac.
2. Open iMovie, make a new Movie and drag the clips in order (trim any dead time).
3. Share → Export File, 1080p. That gives an `.mp4`.
4. Rename it as above and upload it to Drive.
