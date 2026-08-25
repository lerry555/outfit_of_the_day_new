"use strict";

const http = require("http");

const DEFAULT_TIMEOUT_MS = 45_000;
const MIN_TOKEN_LIFETIME_SECONDS = 120;

function validateFirebaseIdTokenShape(token, nowSeconds = Date.now() / 1000) {
  if (typeof token !== "string" || !token) {
    throw new Error("capture_auth_unavailable");
  }
  const parts = token.split(".");
  if (parts.length !== 3 || parts.some((part) => !part)) {
    throw new Error("capture_auth_token_malformed");
  }
  let payload;
  try {
    payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
  } catch (_) {
    throw new Error("capture_auth_token_malformed");
  }
  if (!Number.isFinite(payload.exp) ||
      payload.exp - nowSeconds < MIN_TOKEN_LIFETIME_SECONDS) {
    throw new Error("capture_auth_token_expired");
  }
  return {expiresAt: payload.exp, tokenLength: token.length};
}

function createOneShotTokenListener({
  nonce,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  nowSeconds,
}) {
  if (typeof nonce !== "string" || nonce.length < 32) {
    throw new Error("capture_auth_nonce_invalid");
  }
  let settled = false;
  let timer;
  let resolveToken;
  let rejectToken;
  const tokenPromise = new Promise((resolve, reject) => {
    resolveToken = resolve;
    rejectToken = reject;
  });
  const server = http.createServer((request, response) => {
    if (settled || request.method !== "POST" ||
        request.url !== "/capture-auth") {
      response.writeHead(404).end();
      return;
    }
    const chunks = [];
    request.on("data", (chunk) => {
      if (chunks.reduce((sum, item) => sum + item.length, 0) > 16_384) {
        request.destroy();
      } else {
        chunks.push(chunk);
      }
    });
    request.on("end", () => {
      try {
        const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        if (body.nonce !== nonce) throw new Error("capture_auth_nonce_mismatch");
        const audit = validateFirebaseIdTokenShape(body.token, nowSeconds);
        settled = true;
        clearTimeout(timer);
        response.writeHead(204).end();
        server.close();
        resolveToken({token: body.token, audit});
      } catch (error) {
        response.writeHead(401).end();
        if (error.message !== "capture_auth_nonce_mismatch") {
          settled = true;
          clearTimeout(timer);
          server.close();
          rejectToken(error);
        }
      }
    });
  });
  const listen = () => new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      timer = setTimeout(() => {
        if (settled) return;
        settled = true;
        server.close();
        rejectToken(new Error("capture_auth_handoff_timeout"));
      }, timeoutMs);
      timer.unref();
      resolve(server.address().port);
    });
  });
  return {
    listen,
    tokenPromise,
    close() {
      clearTimeout(timer);
      if (server.listening) server.close();
    },
  };
}

function redactCaptureLog(value) {
  return String(value)
    .replace(/Authorization\s*:\s*Bearer\s+\S+/gi,
      "Authorization: [REDACTED]")
    .replace(/Bearer\s+[A-Za-z0-9._~-]+/gi, "Bearer [REDACTED]")
    .replace(/OOTD_CAPTURE_AUTH_TOKEN\s*=\s*\S+/gi,
      "OOTD_CAPTURE_AUTH_TOKEN=[REDACTED]")
    .replace(/\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g,
      "[JWT_REDACTED]")
    .replace(/(id token listeners about user\s*\()\s*[^)]+(\))/gi,
      "$1[REDACTED]$2");
}

module.exports = {
  DEFAULT_TIMEOUT_MS,
  createOneShotTokenListener,
  redactCaptureLog,
  validateFirebaseIdTokenShape,
};
