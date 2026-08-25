"use strict";

/**
 * Phase 10E host-side disabled smoke using a one-shot Flutter auth handoff.
 * Does not print tokens. Exactly one lifecycle + one authority invocation.
 */

const crypto = require("node:crypto");
const {spawn, spawnSync} = require("node:child_process");
const {
  createOneShotTokenListener,
} = require("../capture_auth_handoff");

const PROJECT = "outfitoftheday-4d401";
const REGION = "us-east1";
const LIFE = "wardrobeRevisionLifecycle";
const AUTH = "wardrobeQualificationAuthority";
function fp(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 12);
}

function adb(...args) {
  const adbPath = process.env.ANDROID_HOME ?
    `${process.env.ANDROID_HOME}/platform-tools/adb` :
    `${process.env.LOCALAPPDATA}/Android/Sdk/platform-tools/adb.exe`;
  return spawnSync(adbPath, args, {encoding: "utf8"});
}

async function callCallable(name, idToken, data) {
  const url =
    `https://${REGION}-${PROJECT}.cloudfunctions.net/${name}`;
  const started = Date.now();
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${idToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({data}),
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch (_) {
    json = {rawTextLength: text.length};
  }
  return {
    httpStatus: res.status,
    elapsedMs: Date.now() - started,
    body: json,
  };
}

function classifyDisabled(result) {
  const err = result.body && (result.body.error || result.body);
  const status = (err && (err.status || err.code)) || null;
  const message = (err && (err.message || err.statusMessage)) || "";
  if (result.httpStatus === 404) return "not_found";
  if (status === "UNAUTHENTICATED" || /UNAUTHENTICATED/i.test(message)) {
    return "unauthenticated";
  }
  if (status === "PERMISSION_DENIED" || /PERMISSION_DENIED/i.test(message)) {
    return "permission_denied";
  }
  if (status === "FAILED_PRECONDITION" ||
      /wardrobe_authority_mode_disabled/i.test(message) ||
      /FAILED_PRECONDITION/i.test(message)) {
    return "disabled_failed_precondition";
  }
  if (status === "UNAVAILABLE" || result.httpStatus === 503) {
    return "unavailable";
  }
  return "unexpected";
}

async function main() {
  const itemId = process.argv[2];
  if (!itemId) throw new Error("usage: node run_disabled_smoke_host.js <itemId>");

  const nonce = crypto.randomBytes(24).toString("hex");
  const listener = createOneShotTokenListener({nonce, timeoutMs: 180000});
  const port = await listener.listen();

  // adb reverse so emulator can reach host listener
  const reverse = adb(
    "-s", "emulator-5554", "reverse", `tcp:${port}`, `tcp:${port}`,
  );
  if (reverse.status !== 0) {
    listener.close();
    throw new Error(`adb_reverse_failed:${reverse.stderr || reverse.stdout}`);
  }

  const flutter = spawn(
    "flutter",
    [
      "run",
      "-d", "emulator-5554",
      "--debug",
      "--dart-define=OOTD_CAPTURE_AUTH_HANDOFF=true",
      `--dart-define=OOTD_CAPTURE_AUTH_PORT=${port}`,
      `--dart-define=OOTD_CAPTURE_AUTH_NONCE=${nonce}`,
    ],
    {
      cwd: require("node:path").resolve(__dirname, "../.."),
      stdio: ["ignore", "pipe", "pipe"],
      shell: true,
    },
  );

  let handoff;
  try {
    handoff = await listener.tokenPromise;
  } finally {
    try {
      flutter.kill("SIGTERM");
    } catch (_) {}
    try {
      listener.close();
    } catch (_) {}
  }

  // Do not log token. Only length/exp audit already in handoff.audit.
  const idToken = handoff.token;
  const life = await callCallable(LIFE, idToken, {
    contractVersion: 1,
    operationKind: "request_same_image_reanalysis",
    itemId,
    idempotencyKey: "m11-1-10e-lifecycle-smoke-1",
  });
  const authority = await callCallable(AUTH, idToken, {
    contractVersion: 1,
    itemId,
    action: "analyze_current_source",
    idempotencyKey: "m11-1-10e-authority-smoke-1",
  });

  const report = {
    ok: true,
    region: REGION,
    projectId: PROJECT,
    itemFingerprint: fp(itemId),
    tokenAudit: handoff.audit,
    appCheckEnforcement: "not_enabled",
    lifecycle: {
      classification: classifyDisabled(life),
      httpStatus: life.httpStatus,
      elapsedMs: life.elapsedMs,
      errorStatus: life.body && life.body.error && life.body.error.status,
      errorMessage: life.body && life.body.error && life.body.error.message,
    },
    authority: {
      classification: classifyDisabled(authority),
      httpStatus: authority.httpStatus,
      elapsedMs: authority.elapsedMs,
      errorStatus: authority.body && authority.body.error &&
        authority.body.error.status,
      errorMessage: authority.body && authority.body.error &&
        authority.body.error.message,
    },
  };
  console.log(JSON.stringify(report, null, 2));
}

main().catch((err) => {
  console.error(JSON.stringify({
    ok: false,
    reasonCode: String(err && err.message || err),
  }));
  process.exit(1);
});
