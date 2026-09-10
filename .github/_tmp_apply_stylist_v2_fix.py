from pathlib import Path


def replace_once(path, old, new, label):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 anchor, found {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


# Session schema: additive, backward-compatible scenario memory.
path = "functions/stylist/v2/stylist_session_state_v2.js"
replace_once(path, "const MAX_HISTORY = 50;\nconst MAX_COLLECTION = 100;\n", "const MAX_HISTORY = 50;\nconst MAX_COLLECTION = 100;\nconst MAX_SCENARIO_SNAPSHOTS = 8;\n", "session constants")
replace_once(path, "      activity: null, terrain: emptyTerrain(), weather: null,\n", "      activity: null, environment: null, terrain: emptyTerrain(), weather: null,\n", "session environment")
replace_once(path, "    wardrobePreferences: {wardrobeRevision: null, preferencesRevision: null, retrievalCache: null},\n    replay: {turns: []},\n", "    wardrobePreferences: {wardrobeRevision: null, preferencesRevision: null, retrievalCache: null},\n    scenarioMemory: {activeScenarioId: null, snapshots: []},\n    replay: {turns: []},\n", "session scenario memory")
replace_once(path, "function validateStylistSessionStateV2(state) {\n  if (!state || state.schemaVersion !== 2 || typeof state.chatId !== \"string\") throw new TypeError(\"invalid StylistSessionStateV2 identity\");\n", "function normalizeBackwardCompatibleStateV2(state) {\n  const normalized = clone(state);\n  if (normalized?.context && !Object.prototype.hasOwnProperty.call(normalized.context, \"environment\")) {\n    normalized.context.environment = null;\n  }\n  if (normalized && !normalized.scenarioMemory) {\n    normalized.scenarioMemory = {activeScenarioId: null, snapshots: []};\n  }\n  return normalized;\n}\n\nfunction validateStylistSessionStateV2(state) {\n  state = normalizeBackwardCompatibleStateV2(state);\n  if (!state || state.schemaVersion !== 2 || typeof state.chatId !== \"string\") throw new TypeError(\"invalid StylistSessionStateV2 identity\");\n", "session backward compatibility")
replace_once(path, "  if (!Number.isInteger(state.revision) || state.revision < 0) throw new TypeError(\"invalid session revision\");\n  validateLocationObservation(state.context.currentLocationObservation, \"currentLocationObservation\");\n", "  if (!Number.isInteger(state.revision) || state.revision < 0) throw new TypeError(\"invalid session revision\");\n  if (![null, \"indoor\", \"outdoor\", \"mixed\"].includes(state.context.environment)) throw new TypeError(\"invalid scenario environment\");\n  validateLocationObservation(state.context.currentLocationObservation, \"currentLocationObservation\");\n", "session environment validation")
replace_once(path, "  const boundedCollections = [outfit.compromises, outfit.missingWardrobeNeeds, outfit.selectionReasonHistory,\n", "  const scenarioMemory = state.scenarioMemory;\n  if (!scenarioMemory || !Array.isArray(scenarioMemory.snapshots) || scenarioMemory.snapshots.length > MAX_SCENARIO_SNAPSHOTS) throw new TypeError(\"scenario memory must be bounded\");\n  const scenarioIds = scenarioMemory.snapshots.map((snapshot) => snapshot?.id);\n  if (scenarioIds.some((id) => typeof id !== \"string\" || !id.trim()) || new Set(scenarioIds).size !== scenarioIds.length) throw new TypeError(\"scenario snapshot IDs must be unique\");\n  if (scenarioMemory.activeScenarioId != null && !scenarioIds.includes(scenarioMemory.activeScenarioId)) throw new TypeError(\"active scenario must reference a stored snapshot\");\n  for (const snapshot of scenarioMemory.snapshots) {\n    if (!snapshot.context || !snapshot.outfit || !Array.isArray(snapshot.referenceSignals) || snapshot.referenceSignals.length > 20 || !Array.isArray(snapshot.outfit.itemIds) || snapshot.outfit.itemIds.length > MAX_COLLECTION || new Set(snapshot.outfit.itemIds).size !== snapshot.outfit.itemIds.length || !sameStringMembers(Object.keys(snapshot.outfit.selectionReasonsByItemId || {}), snapshot.outfit.itemIds)) throw new TypeError(\"invalid scenario snapshot\");\n    if (![null, \"indoor\", \"outdoor\", \"mixed\"].includes(snapshot.context.environment ?? null)) throw new TypeError(\"invalid scenario snapshot environment\");\n  }\n\n  const boundedCollections = [outfit.compromises, outfit.missingWardrobeNeeds, outfit.selectionReasonHistory,\n", "session scenario validation")
replace_once(path, "module.exports = {MAX_COLLECTION, MAX_HISTORY, TERRAIN_SURFACES, TERRAIN_DIFFICULTIES, TERRAIN_CONDITIONS,\n  bootstrapExistingChatV2, bounded, clone, createEmptySessionStateV2, deepFreeze, emptyTerrain, validateStylistSessionStateV2};\n", "module.exports = {MAX_COLLECTION, MAX_HISTORY, MAX_SCENARIO_SNAPSHOTS, TERRAIN_SURFACES, TERRAIN_DIFFICULTIES, TERRAIN_CONDITIONS,\n  bootstrapExistingChatV2, bounded, clone, createEmptySessionStateV2, deepFreeze, emptyTerrain, normalizeBackwardCompatibleStateV2,\n  validateStylistSessionStateV2};\n", "session exports")

# Generic scenario-memory module.
scenario_path = Path("functions/stylist/v2/stylist_scenario_memory_v2.js")
if scenario_path.exists():
    raise SystemExit("scenario memory module unexpectedly already exists")
scenario_path.write_text(r'''"use strict";

const {MAX_SCENARIO_SNAPSHOTS, bounded, clone, emptyTerrain} = require("./stylist_session_state_v2");

const RELEVANT_ANSWERED_FIELDS = [
  "destination", "eventLocation", "date", "timeWindow",
  "terrain.surface", "terrain.difficulty", "terrain.condition",
];

function normalizeSemanticTextV2(value) {
  return String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, " ").replace(/\s+/g, " ").trim();
}
function cleanSignalV2(value, max = 180) {
  const text = String(value || "").trim().replace(/\s+/g, " ");
  return text ? text.slice(0, max) : "";
}
function snapshotReferenceSignalsV2(state) {
  const context = state?.context || {};
  const raw = [context.activity?.id, context.activity?.label, context.destination?.label,
    context.eventLocation?.label, context.date?.dateKey, context.timeWindow?.key, context.timeWindow?.label]
    .map((value) => cleanSignalV2(value)).filter(Boolean);
  return [...new Set(raw)].slice(0, 20);
}
function scenarioLabelV2(state) {
  const context = state?.context || {};
  const parts = [context.activity?.label || context.activity?.id, context.eventLocation?.label || context.destination?.label,
    context.date?.dateKey, context.timeWindow?.label || context.timeWindow?.key]
    .map((value) => cleanSignalV2(value, 100)).filter(Boolean);
  return parts.join(" · ").slice(0, 280) || "outfit scenario";
}
function snapshotFromStateV2(state, id) {
  const weather = state?.context?.weather;
  return {
    id, label: scenarioLabelV2(state), referenceSignals: snapshotReferenceSignalsV2(state),
    context: {
      activity: clone(state.context.activity), date: clone(state.context.date), timeWindow: clone(state.context.timeWindow),
      destination: clone(state.context.destination), eventLocation: clone(state.context.eventLocation),
      terrain: clone(state.context.terrain || emptyTerrain()), environment: state.context.environment ?? null,
      groundingRequirements: clone(state.context.groundingRequirements),
    },
    weatherReference: weather ? {locationProviderId: weather.locationProviderId, dateKey: weather.dateKey,
      timeWindowKey: weather.timeWindowKey, fetchedAt: weather.fetchedAt, source: weather.source} : null,
    outfit: {itemIds: [...state.currentOutfit.itemIds], selectionReasonsByItemId: {...state.currentOutfit.selectionReasonsByItemId},
      compromises: bounded(state.currentOutfit.compromises), missingWardrobeNeeds: bounded(state.currentOutfit.missingWardrobeNeeds)},
    updatedAtRevision: state.revision,
  };
}
function scenarioIdForTurnV2(state, turnId) {
  const safeTurn = cleanSignalV2(turnId, 100).replace(/[^A-Za-z0-9_-]/g, "_");
  const seed = safeTurn || `r${Number.isInteger(state?.revision) ? state.revision : 0}`;
  let candidate = `scenario_${seed}`;
  const ids = new Set(state.scenarioMemory.snapshots.map((snapshot) => snapshot.id));
  let suffix = 2;
  while (ids.has(candidate)) candidate = `scenario_${seed}_${suffix++}`;
  return candidate;
}
function upsertScenarioSnapshotV2(state, {turnId = null} = {}) {
  const next = clone(state);
  if (!next.currentOutfit?.itemIds?.length) return next;
  const snapshots = Array.isArray(next.scenarioMemory?.snapshots) ? [...next.scenarioMemory.snapshots] : [];
  const activeId = next.scenarioMemory?.activeScenarioId;
  const activeIndex = activeId ? snapshots.findIndex((snapshot) => snapshot.id === activeId) : -1;
  const id = activeIndex >= 0 ? activeId : scenarioIdForTurnV2(next, turnId);
  const snapshot = snapshotFromStateV2(next, id);
  if (activeIndex >= 0) snapshots.splice(activeIndex, 1);
  snapshots.push(snapshot);
  next.scenarioMemory = {activeScenarioId: id, snapshots: snapshots.slice(-MAX_SCENARIO_SNAPSHOTS)};
  return next;
}
function clearScenarioClarificationsV2(next) {
  const answered = next.conversationMemory?.answeredClarificationFields;
  if (answered && typeof answered === "object") for (const key of RELEVANT_ANSWERED_FIELDS) delete answered[key];
  next.conversationMemory.pendingQuestion = null;
  next.conversationMemory.pendingAction = null;
}
function beginNewScenarioV2(state) {
  const next = clone(state);
  const currentLocationObservation = clone(next.context.currentLocationObservation);
  next.context = {currentLocationObservation, destination: null, eventLocation: null, date: null, timeWindow: null,
    activity: null, environment: null, terrain: emptyTerrain(), weather: null,
    groundingRequirements: {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []}};
  next.currentOutfit = {...next.currentOutfit, itemIds: [], selectionReasonsByItemId: {}, compromises: [], missingWardrobeNeeds: []};
  next.scenarioMemory.activeScenarioId = null;
  clearScenarioClarificationsV2(next);
  return next;
}
function restoreScenarioSnapshotV2(state, scenarioId) {
  const next = clone(state);
  const snapshot = next.scenarioMemory?.snapshots?.find((entry) => entry.id === scenarioId);
  if (!snapshot) return next;
  const context = snapshot.context || {};
  next.context.activity = clone(context.activity); next.context.date = clone(context.date);
  next.context.timeWindow = clone(context.timeWindow); next.context.destination = clone(context.destination);
  next.context.eventLocation = clone(context.eventLocation); next.context.terrain = clone(context.terrain || emptyTerrain());
  next.context.environment = context.environment ?? null;
  next.context.groundingRequirements = clone(context.groundingRequirements || {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []});
  next.context.weather = null;
  next.currentOutfit.itemIds = [...snapshot.outfit.itemIds];
  next.currentOutfit.selectionReasonsByItemId = {...snapshot.outfit.selectionReasonsByItemId};
  next.currentOutfit.compromises = bounded(snapshot.outfit.compromises);
  next.currentOutfit.missingWardrobeNeeds = bounded(snapshot.outfit.missingWardrobeNeeds);
  clearScenarioClarificationsV2(next);
  const answered = next.conversationMemory.answeredClarificationFields;
  if (next.context.destination) answered.destination = clone(next.context.destination);
  if (next.context.eventLocation) answered.eventLocation = clone(next.context.eventLocation);
  if (next.context.date) answered.date = clone(next.context.date);
  if (next.context.timeWindow) answered.timeWindow = clone(next.context.timeWindow);
  for (const field of ["surface", "difficulty", "condition"]) if (next.context.terrain?.[field] != null) answered[`terrain.${field}`] = next.context.terrain[field];
  next.scenarioMemory.activeScenarioId = snapshot.id;
  return next;
}
function rootsForTextV2(value) {
  return new Set(normalizeSemanticTextV2(value).split(" ").filter((token) => token.length >= 4).map((token) => token.slice(0, 3)));
}
function hasExplicitScenarioBackreferenceV2({latestUserInput, state}) {
  const memory = state?.scenarioMemory;
  if (!memory || !Array.isArray(memory.snapshots) || !memory.snapshots.length) return false;
  const candidates = memory.snapshots.filter((snapshot) => snapshot.id !== memory.activeScenarioId);
  if (!candidates.length) return false;
  const text = normalizeSemanticTextV2(latestUserInput);
  if (!text) return false;
  if (/\b(vratme sa|vrat sa|spat k|spat ku|predchadzajuc|stars scenar|co sme riesili|co sme mali)\b/.test(text)) return true;
  if (!/\b(ten|tento|tato|tuto|tu|to|tamten|tamtu|predchadzajuci|predchadzajucu|starsiu|starsi)\b/.test(text)) return false;
  const messageRoots = rootsForTextV2(text);
  return candidates.some((snapshot) => {
    const snapshotRoots = rootsForTextV2([snapshot.label, ...(snapshot.referenceSignals || [])].join(" "));
    return [...messageRoots].some((root) => snapshotRoots.has(root));
  });
}
module.exports = {beginNewScenarioV2, hasExplicitScenarioBackreferenceV2, restoreScenarioSnapshotV2,
  scenarioLabelV2, snapshotReferenceSignalsV2, upsertScenarioSnapshotV2};
''', encoding="utf-8")

# Grounding: preserve explicit backreferences and clear current outfit on genuinely new scenarios.
path = "functions/stylist/v2/stylist_grounding_policy_v2.js"
replace_once(path, '"use strict";\n\nfunction clone(value) { return value == null ? value : JSON.parse(JSON.stringify(value)); }\n', '"use strict";\n\nconst {beginNewScenarioV2, hasExplicitScenarioBackreferenceV2} = require("./stylist_scenario_memory_v2");\n\nfunction clone(value) { return value == null ? value : JSON.parse(JSON.stringify(value)); }\n', "grounding imports")
replace_once(path, '  if (state?.conversationMemory?.pendingQuestion && PENDING_META_OR_SKIP_TERMS.test(text)) {\n    return {active: false, scope: "pending_followup", resetContext: false, requirements: null};\n  }\n  if (!isConcreteOutfitRequestV2(text)) {\n', '  if (state?.conversationMemory?.pendingQuestion && PENDING_META_OR_SKIP_TERMS.test(text)) {\n    return {active: false, scope: "pending_followup", resetContext: false, requirements: null};\n  }\n  if (hasExplicitScenarioBackreferenceV2({latestUserInput, state})) {\n    return {active: false, scope: "scenario_reference", resetContext: false, requirements: null};\n  }\n  if (!isConcreteOutfitRequestV2(text)) {\n', "grounding backreference defer")
old_reset = '''function applyMandatoryGroundingV2(state, policy) {
  if (!policy?.active) return clone(state);
  const next = clone(state);
  if (policy.resetContext) {
    next.context.activity = null;
    next.context.destination = null;
    next.context.eventLocation = null;
    next.context.date = null;
    next.context.timeWindow = null;
    next.context.weather = null;
    next.context.terrain = {surface: null, difficulty: null, condition: null};
    const answered = next.conversationMemory?.answeredClarificationFields;
    if (answered && typeof answered === "object") {
      for (const key of ["destination", "eventLocation", "date", "timeWindow", "terrain.surface", "terrain.difficulty", "terrain.condition"]) delete answered[key];
    }
    // A clearly new style-only/event request supersedes a clarification from
    // the previous task. Do not let stale pending state turn the new message
    // into a location-parser input.
    if (["style_only", "event"].includes(policy.scope)) {
      next.conversationMemory.pendingQuestion = null;
      next.conversationMemory.pendingAction = null;
    }
  }
'''
new_reset = '''function applyMandatoryGroundingV2(state, policy) {
  if (!policy?.active) return clone(state);
  let next = clone(state);
  if (policy.resetContext) next = beginNewScenarioV2(next);
'''
replace_once(path, old_reset, new_reset, "grounding reset scenario")
replace_once(path, '  for (const key of ["activity", "date", "timeWindow", "terrain"]) {\n', '  for (const key of ["activity", "date", "timeWindow", "terrain", "environment"]) {\n', "grounding environment shadow")

# OpenAI V2 model port: planner scenario mode, environment, safe indoor wording, accurate store CTA.
path = "functions/stylist/v2/openai_stylist_model_port_v2.js"
replace_once(path, '"use strict";\n\nconst PLAN_MODEL = "gpt-5.6-luna";\n', '"use strict";\n\nconst {hasExplicitScenarioBackreferenceV2} = require("./stylist_scenario_memory_v2");\n\nconst PLAN_MODEL = "gpt-5.6-luna";\n', "model scenario import")
replace_once(path, 'const TERRAIN_FIELDS = ["surface", "difficulty", "condition"];\nconst WARDROBE_SCOPES = ["none", "current_outfit", "current_outfit_plus_category", "category", "full_relevant"];\n', 'const TERRAIN_FIELDS = ["surface", "difficulty", "condition"];\nconst ENVIRONMENTS = ["unknown", "indoor", "outdoor", "mixed"];\nconst SCENARIO_MODES = ["current", "new", "restore"];\nconst WARDROBE_SCOPES = ["none", "current_outfit", "current_outfit_plus_category", "category", "full_relevant"];\n', "model enums")
replace_once(path, '    "activityId", "activityLabel", "dateKey", "timeWindowKey",\n    "terrainSurface", "terrainDifficulty", "terrainCondition",\n', '    "activityId", "activityLabel", "dateKey", "timeWindowKey", "environment",\n    "terrainSurface", "terrainDifficulty", "terrainCondition",\n', "patch schema required environment")
replace_once(path, '    timeWindowKey: nullableString(),\n    terrainSurface: {type: "string", enum: TERRAIN_SURFACES},\n', '    timeWindowKey: nullableString(),\n    environment: {type: "string", enum: ENVIRONMENTS},\n    terrainSurface: {type: "string", enum: TERRAIN_SURFACES},\n', "patch schema environment property")
replace_once(path, '    "kind", "action", "assistantText", "clarificationField", "clarificationQuestion",\n    "locationQuery", "locationTargetField", "wardrobeScope", "wardrobeCategory",\n', '    "kind", "action", "assistantText", "clarificationField", "clarificationQuestion",\n    "scenarioMode", "scenarioReferenceId",\n    "locationQuery", "locationTargetField", "wardrobeScope", "wardrobeCategory",\n', "plan schema scenario required")
replace_once(path, '    clarificationQuestion: {type: ["string", "null"]},\n    locationQuery: {type: ["string", "null"]},\n', '    clarificationQuestion: {type: ["string", "null"]},\n    scenarioMode: {type: "string", enum: SCENARIO_MODES},\n    scenarioReferenceId: nullableString(),\n    locationQuery: {type: ["string", "null"]},\n', "plan schema scenario props")
old_cta = '''function shoppingQuickReplyPromptV2(needLabel, canonicalNeed) {
  const normalized = normalizeIntentTextV2(`${needLabel || ""} ${canonicalNeed || ""}`);
  if (/\b(hiking|trekking|turist)/.test(normalized)) {
    return "Chceš, aby som ti vybral vhodnejšie turistické topánky?";
  }
  if (/\b(shoe|shoes|boot|boots|sneaker|footwear|topank|obuv)/.test(normalized)) {
    return "Chceš, aby som ti vybral vhodnejšie topánky?";
  }
  return "Chceš, aby som ti vybral vhodnejší kúsok do šatníka?";
}
'''
new_cta = '''function shoppingQuickReplyPromptV2(needLabel, canonicalNeed) {
  const normalized = normalizeIntentTextV2(`${needLabel || ""} ${canonicalNeed || ""}`);
  if (/\b(shoe|shoes|boot|boots|sneaker|footwear|topank|obuv)/.test(normalized)) {
    return "Chceš, aby som ti pozrel vhodné topánky v obchodoch?";
  }
  return "Chceš, aby som ti pozrel možnosti v obchodoch?";
}
'''
replace_once(path, old_cta, new_cta, "shopping CTA")
replace_once(path, 'function shouldPreloadCurrentOutfitV2(input) {\n  const currentIds = input?.session?.currentOutfit?.itemIds || [];\n', 'function shouldPreloadCurrentOutfitV2(input) {\n  if (hasExplicitScenarioBackreferenceV2({latestUserInput: input?.request?.latestUserInput, state: input?.session})) return false;\n  const currentIds = input?.session?.currentOutfit?.itemIds || [];\n', "preload old scenario")
replace_once(path, '    "Najnovšia správa má prioritu; starší kontext používaj ako pamäť, nie ako formulár, ktorý musíš znovu vypĺňať.",\n', '    "Najnovšia správa má prioritu; starší kontext používaj ako pamäť, nie ako formulár, ktorý musíš znovu vypĺňať.",\n    "Session môže obsahovať scenarioMemory.snapshots. scenarioMode=current použi pri obyčajnom follow-upe/editácii aktuálneho outfitu; scenarioMode=new pri prechode na inú aktuálnu aktivitu/occasion; scenarioMode=restore IBA keď používateľ explicitne odkazuje na starší scenár.",\n    "Pri scenarioMode=restore nastav scenarioReferenceId PRESNE na id najlepšieho semanticky zodpovedajúceho snapshotu. Nevyberaj ho iba podľa pár hard-coded udalostí; porovnaj význam celej správy s label/referenceSignals a štruktúrovaným kontextom snapshotov.",\n    "Po restore ber vyriešenú aktivitu, dátum, čas, miesto, terén a outfit snapshotu ako autoritatívnu pamäť. Nepýtaj sa znovu na údaj, ktorý snapshot už pozná. Pri \'daj mi iné tričko\' bez explicitného návratu nechaj scenarioMode=current a scenarioReferenceId=null.",\n', "planner scenario instructions")
replace_once(path, '    "Počasie pri remote/event outfite musí používať destination/eventLocation. Pri jasne lokálnom rutinnom outfite môže používať currentLocationObservation.",\n', '    "Počasie pri remote/event outfite musí používať destination/eventLocation. Pri jasne lokálnom rutinnom outfite môže používať currentLocationObservation.",\n    "V patch.environment klasifikuj hlavné prostredie nosenia outfitu semanticky ako indoor, outdoor, mixed alebo unknown. Pri indoor je vonkajšia predpoveď iba kontext na cestu, pobyt vonku a vrchnú vrstvu, nie teplota či dážď vo vnútri.",\n', "planner environment")
replace_once(path, '    "Ak ponúkneš nákup, assistantText NESMIE obsahovať otázku Áno/Nie ani vetu \'Chceš, aby som...\'. UI zobrazí samostatnú nákupnú otázku až POD kartami outfitu. Nastav iba offerShopping=true a shoppingNeedLabel.",\n', '    "Ak ponúkneš nákup, assistantText NESMIE obsahovať otázku Áno/Nie ani vetu \'Chceš, aby som...\'. UI zobrazí samostatnú nákupnú otázku až POD kartami outfitu. Nastav iba offerShopping=true a shoppingNeedLabel.",\n    "Ak session.context.environment=indoor, vonkajšiu predpoveď formuluj výhradne ako \'Vonku...\' alebo \'Na cestu...\'. Nikdy nepripisuj vonkajšiu teplotu, dážď, vietor či sucho interiéru. Vnútornú teplotu nepoznáme. Klimatizáciu spomeň iba ako možnosť, nie ako istý fakt.",\n', "final indoor prompt")
replace_once(path, '  if (clean(patch.timeWindowKey, 40)) context.timeWindow = {key: clean(patch.timeWindowKey, 40), source: "user"};\n  const terrain = {...(session?.context?.terrain || {surface: null, difficulty: null, condition: null})};\n', '  if (clean(patch.timeWindowKey, 40)) context.timeWindow = {key: clean(patch.timeWindowKey, 40), source: "user"};\n  if (ENVIRONMENTS.includes(patch.environment) && patch.environment !== "unknown") context.environment = patch.environment;\n  const terrain = {...(session?.context?.terrain || {surface: null, difficulty: null, condition: null})};\n', "patch environment materialization")
replace_once(path, 'function planEnvelope(raw, input) {\n  const statePatch = patchFromRaw(raw, input.session);\n', 'function planEnvelope(raw, input) {\n  const statePatch = patchFromRaw(raw, input.session);\n  const requestedScenarioId = clean(raw?.scenarioReferenceId, 140) || null;\n  const knownScenarioIds = new Set((input?.session?.scenarioMemory?.snapshots || []).map((snapshot) => snapshot.id));\n  const requestedMode = SCENARIO_MODES.includes(raw?.scenarioMode) ? raw.scenarioMode : "current";\n  statePatch.scenarioMode = requestedMode === "restore" && !knownScenarioIds.has(requestedScenarioId) ? "current" : requestedMode;\n  statePatch.scenarioReferenceId = statePatch.scenarioMode === "restore" ? requestedScenarioId : null;\n', "plan scenario state patch")
indoor_guard = r'''function guardIndoorWeatherWordingV2(value, environment) {
  const original = clean(value);
  if (environment !== "indoor" || !original) return original;
  const weatherSignal = /(?:°\s*c|\bstupn|\btepl|\bhoruc|\bchlad|\bsuch|\bdazd|\bprsi|\bsneh|\bsnezi|\bvietor|\bfuka|\bburk|\bmrhol)/iu;
  const outsideScope = /\b(vonku|na cestu|cestou|po ceste|pri presune|pred cestou)\b/iu;
  const climate = /\bklimatiz/iu;
  const climatePossibility = /\b(moze|môže|mozno|možno|pripadne|prípadne)\b/iu;
  const sentences = original.match(/[^.!?]+[.!?]?/gu) || [original];
  return sentences.map((rawSentence) => {
    let sentence = rawSentence.trim();
    if (!sentence) return "";
    if (climate.test(sentence)) {
      if (climatePossibility.test(sentence)) return sentence;
      return "Vnútri môže byť kvôli klimatizácii chladnejšie.";
    }
    if (!weatherSignal.test(sentence) || outsideScope.test(sentence)) return sentence;
    sentence = sentence.replace(/^(?:v|vo)\s+[^,.!?]{1,80}?\s+(?=(?:je|bude|budu|má|ma|prší|prsi|sneží|snezi|fúka|fuka)\b)/iu, "");
    sentence = sentence.replace(/^([A-ZÁÄČĎÉÍĹĽŇÓÔŔŠŤÚÝŽ])/, (match) => match.toLocaleLowerCase("sk-SK"));
    return `Vonku ${sentence}`.replace(/\s+/g, " ").trim();
  }).filter(Boolean).join(" ");
}

function finalEnvelope(raw, input) {
'''
replace_once(path, 'function finalEnvelope(raw, input) {\n', indoor_guard, "indoor guard")
replace_once(path, '    assistantText: clean(raw.assistantText) || "Rozumiem.",\n', '    assistantText: guardIndoorWeatherWordingV2(clean(raw.assistantText) || "Rozumiem.", input?.session?.context?.environment),\n', "apply indoor guard")
replace_once(path, '  finalReasoningForInputV2,\n  planEnvelope,\n', '  finalReasoningForInputV2,\n  guardIndoorWeatherWordingV2,\n  planEnvelope,\n', "model guard export")

# Coordinator: apply transitions before planner patch, preserve validation baseline, persist snapshots.
path = "functions/stylist/v2/stylist_turn_coordinator_v2.js"
replace_once(path, 'const {MAX_HISTORY, bounded, clone, validateStylistSessionStateV2} = require("./stylist_session_state_v2");\n', 'const {MAX_HISTORY, bounded, clone, validateStylistSessionStateV2} = require("./stylist_session_state_v2");\nconst {beginNewScenarioV2, restoreScenarioSnapshotV2, upsertScenarioSnapshotV2} = require("./stylist_scenario_memory_v2");\n', "coordinator scenario imports")
replace_once(path, 'function applySafeStatePatch(state, statePatch = {}) {\n  const next = clone(state);\n  const context = statePatch.context || {};\n  for (const key of ["activity", "date", "timeWindow", "terrain", "groundingRequirements"]) {\n', 'function applySafeStatePatch(state, statePatch = {}) {\n  let next = clone(state);\n  if (statePatch.scenarioMode === "restore" && statePatch.scenarioReferenceId) next = restoreScenarioSnapshotV2(next, statePatch.scenarioReferenceId);\n  else if (statePatch.scenarioMode === "new") next = beginNewScenarioV2(next);\n  const context = statePatch.context || {};\n  for (const key of ["activity", "date", "timeWindow", "terrain", "environment", "groundingRequirements"]) {\n', "coordinator apply transition")
replace_once(path, '  next.replay.turns = [...next.replay.turns, {turnId: result.turnId, result: clone(result)}].slice(-MAX_HISTORY);\n  return validateStylistSessionStateV2(next);\n}\n', '  next.replay.turns = [...next.replay.turns, {turnId: result.turnId, result: clone(result)}].slice(-MAX_HISTORY);\n  const withScenarioSnapshot = ["generate_outfit", "edit_outfit"].includes(result.action) ? upsertScenarioSnapshotV2(next, {turnId: result.turnId}) : next;\n  return validateStylistSessionStateV2(withScenarioSnapshot);\n}\n', "coordinator persist snapshot")
replace_once(path, 'function greetingDecision() {\n  return {action: "chat", assistantText: "Ahoj! Ako ti môžem pomôcť s outfitom?", display: {kind: "none", itemIds: []}};\n}\n', 'function greetingDecision() {\n  return {action: "chat", assistantText: "Ahoj! Ako ti môžem pomôcť?", display: {kind: "none", itemIds: []}};\n}\n', "backend neutral greeting")
replace_once(path, '      let workingState = clone(originalState);\n      const observation = request.freshClientObservations.currentLocationObservation;\n', '      let workingState = clone(originalState);\n      let validationPreviousState = clone(originalState);\n      const observation = request.freshClientObservations.currentLocationObservation;\n', "validation baseline init")
replace_once(path, '        workingState = applySafeStatePatch(workingState, planningEnvelope.statePatch);\n        workingState = applyHelpFirstDefaultsV2(workingState);\n\n        if (planningEnvelope.kind === "final") decision = planningEnvelope.result;\n', '        workingState = applySafeStatePatch(workingState, planningEnvelope.statePatch);\n        workingState = applyHelpFirstDefaultsV2(workingState);\n        validationPreviousState = clone(workingState);\n\n        if (planningEnvelope.kind === "final") decision = planningEnvelope.result;\n', "validation baseline after planner")
replace_once(path, '      const validatedResult = validateAuthoritativeTurnV2({rawResult, previousState: originalState, proposedState: workingState,\n', '      const validatedResult = validateAuthoritativeTurnV2({rawResult, previousState: validationPreviousState, proposedState: workingState,\n', "validator restored baseline")
replace_once(path, '  applyHelpFirstDefaultsV2,\n  cleanLocationAnswerFragmentV2,\n', '  applyAcceptedResult,\n  applyHelpFirstDefaultsV2,\n  applySafeStatePatch,\n  cleanLocationAnswerFragmentV2,\n', "coordinator test exports")
replace_once(path, '  disableOptionalWeatherGroundingV2,\n  isFriendlyGreetingV2,\n', '  disableOptionalWeatherGroundingV2,\n  greetingDecision,\n  isFriendlyGreetingV2,\n', "coordinator greeting export")

# Flutter local greeting and quick-reply regression.
replace_once("lib/Services/stylist_simple_agent_service_v1.dart", "        'assistantText': 'Ahoj! Ako ti môžem pomôcť s outfitom?',\n", "        'assistantText': 'Ahoj! Ako ti môžem pomôcť?',\n", "Flutter neutral greeting")
replace_once("test/stylist_simple_agent_fast_path_test.dart", "    const prompt = 'Chceš, aby som ti vybral vhodnejšie turistické topánky?';\n", "    const prompt = 'Chceš, aby som ti pozrel vhodné topánky v obchodoch?';\n", "Flutter shopping prompt")
replace_once("test/stylist_simple_agent_fast_path_test.dart", "    expect(result['displayItemIds'], isEmpty);\n  });\n\n  test('plain and natural friendly greetings use local fast path', () {\n", "    expect(result['displayItemIds'], isEmpty);\n    expect(result['assistantText'], 'Ahoj! Ako ti môžem pomôcť?');\n    expect((result['assistantText'] as String).toLowerCase(), isNot(contains('outfit')));\n  });\n\n  test('plain and natural friendly greetings use local fast path', () {\n", "Flutter greeting exact test")

# Focused regression suite A-N.
test_path = Path("functions/stylist/v2/stylist_dialog_continuity_v2.test.js")
if test_path.exists():
    raise SystemExit("dialog continuity test unexpectedly already exists")
test_path.write_text(r'''"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {clone, createEmptySessionStateV2, MAX_SCENARIO_SNAPSHOTS, validateStylistSessionStateV2} = require("./stylist_session_state_v2");
const {beginNewScenarioV2, hasExplicitScenarioBackreferenceV2, restoreScenarioSnapshotV2, upsertScenarioSnapshotV2} = require("./stylist_scenario_memory_v2");
const {inferMandatoryGroundingV2} = require("./stylist_grounding_policy_v2");
const {finalEnvelope, guardIndoorWeatherWordingV2, planEnvelope, shouldPreloadCurrentOutfitV2} = require("./openai_stylist_model_port_v2");
const {applySafeStatePatch, greetingDecision} = require("./stylist_turn_coordinator_v2");

function outfitState(chatId, activityId, activityLabel, itemId, options = {}) {
  const state = clone(createEmptySessionStateV2(chatId));
  state.context.activity = {id: activityId, label: activityLabel, source: "user"};
  state.context.date = {dateKey: options.dateKey || "2026-09-11", source: "user"};
  state.context.timeWindow = {key: "day", source: "help_first_default"};
  state.context.destination = options.destination || null;
  state.context.eventLocation = options.eventLocation || null;
  state.context.environment = options.environment ?? null;
  state.currentOutfit.itemIds = [itemId];
  state.currentOutfit.selectionReasonsByItemId = {[itemId]: `reason ${itemId}`};
  state.currentOutfit.revision = 1;
  return state;
}
function addScenario(state, activityId, activityLabel, itemId, options = {}, turnId = "turn") {
  let next = beginNewScenarioV2(state);
  next.context.activity = {id: activityId, label: activityLabel, source: "user"};
  next.context.date = {dateKey: options.dateKey || "2026-09-11", source: "user"};
  next.context.timeWindow = {key: "day", source: "help_first_default"};
  next.context.destination = options.destination || null;
  next.context.eventLocation = options.eventLocation || null;
  next.context.environment = options.environment ?? null;
  next.currentOutfit.itemIds = [itemId];
  next.currentOutfit.selectionReasonsByItemId = {[itemId]: `reason ${itemId}`};
  next.currentOutfit.revision += 1;
  return upsertScenarioSnapshotV2(next, {turnId});
}
function plannerRaw(mode, ref) {
  return {kind: "tool_request", action: "none", assistantText: "", clarificationField: null, clarificationQuestion: null,
    scenarioMode: mode, scenarioReferenceId: ref, locationQuery: null, locationTargetField: "none",
    wardrobeScope: "current_outfit_plus_category", wardrobeCategory: "tops", replaceItemIds: ["hike-shirt"], retainItemIds: [],
    allowedSlots: ["top"], allowedCategories: ["tops"], allowRemovalOnly: false,
    patch: {activityId: null, activityLabel: null, dateKey: null, timeWindowKey: null, environment: "unknown",
      terrainSurface: "unknown", terrainDifficulty: "unknown", terrainCondition: "unknown", replaceGroundingRequirements: false,
      weatherRequired: false, weatherLocationField: "none", terrainRequiredFields: []}};
}

test("A hiking/Tatry -> cinema -> back to hiking restores exact snapshot", () => {
  const tatry = {providerId: "place:tatry", label: "Vysoké Tatry"};
  let state = outfitState("a", "hiking", "túra", "hike-shirt", {destination: tatry, environment: "outdoor"});
  state = upsertScenarioSnapshotV2(state, {turnId: "hike"});
  const hikeId = state.scenarioMemory.activeScenarioId;
  state = addScenario(state, "cinema", "kino", "cinema-shirt", {environment: "indoor"}, "cinema");
  const message = "mohol by si mi ukázať outfit na tú túru ale s iným tričkom?";
  assert.equal(hasExplicitScenarioBackreferenceV2({latestUserInput: message, state}), true);
  const policy = inferMandatoryGroundingV2({latestUserInput: message, state});
  assert.equal(policy.scope, "scenario_reference");
  assert.equal(policy.resetContext, false);
  const envelope = planEnvelope(plannerRaw("restore", hikeId), {session: state, request: {latestUserInput: message}});
  const restored = applySafeStatePatch(state, envelope.statePatch);
  assert.equal(restored.context.activity.id, "hiking");
  assert.equal(restored.context.destination.label, "Vysoké Tatry");
  assert.deepEqual(restored.currentOutfit.itemIds, ["hike-shirt"]);
});

for (const fixture of [
  ["B interview -> dinner -> interview", ["job_interview", "pracovný pohovor", "interview-shirt"], ["dinner", "večera", "dinner-shirt"], "vráťme sa k pohovoru"],
  ["C wedding -> work -> wedding", ["wedding", "svadba", "wedding-shirt"], ["work", "práca", "work-shirt"], "ukáž ten svadobný outfit s inou košeľou"],
  ["D concert -> unrelated -> concert", ["concert", "koncert", "concert-shirt"], ["shopping", "nákup", "shopping-shirt"], "vráťme sa späť ku koncertu"],
]) test(fixture[0], () => {
  let state = outfitState("semantic", ...fixture[1]);
  state = upsertScenarioSnapshotV2(state, {turnId: "old"});
  const oldId = state.scenarioMemory.activeScenarioId;
  state = addScenario(state, ...fixture[2], {}, "current");
  assert.equal(hasExplicitScenarioBackreferenceV2({latestUserInput: fixture[3], state}), true);
  const restored = restoreScenarioSnapshotV2(state, oldId);
  assert.equal(restored.context.activity.id, fixture[1][0]);
  assert.deepEqual(restored.currentOutfit.itemIds, [fixture[1][2]]);
});

test("E/F/G indoor forecast wording is scoped outside", () => {
  for (const [text, forbidden] of [["V kine je 31 °C a sucho.", /v kine je 31/iu], ["V reštaurácii prší.", /reštaurácii prší/iu], ["V kancelárii bude 4 °C, zober si bundu.", /kancelárii bude 4/iu]]) {
    const guarded = guardIndoorWeatherWordingV2(text, "indoor");
    assert.match(guarded, /^Vonku /u); assert.doesNotMatch(guarded, forbidden);
  }
  assert.equal(guardIndoorWeatherWordingV2("V kine môže byť kvôli klimatizácii chladnejšie.", "indoor"), "V kine môže byť kvôli klimatizácii chladnejšie.");
  assert.equal(guardIndoorWeatherWordingV2("V kine bude klimatizácia.", "indoor"), "Vnútri môže byť kvôli klimatizácii chladnejšie.");
});

test("H/I shopping CTA describes store search and is separate", () => {
  const state = clone(createEmptySessionStateV2("shop"));
  const raw = {action: "generate_outfit", assistantText: "Tenisky sú kompromis. Chceš, aby som ti vybral vhodnejšie topánky?",
    resultingOutfitItemIds: ["shoe"], selectionReasons: [{itemId: "shoe", reason: "najpraktickejší dostupný pár"}],
    displayKind: "outfit", displayItemIds: ["shoe"], editReplaceItemIds: [], editRetainItemIds: [], editAllowedSlots: [],
    editAllowedCategories: [], editAllowRemovalOnly: false, clarificationField: null, clarificationQuestion: null,
    offerShopping: true, shoppingNeedLabel: "turistické topánky", shoppingNeedCanonicalType: "hiking_shoes",
    shoppingHardConstraints: [], shoppingSoftPreferences: []};
  const envelope = finalEnvelope(raw, {session: state, request: {turnId: "shop-turn"}, toolResults: {}});
  assert.equal(envelope.result.quickReplyPrompt, "Chceš, aby som ti pozrel vhodné topánky v obchodoch?");
  assert.deepEqual(envelope.result.quickReplies.map((reply) => reply.label), ["Áno", "Nie"]);
  assert.doesNotMatch(envelope.result.assistantText, /Chceš, aby som/iu);
});

test("J greeting is neutral", () => {
  assert.equal(greetingDecision().assistantText, "Ahoj! Ako ti môžem pomôcť?");
  assert.doesNotMatch(greetingDecision().assistantText, /outfit/iu);
});

test("L ordinary current edit does not select old scenario", () => {
  let state = outfitState("edit", "work", "práca", "shirt");
  state = upsertScenarioSnapshotV2(state, {turnId: "work"});
  state = addScenario(state, "dinner", "večera", "dinner-shirt", {}, "dinner");
  const message = "daj mi iné tričko";
  assert.equal(hasExplicitScenarioBackreferenceV2({latestUserInput: message, state}), false);
  assert.equal(shouldPreloadCurrentOutfitV2({request: {latestUserInput: message}, session: state}), true);
});

test("M existing session without scenario memory validates", () => {
  const legacy = clone(createEmptySessionStateV2("legacy"));
  delete legacy.scenarioMemory; delete legacy.context.environment;
  const validated = validateStylistSessionStateV2(legacy);
  assert.deepEqual(validated.scenarioMemory, {activeScenarioId: null, snapshots: []});
  assert.equal(validated.context.environment, null);
});

test("N scenario memory is bounded", () => {
  let state = clone(createEmptySessionStateV2("bounded"));
  for (let i = 0; i < MAX_SCENARIO_SNAPSHOTS + 4; i += 1) state = addScenario(state, `activity-${i}`, `activity ${i}`, `item-${i}`, {}, `turn-${i}`);
  assert.equal(state.scenarioMemory.snapshots.length, MAX_SCENARIO_SNAPSHOTS);
});
''', encoding="utf-8")

print("Scoped V2 scenario-memory patch applied.")
