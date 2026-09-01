"use strict";

const CONTRACT_VERSION = "outfit_edit_plan_v1";
const INTENTS = new Set(["none", "create_outfit", "edit_current_outfit"]);
const ACTIONS = new Set(["preserve", "replace", "add", "remove"]);
const SLOTS = [
  "top", "bottom", "shoes", "layers", "outerwear", "full_body", "accessories",
];
const THERMAL = new Set(["warmer", "cooler"]);
const PRESENTATIONS = new Set(["normal", "concise_full", "focused_item"]);
const ADDABLE_SLOTS = new Set(["layers", "outerwear", "accessories"]);

function token(value, maximum = 64) {
  const normalized = String(value || "").trim().toLowerCase();
  if (!normalized || normalized === "none" || normalized.length > maximum) return null;
  for (const character of normalized) {
    const code = character.charCodeAt(0);
    const allowed = (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) || character === "_" || character === "-";
    if (!allowed) return null;
  }
  return normalized;
}

function sanitizeConstraints(raw) {
  if (raw == null) return Object.freeze({});
  if (typeof raw !== "object" || Array.isArray(raw)) return null;
  const allowedKeys = new Set(["family", "type", "color", "excludedColor", "thermal"]);
  if (Object.keys(raw).some((key) => !allowedKeys.has(key))) return null;
  const read = (key) => {
    const value = String(raw[key] || "").trim().toLowerCase();
    if (!value || value === "none") return {valid: true, value: null};
    const normalized = token(value);
    return {valid: normalized != null, value: normalized};
  };
  const family = read("family");
  const type = read("type");
  const color = read("color");
  const excludedColor = read("excludedColor");
  const thermal = read("thermal");
  if (![family, type, color, excludedColor, thermal].every((value) => value.valid) ||
      (thermal.value != null && !THERMAL.has(thermal.value))) {
    return null;
  }
  return Object.freeze({
    ...(family.value ? {family: family.value} : {}),
    ...(type.value ? {type: type.value} : {}),
    ...(color.value ? {color: color.value} : {}),
    ...(excludedColor.value ? {excludedColor: excludedColor.value} : {}),
    ...(thermal.value ? {thermal: thermal.value} : {}),
  });
}

function sanitizeOperation(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const slot = token(raw.slot);
  const action = token(raw.action);
  if (!SLOTS.includes(slot) || !ACTIONS.has(action)) return null;
  const constraints = sanitizeConstraints(raw.constraints);
  if (constraints == null) return null;
  if ((action === "preserve" || action === "remove") &&
      Object.keys(constraints).length > 0) return null;
  return Object.freeze({slot, action, constraints});
}

function sanitizeOutfitEditPlanV1(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  if (String(raw.contractVersion || "").trim() !== CONTRACT_VERSION) return null;
  const intent = token(raw.intent);
  if (!INTENTS.has(intent)) return null;
  const rawOperations = Array.isArray(raw.operations) ? raw.operations : null;
  if (rawOperations == null) return null;
  const presentationRaw = token(raw.presentation);
  const presentation = PRESENTATIONS.has(presentationRaw) ?
    presentationRaw : intent === "edit_current_outfit" ? "concise_full" : "normal";
  if (intent === "none") {
    if (rawOperations.length > 0) return null;
    return Object.freeze({
      contractVersion: CONTRACT_VERSION,
      intent,
      operations: Object.freeze([]),
      presentation: "normal",
    });
  }
  const operations = [];
  const bySlot = new Map();
  for (const rawOperation of rawOperations) {
    const operation = sanitizeOperation(rawOperation);
    if (!operation) return null;
    if (intent === "create_outfit" && operation.action !== "add") return null;
    if (intent === "edit_current_outfit" &&
        operation.action === "add" && !ADDABLE_SLOTS.has(operation.slot)) return null;
    const existing = bySlot.get(operation.slot) || [];
    if (existing.length > 0 &&
        (!ADDABLE_SLOTS.has(operation.slot) ||
         operation.action !== "add" ||
         existing.some((value) => value.action !== "add"))) {
      return null;
    }
    existing.push(operation);
    bySlot.set(operation.slot, existing);
    operations.push(operation);
  }
  if (intent === "create_outfit") {
    return Object.freeze({
      contractVersion: CONTRACT_VERSION,
      intent,
      operations: Object.freeze(operations),
      presentation: "normal",
    });
  }
  if (!operations.some((operation) => operation.action !== "preserve")) return null;
  for (const slot of SLOTS) {
    if (bySlot.has(slot)) continue;
    operations.push(Object.freeze({
      slot,
      action: "preserve",
      constraints: Object.freeze({}),
    }));
  }
  return Object.freeze({
    contractVersion: CONTRACT_VERSION,
    intent,
    operations: Object.freeze(operations),
    presentation,
  });
}

module.exports = {
  CONTRACT_VERSION,
  sanitizeOutfitEditPlanV1,
};
