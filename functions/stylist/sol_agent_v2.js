"use strict";

const SOL_AGENT_V2_MODEL = "gpt-5.6-sol";
const SOL_AGENT_V2_VERSION = "sol_v2";
const SOL_AGENT_V2_MAX_OUTPUT_TOKENS = 900;
const SOL_AGENT_V2_MAX_TOOL_CALLS = 3;
const SOL_AGENT_V2_PROVIDER_TIMEOUT_MS = 55000;

const SOL_AGENT_V2_INSTRUCTIONS = [
  "Si hlavný konverzačný mozog módnej appky Outfit Of The Day (OOTD).",
  "Komunikuj prirodzene po slovensky, tykaj a správaj sa ako veľmi dobrý osobný stylista a inteligentný chat partner.",
  "Rozumej bežnej reči, preklepom, slangu, nadväzuj na kontext a neodpovedaj ako formulár ani zákaznícka podpora.",
  "Používateľ nemusí riešiť iba módu; na bežnú otázku reaguj normálne a nestrhávaj každú tému naspäť k outfitu.",
  "Ak používateľ pošle obrázok, naozaj ho vizuálne analyzuj a odpovedz na to, čo sa pýta.",
  "Ak potrebuješ aktuálny alebo verejne overiteľný fakt, použi web_search namiesto hádania. Verejné fakty môžeš overovať autonómne.",
  "Nepredstieraj prístup k súkromným dátam, ktoré si nedostal. V tejto prvej verzii nemáš nástroj na používateľov šatník ani autoritatívne počasie z appky.",
  "Ak radíš outfit bez prístupu k šatníku, nevymýšľaj, že používateľ konkrétny kúsok vlastní. Radíš všeobecne z informácií, ktoré máš.",
  "Keď niečo podstatné naozaj chýba, polož jednu prirodzenú otázku; nepýtaj sa na veci, ktoré vieš rozumne vyriešiť alebo verejne overiť sám.",
  "Buď konkrétny, praktický a sebaistý, ale neprikrášľuj neistotu. Pri móde vysvetli dôvod ľudsky, nie technickými skóre alebo internými pravidlami.",
  "Nespomínaj model, API, prompt, interné nástroje, routing ani implementáciu appky.",
  "Dĺžku odpovede prispôsob otázke. Bežný chat drž skôr stručný; keď používateľ chce detail, pokojne choď viac do hĺbky.",
].join("\n");

function cleanText(value, max = 12000) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function isHttpUrl(value) {
  try {
    const url = new URL(String(value || ""));
    return url.protocol === "https:" || url.protocol === "http:";
  } catch (_) {
    return false;
  }
}

function buildSolAgentV2Input({message, imageUrl}) {
  const text = cleanText(message, 12000) ||
    (imageUrl ? "Pozri sa na túto fotku a reaguj prirodzene podľa toho, čo na nej vidíš." : "");
  const content = [];
  if (text) content.push({type: "input_text", text});
  if (imageUrl && isHttpUrl(imageUrl)) {
    content.push({type: "input_image", image_url: imageUrl, detail: "auto"});
  }
  return [{role: "user", content}];
}

function buildSolAgentV2Request({message, imageUrl, previousResponseId, clientNow}) {
  const input = buildSolAgentV2Input({message, imageUrl});
  if (!input[0].content.length) {
    const error = new Error("sol_agent_v2_empty_input");
    error.code = "invalid-argument";
    throw error;
  }

  const now = cleanText(clientNow, 120);
  const instructions = now ?
    `${SOL_AGENT_V2_INSTRUCTIONS}\n\nAktuálny čas používateľa podľa appky: ${now}` :
    SOL_AGENT_V2_INSTRUCTIONS;

  return {
    model: SOL_AGENT_V2_MODEL,
    instructions,
    input,
    tools: [{type: "web_search", search_context_size: "low"}],
    tool_choice: "auto",
    max_tool_calls: SOL_AGENT_V2_MAX_TOOL_CALLS,
    reasoning: {effort: "low"},
    max_output_tokens: SOL_AGENT_V2_MAX_OUTPUT_TOKENS,
    include: ["web_search_call.action.sources"],
    store: true,
    ...(previousResponseId ? {previous_response_id: previousResponseId} : {}),
  };
}

function extractSolAgentV2Text(json) {
  const direct = cleanText(json && json.output_text, 20000);
  if (direct) return direct;
  const chunks = [];
  for (const item of Array.isArray(json && json.output) ? json.output : []) {
    if (!item || item.type !== "message") continue;
    for (const part of Array.isArray(item.content) ? item.content : []) {
      if (part && part.type === "output_text") {
        const text = cleanText(part.text, 20000);
        if (text) chunks.push(text);
      }
    }
  }
  return chunks.join("\n").trim();
}

function extractSolAgentV2WebMeta(json) {
  let callCount = 0;
  const hosts = [];
  const seen = new Set();
  for (const item of Array.isArray(json && json.output) ? json.output : []) {
    if (!item || item.type !== "web_search_call") continue;
    callCount += 1;
    const sources = item.action && Array.isArray(item.action.sources) ? item.action.sources : [];
    for (const source of sources) {
      try {
        const host = new URL(String(source && source.url || "")).hostname.replace(/^www\./i, "");
        if (host && !seen.has(host)) {
          seen.add(host);
          hosts.push(host);
        }
      } catch (_) {}
    }
  }
  return Object.freeze({
    used: callCount > 0,
    callCount,
    sourceHosts: Object.freeze(hosts.slice(0, 12)),
  });
}

function safeProviderErrorCode(error) {
  const code = cleanText(error && (error.code || error.name), 80);
  return code || "unknown";
}

function createSolAgentV2Handler({
  db,
  fetchImpl,
  resolveOpenAISecret,
  logger,
  serverTimestamp,
  httpsError,
} = {}) {
  if (!db || typeof fetchImpl !== "function" || typeof resolveOpenAISecret !== "function") {
    throw new Error("sol_agent_v2_dependencies_missing");
  }
  const log = logger || console;
  const makeHttpsError = typeof httpsError === "function" ? httpsError :
    (code, message) => Object.assign(new Error(message), {code});
  const timestamp = typeof serverTimestamp === "function" ? serverTimestamp : () => new Date();

  return async function stylistAgentV2(data, context) {
    const uid = cleanText(context && context.auth && context.auth.uid, 256);
    if (!uid) throw makeHttpsError("unauthenticated", "auth_required");

    const message = cleanText(data && data.message, 12000);
    const sessionId = cleanText(data && data.sessionId, 180);
    const chatId = cleanText(data && data.chatId, 180);
    const stateId = sessionId || chatId;
    const imageUrlRaw = cleanText(data && data.imageUrl, 2000);
    const imageUrl = imageUrlRaw && isHttpUrl(imageUrlRaw) ? imageUrlRaw : "";
    const clientNow = cleanText(data && data.clientNow, 120);

    if (!stateId) throw makeHttpsError("invalid-argument", "session_id_required");
    if (!message && !imageUrl) throw makeHttpsError("invalid-argument", "message_or_image_required");

    const sessions = db.collection("users").doc(uid).collection("stylistAgentV2Sessions");
    const sessionRef = sessions.doc(stateId);
    const persistedChatRef = chatId && chatId !== stateId ? sessions.doc(chatId) : null;

    let previousResponseId = "";
    try {
      const snapshot = await sessionRef.get();
      previousResponseId = cleanText(snapshot && snapshot.data && snapshot.data()?.previousResponseId, 200);
      // Existing chats opened after an app restart use their persisted chatId.
      // During the first live session a temporary sessionId may be used before
      // the local chat document exists; once chatId appears we mirror state to it.
      if (!previousResponseId && persistedChatRef) {
        const persistedSnapshot = await persistedChatRef.get();
        previousResponseId = cleanText(
          persistedSnapshot && persistedSnapshot.data && persistedSnapshot.data()?.previousResponseId,
          200,
        );
      }
    } catch (error) {
      log.warn("stylistAgentV2 session read failed", {
        code: safeProviderErrorCode(error),
      });
      throw makeHttpsError("unavailable", "agent_session_unavailable");
    }

    let apiKey;
    try {
      apiKey = resolveOpenAISecret();
    } catch (error) {
      log.error("stylistAgentV2 secret unavailable", {
        code: safeProviderErrorCode(error),
      });
      throw makeHttpsError("internal", "stylist_agent_v2_unavailable");
    }

    const body = buildSolAgentV2Request({
      message,
      imageUrl,
      previousResponseId,
      clientNow,
    });
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), SOL_AGENT_V2_PROVIDER_TIMEOUT_MS);
    const startedAt = Date.now();

    try {
      const response = await fetchImpl("https://api.openai.com/v1/responses", {
        method: "POST",
        signal: controller.signal,
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify(body),
      });

      if (!response.ok) {
        let providerCode = `http_${response.status}`;
        try {
          const errorJson = await response.json();
          providerCode = cleanText(errorJson && errorJson.error &&
            (errorJson.error.code || errorJson.error.type), 80) || providerCode;
        } catch (_) {}
        log.error("stylistAgentV2 provider rejected request", {
          status: response.status,
          providerCode,
          durationMs: Date.now() - startedAt,
          hadPreviousResponse: Boolean(previousResponseId),
        });
        throw makeHttpsError("internal", "stylist_agent_v2_provider_error");
      }

      const json = await response.json();
      const reply = extractSolAgentV2Text(json);
      const responseId = cleanText(json && json.id, 200);
      const web = extractSolAgentV2WebMeta(json);
      if (!reply || !responseId) {
        log.error("stylistAgentV2 incomplete provider response", {
          hasReply: Boolean(reply),
          hasResponseId: Boolean(responseId),
          durationMs: Date.now() - startedAt,
        });
        throw makeHttpsError("internal", "stylist_agent_v2_empty_response");
      }

      const statePatch = {
        previousResponseId: responseId,
        model: SOL_AGENT_V2_MODEL,
        agentVersion: SOL_AGENT_V2_VERSION,
        updatedAt: timestamp(),
      };
      await sessionRef.set(statePatch, {merge: true});
      if (persistedChatRef) await persistedChatRef.set(statePatch, {merge: true});

      log.info("stylistAgentV2 completed", {
        model: SOL_AGENT_V2_MODEL,
        agentVersion: SOL_AGENT_V2_VERSION,
        durationMs: Date.now() - startedAt,
        replyChars: reply.length,
        imageAttached: Boolean(imageUrl),
        usedPreviousResponse: Boolean(previousResponseId),
        mirroredToPersistedChat: Boolean(persistedChatRef),
        webSearchUsed: web.used,
        webSearchCalls: web.callCount,
        webSourceHosts: web.sourceHosts,
      });

      return {
        reply,
        action: "chat",
        suggestedItems: [],
        agentVersion: SOL_AGENT_V2_VERSION,
        model: SOL_AGENT_V2_MODEL,
        webSearchUsed: web.used,
        webSearchCalls: web.callCount,
      };
    } catch (error) {
      if (error && typeof error.code === "string" &&
          ["internal", "unavailable", "invalid-argument", "unauthenticated"].includes(error.code)) {
        throw error;
      }
      const aborted = error && error.name === "AbortError";
      log.error("stylistAgentV2 failed", {
        code: safeProviderErrorCode(error),
        aborted,
        durationMs: Date.now() - startedAt,
      });
      throw makeHttpsError(
        aborted ? "deadline-exceeded" : "internal",
        aborted ? "stylist_agent_v2_timeout" : "stylist_agent_v2_failed",
      );
    } finally {
      clearTimeout(timer);
    }
  };
}

module.exports = {
  SOL_AGENT_V2_MODEL,
  SOL_AGENT_V2_VERSION,
  SOL_AGENT_V2_INSTRUCTIONS,
  buildSolAgentV2Input,
  buildSolAgentV2Request,
  extractSolAgentV2Text,
  extractSolAgentV2WebMeta,
  createSolAgentV2Handler,
};
