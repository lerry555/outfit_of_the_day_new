"use strict";

function createNoRetryFetchExecutor({fetchImpl = globalThis.fetch} = {}) {
  if (typeof fetchImpl !== "function") throw new Error("fetch_executor_missing");
  return async (request) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), request.timeoutMs);
    try {
      const response = await fetchImpl(request.url, {
        method: request.method,
        headers: {...request.headers, "content-type": "application/json"},
        body: JSON.stringify(request.body),
        signal: controller.signal,
      });
      let json = null;
      try { json = await response.json(); } catch (_) {
        return Object.freeze({ok: false, status: response.status, code: "structured_output_invalid"});
      }
      return Object.freeze({ok: response.ok, status: response.status, json});
    } finally {
      clearTimeout(timer);
    }
  };
}

module.exports = {createNoRetryFetchExecutor};
