// Backend server for the CN project. Same file runs as Backend A and Backend B:
//
//   node backend/server.js --name A --port 3001
//   node backend/server.js --name B --port 3002
//
// Only Node's built-in modules - nothing to install.
//
//   GET /            HTML page that says which backend answered
//   GET /api/status  JSON, never cached
//   GET /api/info    JSON, same on A and B, cacheable (Cache-Control + ETag -> 304)
//   GET /healthz     "ok"
//
// Every response has the header  X-Backend: A  (or B).

const http = require("http");
const os = require("os");
const crypto = require("crypto");

// read --name, --port, --team from the command line
function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i > -1 ? process.argv[i + 1] : fallback;
}
const NAME = arg("--name", "A").toUpperCase();
const PORT = Number(arg("--port", 3001));
const TEAM = arg("--team", "team");
const HOST = os.hostname();

// /api/info must be identical on A and B so both give the same ETag
const INFO = JSON.stringify({
  service: "private-network-service-platform",
  version: "1.0.0",
  message: "This document is cacheable. Ask again with If-None-Match to get a 304.",
  max_age_seconds: 60,
}, null, 2) + "\n";
const ETAG = '"' + crypto.createHash("sha256").update(INFO).digest("hex").slice(0, 16) + '"';

function page(client) {
  const color = NAME === "A" ? "#2563eb" : "#16a34a";
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${TEAM} - Backend ${NAME}</title>
<style>
 body{font-family:-apple-system,Segoe UI,sans-serif;background:${color};color:#fff;
      display:flex;min-height:100vh;margin:0;align-items:center;justify-content:center}
 .card{text-align:center} h1{font-size:96px;margin:0} p{opacity:.85;margin:.4em}
 code{background:rgba(0,0,0,.25);padding:2px 6px;border-radius:4px}
</style></head>
<body><div class="card">
 <p>${TEAM}</p>
 <h1>Backend ${NAME}</h1>
 <p>served by <code>${HOST}</code> on port <code>${PORT}</code></p>
 <p>your request came in via <code>${client}</code></p>
 <p>refresh the page - the load balancer should alternate A / B</p>
</div></body></html>
`;
}

const server = http.createServer((req, res) => {
  const path = req.url.split("?")[0];
  // nginx sends the real client IP in X-Real-IP; the TCP peer is nginx itself
  const client = req.headers["x-real-ip"] || req.socket.remoteAddress;

  console.log(`${new Date().toTimeString().slice(0, 8)} [backend ${NAME}] ` +
    `peer=${req.socket.remoteAddress} xff=${req.headers["x-forwarded-for"] || "-"} "${req.method} ${req.url}"`);

  res.setHeader("X-Backend", NAME);

  if (path === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
    res.end(page(client));
  } else if (path === "/api/status") {
    res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    res.end(JSON.stringify({
      backend: NAME,
      status: "ok",
      host: HOST,
      listen_port: PORT,
      tcp_peer: `${req.socket.remoteAddress}:${req.socket.remotePort}`,
      x_forwarded_for: req.headers["x-forwarded-for"] || null,
      x_forwarded_proto: req.headers["x-forwarded-proto"] || null,
      host_header: req.headers.host || null,
      served_at: new Date().toUTCString(),
    }, null, 2) + "\n");
  } else if (path === "/api/info") {
    res.setHeader("Cache-Control", "public, max-age=60");
    res.setHeader("ETag", ETAG);
    if (req.headers["if-none-match"] === ETAG) {
      res.writeHead(304);
      res.end();
    } else {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(INFO);
    }
  } else if (path === "/healthz") {
    res.writeHead(200, { "Content-Type": "text/plain", "Cache-Control": "no-store" });
    res.end("ok\n");
  } else {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ backend: NAME, error: "not found", path }) + "\n");
  }
});

// 0.0.0.0 = listen on every interface, so the edge on another Mac can reach it
server.listen(PORT, "0.0.0.0", () => {
  console.log(`Backend ${NAME} listening on 0.0.0.0:${PORT}  (Ctrl+C to stop)`);
});
