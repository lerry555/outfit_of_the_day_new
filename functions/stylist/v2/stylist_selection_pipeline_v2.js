"use strict";

const {buildSelectionContextV2, itemMatchesEditScopeV2} = require("./stylist_selection_context_v2");

function clean(value, max = 300) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function list(value, max = 20) {
  return [...new Set((Array.isArray(value) ? value : [])
    .map((entry) => clean(String(entry), 180)).filter(Boolean))].slice(0, max);
}

function normalizeSelectionV2(raw, selectionContext) {
  const ids = list(raw?.selectedItemIds, 12);
  const reasons = new Map();
  for (const entry of Array.isArray(raw?.selectionReasons) ? raw.selectionReasons : []) {
    const itemId = clean(entry?.itemId, 180);
    const reason = clean(entry?.reason, 300);
    if (itemId && reason && ids.includes(itemId) && !reasons.has(itemId)) reasons.set(itemId, reason);
  }
  const previousReasons = selectionContext.selection?.currentOutfit?.selectionReasonsByItemId || {};
  for (const id of ids) {
    if (Object.hasOwn(previousReasons, id) && previousReasons[id] != null) {
      reasons.set(id, clean(previousReasons[id], 300));
    }
  }
  return {
    selectedItemIds: ids,
    selectionReasons: ids.filter((id) => reasons.has(id))
      .map((itemId) => ({itemId, reason: reasons.get(itemId)})),
    compromises: list(raw?.compromises, 8),
    missingWardrobeNeeds: list(raw?.missingWardrobeNeeds, 8),
  };
}

function validateSelectionV2(selection, selectionContext) {
  const errors = [];
  const ids = selection.selectedItemIds;
  const candidateById = new Map((selectionContext.candidateItems || []).map((item) => [item.id, item]));
  if (!ids.length) errors.push("selection_empty");
  for (const id of ids) if (!candidateById.has(id)) errors.push(`selection_unknown_item:${id}`);
  const reasonIds = selection.selectionReasons.map((entry) => entry.itemId);
  for (const id of ids) if (!reasonIds.includes(id)) errors.push(`selection_reason_missing:${id}`);
  for (const id of reasonIds) if (!ids.includes(id)) errors.push(`selection_reason_detached:${id}`);

  if (selectionContext.selection?.action === "generate_outfit") {
    const candidates = [...candidateById.values()];
    const selectedItems = ids.map((id) => candidateById.get(id)).filter(Boolean);
    const slots = (item) => new Set(Array.isArray(item?.bodySlots) ? item.bodySlots : []);
    const candidateCanCover = (slot) => candidates.some((item) => {
      const itemSlots = slots(item);
      return itemSlots.has(slot) ||
        (["upper_body", "lower_body"].includes(slot) && itemSlots.has("full_body"));
    });
    const selectionCovers = (slot) => selectedItems.some((item) => {
      const itemSlots = slots(item);
      return itemSlots.has(slot) ||
        (["upper_body", "lower_body"].includes(slot) && itemSlots.has("full_body"));
    });
    for (const slot of ["upper_body", "lower_body", "feet"]) {
      if (candidateCanCover(slot) && !selectionCovers(slot)) {
        errors.push(`selection_core_coverage_missing:${slot}`);
      }
    }
  }

  if (selectionContext.selection?.action === "edit_outfit") {
    const scope = selectionContext.selection.authorizedEditScope;
    const currentIds = list(selectionContext.selection.currentOutfit?.itemIds, 12);
    if (!scope) errors.push("edit_scope_missing");
    const replaceIds = list(scope?.replaceItemIds, 12);
    const retainIds = list(scope?.retainItemIds, 12);
    const protectedIds = [...new Set([...retainIds, ...currentIds.filter((id) => !replaceIds.includes(id))])];
    for (const id of protectedIds) if (!ids.includes(id)) errors.push(`edit_retained_item_missing:${id}`);
    const addedIds = ids.filter((id) => !currentIds.includes(id));
    if (scope?.allowRemovalOnly && addedIds.length) errors.push("edit_removal_only_added_item");
    for (const id of addedIds) {
      if (!itemMatchesEditScopeV2(candidateById.get(id), scope, currentIds)) {
        errors.push(`edit_added_item_outside_scope:${id}`);
      }
    }
  }
  return {valid: errors.length === 0, errors: [...new Set(errors)]};
}

function deepFreeze(value) {
  if (!value || typeof value !== "object" || Object.isFrozen(value)) return value;
  Object.freeze(value);
  for (const child of Object.values(value)) deepFreeze(child);
  return value;
}

function createStylistSelectionPipelineV2({selector, judge, logger = console,
  visualEvidenceLimit} = {}) {
  if (!selector || typeof selector.select !== "function") throw new TypeError("selector_required");
  if (!judge || typeof judge.judge !== "function") throw new TypeError("quality_judge_required");
  return Object.freeze({
    async resolve(input) {
      const context = buildSelectionContextV2({...input, logger, visualEvidenceLimit});
      let retryUsed = false;
      let selection = normalizeSelectionV2(await selector.select(context, {attempt: 1}), context);
      let validation = validateSelectionV2(selection, context);
      if (!validation.valid) {
        retryUsed = true;
        selection = normalizeSelectionV2(await selector.select(context, {
          attempt: 2,
          feedback: {source: "deterministic_contract", problems: validation.errors},
        }), context);
        validation = validateSelectionV2(selection, context);
        if (!validation.valid) {
          const error = new Error("selector_validation_failed");
          error.code = "selector_validation_failed";
          error.validationErrors = validation.errors;
          throw error;
        }
      }

      let judgment = {verdict: "pass", problems: [], retryGuidance: null};
      try {
        judgment = await judge.judge(context, selection);
      } catch (error) {
        // A structurally valid selector result is the safe fallback if the
        // independent quality service is unavailable.
        logger?.warn?.("STYLIST_V2_JUDGE_FALLBACK", {code: clean(error?.code || error?.message, 120)});
      }
      if (judgment?.verdict === "retry" && !retryUsed) {
        retryUsed = true;
        try {
          const retried = normalizeSelectionV2(await selector.select(context, {
            attempt: 2,
            feedback: {
              source: "quality_judge",
              problems: list(judgment.problems, 10),
              guidance: clean(judgment.retryGuidance, 600) || null,
            },
          }), context);
          const retriedValidation = validateSelectionV2(retried, context);
          if (retriedValidation.valid) selection = retried;
        } catch (error) {
          logger?.warn?.("STYLIST_V2_SELECTOR_RETRY_FALLBACK", {
            code: clean(error?.code || error?.message, 120),
          });
        }
      }
      logger?.info?.("STYLIST_V2_SELECTION_FROZEN", {
        action: context.selection.action,
        selectedItemIds: selection.selectedItemIds,
        selectorCalls: retryUsed ? 2 : 1,
        retryUsed,
        judgeVerdict: judgment?.verdict === "retry" ? "retry" : "pass",
        integrityDiagnosticCount: context.diagnostics.length,
      });
      return {selection: deepFreeze(selection), context};
    },
  });
}

module.exports = {
  createStylistSelectionPipelineV2,
  normalizeSelectionV2,
  validateSelectionV2,
};
