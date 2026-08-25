"use strict";

const http = require("node:http");
const {classifyHttpStatus, createPartnerError, PARTNER_ERROR} =
  require("../partner_errors");

/**
 * Local mock HTTP partner server for adapter qualification.
 * REAL_PARTNER_API_REQUESTS remains 0 — no external retailer traffic.
 */
function createMockPartnerHttpServer({
  handler,
  host = "127.0.0.1",
} = {}) {
  if (typeof handler !== "function") {
    throw new Error("mock_partner_http_handler_required");
  }

  let requestCount = 0;
  let baseUrl = null;

  const server = http.createServer(async (req, res) => {
    requestCount += 1;
    try {
      const url = new URL(req.url, `http://${host}`);
      const result = await handler({
        method: req.method,
        path: url.pathname,
        query: Object.fromEntries(url.searchParams.entries()),
        headers: req.headers,
      });
      const status = result.status || 200;
      const body = result.body == null ? "" :
        (typeof result.body === "string" ? result.body : JSON.stringify(result.body));
      res.writeHead(status, {
        "content-type": result.contentType || "application/json",
        ...(result.headers || {}),
      });
      res.end(body);
    } catch (error) {
      res.writeHead(500, {"content-type": "application/json"});
      res.end(JSON.stringify({error: error.message || "mock_error"}));
    }
  });

  async function start() {
    await new Promise((resolve) => server.listen(0, host, resolve));
    const addr = server.address();
    baseUrl = `http://${host}:${addr.port}`;
    return baseUrl;
  }

  async function stop() {
    await new Promise((resolve, reject) => {
      server.close((err) => err ? reject(err) : resolve());
    });
  }

  return {
    start,
    stop,
    getBaseUrl: () => baseUrl,
    getRequestCount: () => requestCount,
    resetRequestCount: () => {
      requestCount = 0;
    },
  };
}

/**
 * Minimal HTTP JSON fetch used by the generic adapter skeleton in tests.
 */
async function fetchJson(url, {
  method = "GET",
  headers = {},
  timeoutMs = 5000,
  fetchImpl = globalThis.fetch,
} = {}) {
  if (typeof fetchImpl !== "function") {
    throw createPartnerError(
      PARTNER_ERROR.FATAL_CONFIGURATION,
      "partner_fetch_unavailable",
    );
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(url, {
      method,
      headers,
      signal: controller.signal,
    });
    const retryAfter = response.headers?.get?.("retry-after");
    let retryAfterMs = null;
    if (retryAfter != null) {
      const asNum = Number(retryAfter);
      if (Number.isFinite(asNum)) retryAfterMs = asNum * 1000;
    }
    if (!response.ok) {
      throw classifyHttpStatus(response.status, {retryAfterMs});
    }
    const text = await response.text();
    try {
      return JSON.parse(text);
    } catch (_) {
      throw createPartnerError(
        PARTNER_ERROR.INVALID_PAYLOAD,
        "partner_malformed_json",
      );
    }
  } catch (error) {
    if (error.name === "AbortError") {
      throw createPartnerError(PARTNER_ERROR.TIMEOUT, "partner_timeout");
    }
    if (error.code && Object.values(PARTNER_ERROR).includes(error.code)) {
      throw error;
    }
    throw createPartnerError(
      PARTNER_ERROR.PARTNER_UNAVAILABLE,
      error.message || "partner_http_failed",
    );
  } finally {
    clearTimeout(timer);
  }
}

module.exports = {
  createMockPartnerHttpServer,
  fetchJson,
};
