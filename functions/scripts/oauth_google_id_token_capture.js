"use strict";

const http = require("http");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const clientId =
  "221686818701-44elcocf5ge0k7otajo8qobne908kjir.apps.googleusercontent.com";
const port = 8765;
const nonce = crypto.randomBytes(16).toString("hex");
const redirect = `http://127.0.0.1:${port}/oauth`;
const url = "https://accounts.google.com/o/oauth2/v2/auth" +
  `?client_id=${encodeURIComponent(clientId)}` +
  `&redirect_uri=${encodeURIComponent(redirect)}` +
  `&response_type=${encodeURIComponent("id_token token")}` +
  `&scope=${encodeURIComponent("openid email profile")}` +
  `&nonce=${nonce}` +
  "&prompt=select_account";

const outDir = process.env.TEMP || ".";
fs.writeFileSync(path.join(outDir, "m11_10er_oauth_url.txt"), url);
console.log("OAUTH_URL_WRITTEN");
console.log(`redirect=${redirect}`);

const server = http.createServer((req, res) => {
  const u = new URL(req.url, `http://127.0.0.1:${port}`);
  if (u.pathname === "/oauth") {
    res.writeHead(200, {"Content-Type": "text/html; charset=utf-8"});
    res.end(`<!doctype html><html><body><script>
      const h=location.hash.substring(1);
      fetch('/capture',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({hash:h})})
        .then(()=>{document.body.innerText='captured';});
    </script>Capturing...</body></html>`);
    return;
  }
  if (u.pathname === "/capture" && req.method === "POST") {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      try {
        const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        const params = new URLSearchParams(body.hash || "");
        const idToken = params.get("id_token");
        if (!idToken) {
          res.writeHead(400).end("missing");
          return;
        }
        fs.writeFileSync(
          path.join(outDir, "m11_10er_google_id_token.txt"),
          idToken,
          {mode: 0o600},
        );
        console.log(`GOOGLE_ID_TOKEN_CAPTURED len=${idToken.length}`);
        res.writeHead(204).end();
        server.close();
        process.exit(0);
      } catch (e) {
        res.writeHead(500).end("err");
      }
    });
    return;
  }
  res.writeHead(404).end();
});

server.listen(port, "127.0.0.1", () => console.log("LISTENING"));
setTimeout(() => {
  console.log("TIMEOUT");
  process.exit(2);
}, 180000);
