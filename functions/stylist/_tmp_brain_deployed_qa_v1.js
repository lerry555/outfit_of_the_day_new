"use strict";

const crypto = require("node:crypto");

const projectId = process.env.FIREBASE_PROJECT_ID || "outfitoftheday-4d401";
const apiKey = process.env.FIREBASE_WEB_API_KEY || "";
const endpoint = `https://us-east1-${projectId}.cloudfunctions.net/stylistChat`;
const identityBase = "https://identitytoolkit.googleapis.com/v1";
const allowedActions = new Set(["chat", "clarify", "generate_outfit", "show_items"]);

async function jsonRequest(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch (_) {}
  return {response, json};
}

function authErrorCode(result) {
  return String(result?.json?.error?.message || result?.response?.status || "unknown")
    .trim()
    .slice(0, 120);
}

async function signUp(body) {
  return jsonRequest(
    `${identityBase}/accounts:signUp?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({...body, returnSecureToken: true}),
    },
  );
}

async function createEphemeralAuth() {
  if (!apiKey) throw new Error("firebase_web_api_key_missing");

  const anonymous = await signUp({});
  if (anonymous.response.ok && anonymous.json?.idToken) {
    console.log("Firebase ephemeral auth | PASS | provider=anonymous");
    return maskAndReturnAuth(anonymous.json, "anonymous");
  }

  const anonymousCode = authErrorCode(anonymous);
  const suffix = crypto.randomUUID().replace(/-/g, "");
  const email = `brain-live-${suffix}@example.invalid`;
  const password = `${crypto.randomBytes(18).toString("base64url")}Aa1!`;
  const emailPassword = await signUp({email, password});
  if (emailPassword.response.ok && emailPassword.json?.idToken) {
    console.log("Firebase ephemeral auth | PASS | provider=email_password");
    return maskAndReturnAuth(emailPassword.json, "email_password");
  }

  throw new Error(
    `firebase_ephemeral_auth_failed:anonymous=${anonymousCode};email=${authErrorCode(emailPassword)}`,
  );
}

function maskAndReturnAuth(json, provider) {
  console.log(`::add-mask::${json.idToken}`);
  if (json.refreshToken) console.log(`::add-mask::${json.refreshToken}`);
  return {
    idToken: json.idToken,
    localId: String(json.localId || ""),
    provider,
  };
}

async function deleteEphemeralAuth(idToken) {
  if (!idToken) return;
  try {
    const result = await jsonRequest(
      `${identityBase}/accounts:delete?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({idToken}),
      },
    );
    console.log(
      `Firebase ephemeral auth cleanup | ${result.response.ok ? "DONE" : "BEST_EFFORT_FAILED"}`,
    );
  } catch (_) {
    console.log("Firebase ephemeral auth cleanup | BEST_EFFORT_FAILED");
  }
}

async function callStylist(payload, idToken) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 110000);
  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({data: payload}),
      signal: controller.signal,
    });
    const text = await response.text();
    let envelope;
    try {
      envelope = JSON.parse(text);
    } catch (_) {
      throw new Error(`callable_non_json_http_${response.status}`);
    }
    if (!response.ok || envelope.error) {
      const code = String(
        envelope?.error?.status || envelope?.error?.message || response.status,
      ).slice(0, 160);
      throw new Error(`callable_error:${code}`);
    }
    const result = envelope.result ?? envelope.data;
    if (!result || typeof result !== "object") {
      throw new Error("callable_result_missing");
    }
    return result;
  } finally {
    clearTimeout(timer);
  }
}

function payload(message, state, history = [], brain = true) {
  return {
    message,
    history,
    weatherContext: {},
    clientContext: {
      ...(brain ? {conversationBrainVersion: "brain_v1"} : {}),
      timezone: "Europe/Bratislava",
      nowIso: new Date().toISOString(),
    },
    outfitContextState: state,
    mode: "chat",
    includeWardrobe: false,
  };
}

function summarize(data) {
  const reply = typeof data.reply === "string" ? data.reply.trim() : "";
  const action = String(data.action || "").trim();
  const webResearch =
    data.webResearch && typeof data.webResearch === "object" ? data.webResearch : null;
  return {
    reply,
    action,
    webResearch,
    webUsed: webResearch?.used === true,
    webCallCount: Number(webResearch?.callCount || 0),
  };
}

function assertCore(result, label) {
  if (!result.reply) throw new Error(`${label}:reply_missing`);
  if (!allowedActions.has(result.action)) {
    throw new Error(`${label}:action_invalid:${result.action || "missing"}`);
  }
}

async function run() {
  const simpleState = {groundingStatus: "sufficient", unresolvedMaterialFields: []};
  const simpleMessage = "Hodí sa biele tričko k tmavomodrým džínsom?";
  let auth = null;

  try {
    auth = await createEphemeralAuth();

    // Diagnostic gate: legacy must work for the same authenticated test user.
    const legacyStarted = Date.now();
    const legacy = summarize(
      await callStylist(payload(simpleMessage, simpleState, [], false), auth.idToken),
    );
    assertCore(legacy, "legacy_baseline");
    console.log(
      `Brain deployed QA | legacy-baseline | PASS | action=${legacy.action} ` +
        `replyLen=${legacy.reply.length} durationMs=${Date.now() - legacyStarted}`,
    );

    // Brain gate prevents the full paid suite from running against a broken deploy.
    const brainGateStarted = Date.now();
    const brainGate = summarize(
      await callStylist(payload(simpleMessage, simpleState, [], true), auth.idToken),
    );
    assertCore(brainGate, "brain_simple_gate");
    if (brainGate.webUsed) throw new Error("brain_simple_gate:unexpected_web");
    console.log(
      `Brain deployed QA | brain-simple-gate | PASS | action=${brainGate.action} ` +
        `web=${brainGate.webUsed} calls=${brainGate.webCallCount} ` +
        `replyLen=${brainGate.reply.length} durationMs=${Date.now() - brainGateStarted}`,
    );

    const scenarios = [
      {
        id: "current-public-event-needs-web",
        turns: [
          {
            message: "O tri týždne idem do Michaloviec na koncert AC/DC. Čo si mám obliecť?",
            state: {
              activityLocationLabel: "Michalovce",
              activityLocationKnown: true,
              activityHint: "concert",
              groundingStatus: "sufficient",
              unresolvedMaterialFields: [],
            },
            expectWeb: true,
          },
        ],
      },
      {
        id: "unknown-public-term-needs-web-before-clarify",
        turns: [
          {
            message:
              "Na pozvánke na verejné podujatie mám dress code 'Neo Alpine Formal 2026'. Čo to znamená pre outfit?",
            state: {
              groundingStatus: "needs_grounding",
              unresolvedMaterialFields: ["activity"],
            },
            expectWeb: true,
          },
        ],
      },
      {
        id: "private-shorthand-must-not-use-web",
        turns: [
          {
            message:
              "S kamarátmi máme súkromnú skratku 'modrý režim'. Zajtra ideme na modrý režim, čo si mám obliecť?",
            state: {
              groundingStatus: "needs_grounding",
              unresolvedMaterialFields: ["activity", "destination"],
            },
            expectWeb: false,
            actions: ["clarify", "chat"],
          },
        ],
      },
      {
        id: "private-place-must-not-use-web",
        turns: [
          {
            message: "Zajtra idem s Katkou na naše miesto. Čo si mám dať?",
            state: {
              groundingStatus: "needs_grounding",
              unresolvedMaterialFields: ["activity", "destination"],
            },
            expectWeb: false,
            actions: ["clarify", "chat"],
          },
        ],
      },
      {
        id: "topic-switch-does-not-carry-stale-research",
        turns: [
          {
            message: "O tri týždne idem do Michaloviec na koncert AC/DC. Čo si mám obliecť?",
            state: {
              activityLocationLabel: "Michalovce",
              activityLocationKnown: true,
              activityHint: "concert",
              groundingStatus: "sufficient",
              unresolvedMaterialFields: [],
            },
            expectWeb: true,
          },
          {
            message:
              "Inak nechaj koncert tak. Hodí sa všeobecne čierne tričko k sivým nohaviciam?",
            state: {groundingStatus: "sufficient", unresolvedMaterialFields: []},
            expectWeb: false,
            actions: ["chat"],
            forbiddenReplyTerms: ["AC/DC", "Michalov"],
          },
        ],
      },
    ];

    let failed = false;
    let requestCount = 2;
    for (const scenario of scenarios) {
      const history = [];
      for (let i = 0; i < scenario.turns.length; i += 1) {
        const turn = scenario.turns[i];
        requestCount += 1;
        const started = Date.now();
        try {
          const result = summarize(
            await callStylist(payload(turn.message, turn.state, history, true), auth.idToken),
          );
          const failures = [];
          if (!result.reply) failures.push("reply_missing");
          if (!allowedActions.has(result.action)) {
            failures.push(`action_invalid:${result.action || "missing"}`);
          }
          if (result.webUsed !== turn.expectWeb) {
            failures.push(`web_expected_${turn.expectWeb}_actual_${result.webUsed}`);
          }
          if (result.webCallCount < 0 || result.webCallCount > 3) {
            failures.push(`web_call_count:${result.webCallCount}`);
          }
          if (Array.isArray(turn.actions) && !turn.actions.includes(result.action)) {
            failures.push(
              `action_expected_${turn.actions.join("|")}_actual_${result.action}`,
            );
          }
          for (const term of turn.forbiddenReplyTerms || []) {
            if (result.reply.toLowerCase().includes(term.toLowerCase())) {
              failures.push(`stale_reply_term:${term}`);
            }
          }
          const publicKeys = Object.keys(result.webResearch?.publicContext || {});
          console.log(
            `Brain deployed QA | ${scenario.id}#${i + 1} | ` +
              `${failures.length ? "FAIL" : "PASS"} | action=${result.action || "missing"} ` +
              `web=${result.webUsed} calls=${result.webCallCount} replyLen=${result.reply.length} ` +
              `publicKeys=${publicKeys.join(",") || "-"} durationMs=${Date.now() - started}`,
          );
          if (failures.length) {
            failed = true;
            console.log(`  failures=${failures.join(",")}`);
          }
          history.push({role: "user", content: turn.message});
          history.push({role: "assistant", content: result.reply});
          if (history.length > 8) history.splice(0, history.length - 8);
        } catch (error) {
          failed = true;
          console.log(
            `Brain deployed QA | ${scenario.id}#${i + 1} | ERROR | ` +
              String(error?.message || error).slice(0, 240),
          );
        }
      }
    }
    console.log(`Brain deployed QA | requests=${requestCount} | passed=${!failed}`);
    if (failed) process.exitCode = 1;
  } catch (error) {
    console.log(
      `Brain deployed QA | ABORT | ${String(error?.message || error).slice(0, 240)}`,
    );
    process.exitCode = 1;
  } finally {
    if (auth?.idToken) await deleteEphemeralAuth(auth.idToken);
  }
}

run().catch((error) => {
  console.log(
    `Brain deployed QA | FATAL | ${String(error?.message || error).slice(0, 240)}`,
  );
  process.exitCode = 1;
});
