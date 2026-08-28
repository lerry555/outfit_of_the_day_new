"use strict";

const fs = require("node:fs");
const path = require("node:path");
const childProcess = require("node:child_process");
const {
  runLiveQaSuite,
  printSafeReport,
} = require("./brain_live_qa_v1");

const DEFAULT_SECRET_NAME = "OPENAI_API_KEY";

function clean(value, max = 10000) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function resolveFirebaseProjectId({
  readFileSync = fs.readFileSync,
  repoRoot = path.resolve(__dirname, "../.."),
} = {}) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(path.join(repoRoot, ".firebaserc"), "utf8"));
  } catch (_) {
    throw new Error("brain_live_qa_firebase_project_config_unavailable");
  }
  const projectId = clean(parsed && parsed.projects && parsed.projects.default, 200);
  if (!projectId) throw new Error("brain_live_qa_firebase_project_missing");
  return projectId;
}

function firebaseCliCandidates({platform = process.platform, env = process.env} = {}) {
  const explicit = clean(env.FIREBASE_CLI_BIN, 1000);
  if (explicit) return Object.freeze([{command: explicit, prefixArgs: Object.freeze([])}]);
  const windows = platform === "win32";
  return Object.freeze([
    Object.freeze({command: windows ? "firebase.cmd" : "firebase", prefixArgs: Object.freeze([])}),
    Object.freeze({
      command: windows ? "npx.cmd" : "npx",
      prefixArgs: Object.freeze(["--yes", "firebase-tools"]),
    }),
  ]);
}

function readFirebaseSecret({
  secretName = DEFAULT_SECRET_NAME,
  projectId,
  execFileSync = childProcess.execFileSync,
  candidates = firebaseCliCandidates(),
} = {}) {
  const name = clean(secretName, 200);
  const project = clean(projectId, 200);
  if (!name) throw new Error("brain_live_qa_firebase_secret_name_missing");
  if (!project) throw new Error("brain_live_qa_firebase_project_missing");

  let commandFound = false;
  for (const candidate of candidates) {
    const command = clean(candidate && candidate.command, 1000);
    if (!command) continue;
    const prefixArgs = Array.isArray(candidate.prefixArgs) ? candidate.prefixArgs : [];
    try {
      const output = execFileSync(
        command,
        [
          ...prefixArgs,
          "functions:secrets:access",
          name,
          "--project",
          project,
        ],
        {
          encoding: "utf8",
          stdio: ["ignore", "pipe", "ignore"],
          maxBuffer: 1024 * 1024,
          windowsHide: true,
        },
      );
      commandFound = true;
      const value = clean(output, 10000);
      if (!value) throw new Error("brain_live_qa_firebase_secret_empty");
      return value;
    } catch (error) {
      if (error && error.code === "ENOENT") continue;
      commandFound = true;
      break;
    }
  }

  if (!commandFound) throw new Error("brain_live_qa_firebase_cli_unavailable");
  throw new Error("brain_live_qa_firebase_secret_access_failed");
}

function assertLauncherOptIn(argv = process.argv.slice(2)) {
  if (!Array.isArray(argv) || !argv.includes("--live")) {
    throw new Error("brain_live_qa_firebase_requires_live_flag");
  }
}

function resolveFilter(argv = process.argv.slice(2), env = process.env) {
  const inline = Array.isArray(argv) ? argv.find((arg) => String(arg).startsWith("--filter=")) : null;
  if (inline) return clean(String(inline).slice("--filter=".length), 120);
  return clean(env.BRAIN_LIVE_QA_FILTER, 120);
}

async function runFirebaseBackedLiveQa({
  argv = process.argv.slice(2),
  env = process.env,
  readFileSync = fs.readFileSync,
  execFileSync = childProcess.execFileSync,
  fetchImpl = global.fetch,
  now = () => new Date(),
  log = console.log,
} = {}) {
  assertLauncherOptIn(argv);
  const projectId = resolveFirebaseProjectId({readFileSync});
  const apiKey = readFirebaseSecret({
    projectId,
    execFileSync,
    candidates: firebaseCliCandidates({env}),
  });
  const suite = await runLiveQaSuite({
    apiKey,
    fetchImpl,
    now,
    filter: resolveFilter(argv, env),
  });
  printSafeReport(suite, log);
  return suite;
}

if (require.main === module) {
  runFirebaseBackedLiveQa().then((suite) => {
    if (!suite.passed) process.exitCode = 1;
  }).catch((error) => {
    const code = clean(error && error.message, 200) || "brain_live_qa_firebase_unknown_error";
    console.error(`Brain Live QA Firebase launcher aborted: ${code}`);
    process.exitCode = 1;
  });
}

module.exports = {
  DEFAULT_SECRET_NAME,
  resolveFirebaseProjectId,
  firebaseCliCandidates,
  readFirebaseSecret,
  assertLauncherOptIn,
  resolveFilter,
  runFirebaseBackedLiveQa,
};
