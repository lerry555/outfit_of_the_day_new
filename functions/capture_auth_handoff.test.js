"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const {
  createOneShotTokenListener,
  redactCaptureLog,
  validateFirebaseIdTokenShape,
} = require("./capture_auth_handoff");

function token(exp = Math.floor(Date.now() / 1000) + 3600) {
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({alg: "RS256"})}.${encode({exp})}.signature`;
}

test("JWT shape accepts valid expiry and rejects expired token", () => {
  assert(validateFirebaseIdTokenShape(token()).tokenLength > 0);
  assert.throws(() => validateFirebaseIdTokenShape(token(1)),
    /capture_auth_token_expired/);
  assert.throws(() => validateFirebaseIdTokenShape("not-a-jwt"),
    /capture_auth_token_malformed/);
});

test("one-shot listener binds loopback, requires nonce, and closes", async () => {
  const nonce = "n".repeat(64);
  const listener = createOneShotTokenListener({nonce, timeoutMs: 2000});
  const port = await listener.listen();
  try {
    const rejected = await fetch(`http://127.0.0.1:${port}/capture-auth`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({nonce: "wrong", token: token()}),
    });
    assert.equal(rejected.status, 401);
    const accepted = await fetch(`http://127.0.0.1:${port}/capture-auth`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({nonce, token: token()}),
    });
    assert.equal(accepted.status, 204);
    const handoff = await listener.tokenPromise;
    assert.equal(handoff.token, token());
    await assert.rejects(fetch(`http://127.0.0.1:${port}/capture-auth`, {
      method: "POST",
    }));
  } finally {
    listener.close();
  }
});

test("short timeout fails closed without token", async () => {
  const listener = createOneShotTokenListener({
    nonce: "n".repeat(64),
    timeoutMs: 20,
  });
  await listener.listen();
  await assert.rejects(listener.tokenPromise, /capture_auth_handoff_timeout/);
});

test("central redaction hides authorization and environment token", () => {
  const secret = token();
  const output = redactCaptureLog(
    `Authorization: Bearer ${secret} OOTD_CAPTURE_AUTH_TOKEN=${secret} ` +
    "Notifying id token listeners about user ( private-uid ).",
  );
  assert.doesNotMatch(output, new RegExp(secret.replaceAll(".", "\\.")));
  assert.match(output, /Authorization: \[REDACTED\]/);
  assert.match(output, /OOTD_CAPTURE_AUTH_TOKEN=\[REDACTED\]/);
  assert.doesNotMatch(output, /private-uid/);
});

test("Flutter bridge is debug-only and wrapper never writes the token", () => {
  const root = path.resolve(__dirname, "..");
  const flutter = fs.readFileSync(path.join(root, "lib/debug",
    "capture_auth_handoff.dart"), "utf8");
  const wrapper = fs.readFileSync(path.join(root, "tool",
    "run_capture_with_debug_auth_handoff.cjs"), "utf8");
  const main = fs.readFileSync(path.join(root, "lib", "main.dart"), "utf8");
  assert.match(flutter, /!kDebugMode \|\| !_enabled/);
  assert.match(flutter, /getIdToken\(true\)/);
  assert.match(flutter, /127\.0\.0\.1/);
  assert.doesNotMatch(flutter, /print\(|debugPrint\(/);
  assert.match(main, /if \(await CaptureAuthHandoff\.runIfEnabled\(\)\) return/);
  assert.match(wrapper, /OOTD_CAPTURE_AUTH_TOKEN: token/);
  assert.doesNotMatch(wrapper, /writeFile.*token|appendFile.*token/);
});
