"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  resolveFirebaseProjectId,
  firebaseCliCandidates,
  readFirebaseSecret,
  assertLauncherOptIn,
  resolveFilter,
} = require("./brain_live_qa_firebase_launcher_v1");

test("Firebase live launcher reads the default project from .firebaserc", () => {
  const projectId = resolveFirebaseProjectId({
    readFileSync: () => JSON.stringify({projects: {default: "outfitoftheday-4d401"}}),
    repoRoot: "/repo",
  });
  assert.equal(projectId, "outfitoftheday-4d401");
});

test("Firebase live launcher requires explicit --live opt-in", () => {
  assert.throws(() => assertLauncherOptIn([]), /requires_live_flag/);
  assert.doesNotThrow(() => assertLauncherOptIn(["--live"]));
});

test("Firebase CLI candidates are Windows-safe and support explicit binary override", () => {
  const windows = firebaseCliCandidates({platform: "win32", env: {}});
  assert.equal(windows[0].command, "firebase.cmd");
  assert.equal(windows[1].command, "npx.cmd");
  assert.deepEqual(windows[1].prefixArgs, ["--yes", "firebase-tools"]);

  const explicit = firebaseCliCandidates({
    platform: "win32",
    env: {FIREBASE_CLI_BIN: "C:\\tools\\firebase.cmd"},
  });
  assert.equal(explicit.length, 1);
  assert.equal(explicit[0].command, "C:\\tools\\firebase.cmd");
});

test("Firebase secret access keeps the value out of command arguments", () => {
  const calls = [];
  const secret = readFirebaseSecret({
    projectId: "outfitoftheday-4d401",
    candidates: [{command: "firebase", prefixArgs: []}],
    execFileSync: (command, args, options) => {
      calls.push({command, args, options});
      return "  sk-secret-value\n";
    },
  });

  assert.equal(secret, "sk-secret-value");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, "firebase");
  assert.deepEqual(calls[0].args, [
    "functions:secrets:access",
    "OPENAI_API_KEY",
    "--project",
    "outfitoftheday-4d401",
  ]);
  assert.equal(calls[0].args.join(" ").includes("sk-secret-value"), false);
  assert.deepEqual(calls[0].options.stdio, ["ignore", "pipe", "ignore"]);
});

test("Firebase secret access falls back to npx only when CLI binary is missing", () => {
  const commands = [];
  const secret = readFirebaseSecret({
    projectId: "outfitoftheday-4d401",
    candidates: [
      {command: "firebase", prefixArgs: []},
      {command: "npx", prefixArgs: ["--yes", "firebase-tools"]},
    ],
    execFileSync: (command) => {
      commands.push(command);
      if (command === "firebase") {
        const error = new Error("missing");
        error.code = "ENOENT";
        throw error;
      }
      return "secret-from-fallback";
    },
  });

  assert.equal(secret, "secret-from-fallback");
  assert.deepEqual(commands, ["firebase", "npx"]);
});

test("Firebase launcher exposes only a sanitized failure when secret access fails", () => {
  assert.throws(
    () => readFirebaseSecret({
      projectId: "outfitoftheday-4d401",
      candidates: [{command: "firebase", prefixArgs: []}],
      execFileSync: () => {
        throw new Error("raw provider output with sensitive details");
      },
    }),
    (error) => {
      assert.equal(error.message, "brain_live_qa_firebase_secret_access_failed");
      assert.equal(error.message.includes("sensitive details"), false);
      return true;
    },
  );
});

test("Firebase launcher filter works on Windows without shell env syntax", () => {
  assert.equal(resolveFilter(["--live", "--filter=current-public"], {}), "current-public");
  assert.equal(resolveFilter(["--live"], {BRAIN_LIVE_QA_FILTER: "private"}), "private");
});
