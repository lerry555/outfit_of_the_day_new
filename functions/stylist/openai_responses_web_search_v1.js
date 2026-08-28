"use strict";

function cleanText(value, max = 8000) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function normalizeResponsesInputV1(messages) {
  if (!Array.isArray(messages)) return [];
  return messages.map((message) => {
    const roleRaw = String(message && message.role || "user").trim();
    const role = ["system", "developer", "assistant", "user"].includes(roleRaw) ?
      roleRaw : "user";
    const content = cleanText(message && message.content, 24000);
    return {
      role,
      content: [{type: "input_text", text: content}],
    };
  }).filter((message) => message.content[0].text.length > 0);
}

function buildConversationBrainResponsesBodyV1({
  model,
  messages,
  maxOutputTokens = 900,
  reasoningEffort = "low",
  searchContextSize = "low",
} = {}) {
  const modelId = cleanText(model, 120);
  if (!modelId) throw new Error("conversation_brain_responses_model_missing");
  const maxTokens = Number.isFinite(Number(maxOutputTokens)) ?
    Math.max(128, Math.min(4096, Math.round(Number(maxOutputTokens)))) : 900;
  const effort = ["none", "low", "medium", "high", "xhigh", "max"]
    .includes(String(reasoningEffort)) ? String(reasoningEffort) : "low";
  const contextSize = ["low", "medium", "high"].includes(String(searchContextSize)) ?
    String(searchContextSize) : "low";

  return {
    model: modelId,
    input: normalizeResponsesInputV1(messages),
    tools: [{type: "web_search", search_context_size: contextSize}],
    tool_choice: "auto",
    // Guard one Brain execution against tool loops. Every later chat turn builds
    // a fresh Responses request and receives its own allowance.
    max_tool_calls: 3,
    include: ["web_search_call.action.sources"],
    reasoning: {effort},
    max_output_tokens: maxTokens,
    text: {format: {type: "json_object"}},
    store: false,
  };
}

function extractConversationBrainResponseTextV1(json) {
  const direct = cleanText(json && json.output_text, 16000);
  if (direct) return direct;
  const parts = [];
  for (const item of Array.isArray(json && json.output) ? json.output : []) {
    if (!item || item.type !== "message") continue;
    for (const content of Array.isArray(item.content) ? item.content : []) {
      if (content && content.type === "output_text") {
        const text = cleanText(content.text, 16000);
        if (text) parts.push(text);
      }
    }
  }
  return parts.join("").trim();
}

function safeWebSource(source) {
  const url = cleanText(source && source.url, 1200);
  if (!/^https?:\/\//i.test(url)) return null;
  return {
    title: cleanText(source && source.title, 240) || null,
    url,
  };
}

function safeInteger(value, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number) || !Number.isInteger(number)) return null;
  if (number < min || number > max) return null;
  return number;
}

function normalizeVenueType(value) {
  const raw = cleanText(value, 80).toLowerCase();
  if (!raw) return null;
  if (raw.includes("outdoor") || raw.includes("vonku")) return "outdoor";
  if (raw.includes("formal") || raw.includes("gala") || raw.includes("filharmon")) {
    return "indoor_formal";
  }
  if (raw.includes("indoor") || raw.includes("vnútri") || raw.includes("vnutri")) {
    return "indoor_casual";
  }
  if (raw === "any") return "any";
  return null;
}

function safePublicResearchContext(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const out = {};

  const performer = cleanText(raw.performer || raw.artist, 160);
  if (performer) out.performer = performer;

  const dressRaw = raw.dressCode && typeof raw.dressCode === "object" &&
    !Array.isArray(raw.dressCode) ? raw.dressCode : null;
  if (dressRaw) {
    const formalityTarget = safeInteger(
      dressRaw.formalityTarget ?? dressRaw.formality,
      1,
      10,
    );
    if (formalityTarget != null) {
      const dressCode = {formalityTarget};
      const id = cleanText(dressRaw.id, 80);
      const labelSk = cleanText(dressRaw.labelSk || dressRaw.label, 120);
      const venueType = normalizeVenueType(dressRaw.venueType || dressRaw.venue);
      if (id) dressCode.id = id;
      if (labelSk) dressCode.labelSk = labelSk;
      if (venueType) dressCode.venueType = venueType;
      out.dressCode = Object.freeze(dressCode);
    }
  }

  const eventStartHour = safeInteger(raw.eventStartHour, 0, 23);
  const eventEndHour = safeInteger(raw.eventEndHour, 0, 23);
  const durationMinutes = safeInteger(raw.durationMinutes, 1, 7 * 24 * 60);
  if (eventStartHour != null) out.eventStartHour = eventStartHour;
  if (eventEndHour != null) out.eventEndHour = eventEndHour;
  if (durationMinutes != null) out.durationMinutes = durationMinutes;

  return Object.keys(out).length ? Object.freeze(out) : null;
}

function extractPublicResearchContextFromResponse(json) {
  const text = extractConversationBrainResponseTextV1(json);
  if (!text) return null;
  try {
    const parsed = JSON.parse(text);
    const eventContext = parsed && parsed.eventContext;
    const publicResearch = eventContext && typeof eventContext === "object" &&
      !Array.isArray(eventContext) ? eventContext.publicResearch : null;
    return safePublicResearchContext(publicResearch);
  } catch (_) {
    return null;
  }
}

function extractConversationBrainWebResearchV1(json) {
  const output = Array.isArray(json && json.output) ? json.output : [];
  let callCount = 0;
  const sources = [];
  const seen = new Set();

  const add = (raw) => {
    const source = safeWebSource(raw);
    if (!source || seen.has(source.url)) return;
    seen.add(source.url);
    sources.push(source);
  };

  for (const item of output) {
    if (!item) continue;
    if (item.type === "web_search_call") {
      callCount += 1;
      const actionSources = item.action && Array.isArray(item.action.sources) ?
        item.action.sources : [];
      actionSources.forEach(add);
    }
    if (item.type === "message") {
      for (const content of Array.isArray(item.content) ? item.content : []) {
        for (const annotation of Array.isArray(content && content.annotations) ?
          content.annotations : []) {
          if (annotation && annotation.type === "url_citation") add(annotation);
        }
      }
    }
  }

  const publicContext = callCount > 0 ?
    extractPublicResearchContextFromResponse(json) : null;
  return Object.freeze({
    used: callCount > 0,
    callCount,
    sources: Object.freeze(sources.slice(0, 12).map(Object.freeze)),
    ...(publicContext ? {publicContext} : {}),
  });
}

module.exports = {
  normalizeResponsesInputV1,
  buildConversationBrainResponsesBodyV1,
  extractConversationBrainResponseTextV1,
  extractConversationBrainWebResearchV1,
  safePublicResearchContext,
};
