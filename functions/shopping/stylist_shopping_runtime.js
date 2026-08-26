"use strict";

const crypto = require("crypto");
const {
  ACTIONS,
  buildQueryPatch,
  buildShoppingNeeds,
  canonicalTypeFromText,
  classifyShoppingUtterance,
  resolveReference,
  validateAiShoppingAction,
  wishlistOffer,
} = require("./stylist_shopping_contract");

const ATTACHMENT_KINDS = Object.freeze({
  candidate: "shopping_candidate",
  resultGroup: "shopping_result_group",
  clarification: "shopping_clarification",
  wishlistOffer: "wishlist_offer",
  wishlistEditor: "wishlist_editor",
  diagnostics: "shopping_relaxations",
});

async function handleStylistShoppingTurn({
  auth,
  message,
  shoppingContext = {},
  orchestrator,
  wardrobeSignal = null,
}) {
  if (!auth?.uid || !orchestrator) return {handled: false};
  const text = String(message || "").trim();
  const lower = text.toLowerCase();

  if (isNormalOutfitTopic(lower) && shoppingContext.sessionId) {
    return {handled: false, clearShoppingContext: true};
  }

  if (wardrobeSignal?.gapDetected === true &&
      wardrobeSignal?.suitableOwnedItemExists !== true &&
      wardrobeSignal?.shoppingApproved !== true) {
    const compromiseLead = wardrobeSignal?.bestOwnedCompromiseExists === true ?
      "Z tvojho šatníka som vybral najbližšiu možnosť, ale ideálny kúsok na túto situáciu" :
      "Na túto situáciu ti v šatníku";
    return shoppingResult({
      action: ACTIONS.ASK_PERMISSION,
      reply: `${compromiseLead} chýba${wardrobeSignal.needLabel ?
        ` (${wardrobeSignal.needLabel})` : ""}. Chceš, aby som pozrel možnosti v obchodoch?`,
      attachments: [clarificationAttachment("SHOPPING_PERMISSION", ["SHOPPING", "NO_THANKS"])],
      contextPatch: {
        activeClarification: "SHOPPING_PERMISSION",
        pendingNeedText: wardrobeSignal.canonicalType ?
          `Chcem si kúpiť ${wardrobeSignal.canonicalType}` :
          String(wardrobeSignal.needLabel || ""),
      },
    });
  }
  if (wardrobeSignal?.suitableOwnedItemExists === true &&
      !isCompletelyNew(lower)) {
    return {handled: false};
  }

  const clarification = String(shoppingContext.activeClarification || "");
  if (shoppingContext.pendingWishlistOfferVariantId) {
    if (/(wishlist|ulož|uloz)/.test(lower) && isAffirmativePrefix(lower)) {
      return shoppingResult({
        action: ACTIONS.WISHLIST_EDITOR,
        reply: "Nastav cieľovú cenu a veľkosť. Uložím ich až po tvojom potvrdení.",
        attachments: [{
          kind: ATTACHMENT_KINDS.wishlistEditor,
          variantId: shoppingContext.pendingWishlistOfferVariantId,
          selectedSizeKeys: shoppingContext.selectedSizeKeys || [],
          targetPrice: null,
          candidate: (shoppingContext.presentedCandidates || []).find((item) =>
            item.variantId === shoppingContext.pendingWishlistOfferVariantId) || null,
          persistenceContract: "WISHLIST_V2",
        }],
        contextPatch: {activeClarification: null},
      });
    }
    if (/(nie|nechcem|no thanks)/.test(lower)) {
      return shoppingResult({
        action: ACTIONS.FOCUS,
        reply: "Dobre, Wishlist už nebudem ponúkať pri tejto možnosti.",
        contextPatch: {
          activeClarification: null,
          pendingWishlistOfferVariantId: null,
        },
      });
    }
  }
  if (clarification === "SHOPPING_SOURCE") {
    if (isWardrobeChoice(lower)) {
      return {
        handled: false,
        clearShoppingContext: true,
        passThroughMessage: String(shoppingContext.pendingSourceText || text),
      };
    }
    if (isShoppingChoice(lower)) {
      const sourceText = String(shoppingContext.pendingSourceText || text);
      return startSearch({auth, text: `${sourceText} nové z obchodov`,
        orchestrator, shoppingContext});
    }
  }
  if (clarification === "SHOPPING_PERMISSION") {
    if (isShoppingChoice(lower) || isAffirmative(lower)) {
      return startSearch({auth, text: String(shoppingContext.pendingNeedText || text),
        orchestrator, shoppingContext});
    }
    return shoppingResult({
      action: ACTIONS.RETURN_WARDROBE,
      reply: "Dobre, zostaneme pri tvojom šatníku.",
      clearShoppingContext: true,
    });
  }
  if (clarification === "SHOPPING_MAX_PRICE") {
    const patch = buildQueryPatch(text);
    if (!patch.constraints.some((item) => item.field === "maxPrice")) {
      return oneQuestion(ACTIONS.ASK_PRICE, "Do akej ceny sa chceš zmestiť?",
        "SHOPPING_MAX_PRICE");
    }
    return refineSearch({auth, patch, orchestrator, shoppingContext});
  }

  const classified = classifyShoppingUtterance(text, shoppingContext);
  if (classified?.action === ACTIONS.CLARIFY_SOURCE) {
    return shoppingResult({
      action: ACTIONS.CLARIFY_SOURCE,
      reply: "Chceš niečo z tvojho šatníka, alebo mám pozrieť niečo nové v obchodoch?",
      attachments: [clarificationAttachment("SHOPPING_SOURCE", ["WARDROBE", "SHOPPING"])],
      contextPatch: {activeClarification: "SHOPPING_SOURCE", pendingSourceText: text},
    });
  }
  if (classified?.action === ACTIONS.START) {
    return startSearch({auth, text, orchestrator, shoppingContext});
  }
  if (shoppingContext.sessionId) {
    if (classified?.rejectPresented) {
      for (const variantId of shoppingContext.presentedVariantIds || []) {
        await orchestrator.dispatch(auth, {
          operation: "REJECT_CANDIDATE",
          sessionId: shoppingContext.sessionId,
          variantId,
        });
      }
      // Rejections mutate the version one-by-one. Page afterward without the
      // caller's pre-rejection version; it still executes atomically.
      return showMore({auth, orchestrator, shoppingContext: {
        ...shoppingContext, sessionVersion: null, operationId: null,
      }});
    }
    if (classified?.action === ACTIONS.SHOW_MORE) {
      return showMore({auth, orchestrator, shoppingContext});
    }
    if (classified?.action === ACTIONS.SHOW_ALL) {
      const result = await orchestrator.dispatch(auth, {
        operation: "SHOW_ALL", sessionId: shoppingContext.sessionId,
        ...mutationRequest(shoppingContext, "show_all"),
      });
      return fromOrchestration(ACTIONS.SHOW_ALL, result, {
        reply: "Pripravil som všetky zostávajúce možnosti na prehľad.",
        groupOnly: true,
      });
    }
    if (classified?.action === ACTIONS.ASK_PRICE) {
      return oneQuestion(ACTIONS.ASK_PRICE, "Do akej ceny sa chceš zmestiť?",
        "SHOPPING_MAX_PRICE", {focusedVariantId: shoppingContext.focusedVariantId});
    }
    if (classified?.action === ACTIONS.CLARIFY_STYLE) {
      return oneQuestion(ACTIONS.CLARIFY_STYLE,
        "Čo ti nesedí najviac — strih, farba, vzor alebo logo?",
        "SHOPPING_STYLE");
    }
    if (/(veľk\S*\s+log[ao]|velk\S*\s+log[ao]|big logo)/.test(lower)) {
      return oneQuestion(ACTIONS.UNSUPPORTED_CONSTRAINT,
        "Logo zatiaľ neviem overiť ako spoľahlivý katalógový údaj. Chceš spresniť farbu, strih alebo vzor?",
        "SHOPPING_STYLE");
    }
    if (/(tmavš|tmavs|darker)/.test(lower)) {
      return oneQuestion(ACTIONS.UNSUPPORTED_CONSTRAINT,
        "Ktorú presnú tmavšiu farbu chceš — napríklad tmavomodrú alebo čiernu?",
        "SHOPPING_COLOR");
    }

    const candidates = Array.isArray(shoppingContext.presentedCandidates) ?
      shoppingContext.presentedCandidates : [];
    const reference = resolveReference(text, candidates);
    if (reference) {
      const focused = await orchestrator.dispatch(auth, {
        operation: "FOCUS_CANDIDATE",
        sessionId: shoppingContext.sessionId,
        variantId: reference,
        ...mutationRequest(shoppingContext, "focus"),
      });
      if (/(páči|paci|like)/.test(lower) && /(drah|expensive)/.test(lower)) {
        const offer = wishlistOffer(reference,
          Array.isArray(shoppingContext.selectedSizeKeys) ?
            shoppingContext.selectedSizeKeys : []);
        return shoppingResult({
          action: ACTIONS.ASK_PRICE,
          reply: "Rozumiem. Do akej ceny sa chceš zmestiť?",
          attachments: [{
            kind: ATTACHMENT_KINDS.wishlistOffer,
            ...offer,
            candidate: candidates.find((item) => item.variantId === reference) || null,
          }],
          contextPatch: {
            focusedVariantId: reference,
            sessionVersion: focused.version,
            activeClarification: "SHOPPING_MAX_PRICE",
            pendingWishlistOfferVariantId: reference,
          },
        });
      }
      return shoppingResult({
        action: ACTIONS.FOCUS,
        reply: "Jasné, túto možnosť držím ako aktuálnu.",
        contextPatch: {focusedVariantId: reference, sessionVersion: focused.version},
      });
    }
    if (looksLikeProductReference(lower, candidates)) {
      return oneQuestion(ACTIONS.FOCUS,
        "Ktorú zobrazenú možnosť myslíš? Môžeš povedať prvú, druhú alebo značku.",
        "SHOPPING_PRODUCT_REFERENCE");
    }

    const patch = buildQueryPatch(text);
    if (patch.constraints.length || patch.availableNow) {
      const previousType = shoppingContext.query?.constraints?.find((item) =>
        item.field === "canonicalType")?.value;
      const nextType = canonicalTypeFromText(text);
      if (nextType && previousType && nextType !== previousType &&
          /(teraz mi nájdi|teraz mi najdi|now find)/.test(lower)) {
        patch.resetIndependentNeed = true;
      }
      return refineSearch({auth, patch, orchestrator, shoppingContext});
    }
  }
  return {handled: false};
}

async function startSearch({auth, text, orchestrator, shoppingContext = {}}) {
  const patch = buildQueryPatch(text);
  const needs = buildShoppingNeeds(text);
  const query = {
    queryId: opaqueId("query"),
    sessionId: opaqueId("intent"),
    revision: 1,
    intent: needs.mode === "COMPLETELY_NEW_OUTFIT" ?
      "completelyNewOutfit" : "browseNew",
    constraints: patch.constraints,
    availableNow: patch.availableNow,
    selectedSizeKeys: extractSizes(text),
    preferredSizeKey: extractSizes(text)[0] || null,
  };
  const result = await orchestrator.dispatch(auth, {
    operation: "START_SEARCH",
    query,
    pageSize: 3,
    idempotencyKey: shoppingContext.operationId || opaqueId("turn"),
  });
  return fromOrchestration(ACTIONS.START, result, {
    reply: result.status === "NO_RESULTS" ?
      zeroResultCopy(result.diagnostics) :
      "Našiel som tieto overené možnosti.",
    extraContext: {shoppingNeeds: needs, query},
  });
}

async function refineSearch({auth, patch, orchestrator, shoppingContext}) {
  const current = shoppingContext.query;
  if (!current || !shoppingContext.sessionId) return {handled: false};
  const next = {
    ...current,
    revision: Number(current.revision || 1) + 1,
    constraints: patch.resetIndependentNeed ?
      patch.constraints :
      mergeConstraints(current.constraints || [], patch.constraints),
    availableNow: patch.resetIndependentNeed ?
      patch.availableNow :
      patch.availableNow || current.availableNow === true,
  };
  const result = await orchestrator.dispatch(auth, {
    operation: "REFINE_QUERY",
    sessionId: shoppingContext.sessionId,
    query: next,
    pageSize: 3,
    expectedQueryRevision: Number(current.revision || 1),
    ...mutationRequest(shoppingContext, "refine"),
  });
  return fromOrchestration(ACTIONS.REFINE, result, {
    reply: result.status === "NO_RESULTS" ?
      zeroResultCopy(result.diagnostics) :
      "Upravil som výber podľa tvojej požiadavky.",
    extraContext: {
      query: next,
      ...(patch.resetIndependentNeed ? {focusedVariantId: null} : {}),
    },
  });
}

async function showMore({auth, orchestrator, shoppingContext}) {
  const result = await orchestrator.dispatch(auth, {
    operation: "SHOW_MORE", sessionId: shoppingContext.sessionId, pageSize: 3,
    ...mutationRequest(shoppingContext, "show_more"),
  });
  return fromOrchestration(ACTIONS.SHOW_MORE, result, {
    reply: result.candidates.length ?
      "Tu sú ďalšie možnosti." : "Ďalšie overené možnosti už nemám.",
  });
}

function fromOrchestration(action, result, {
  reply,
  groupOnly = false,
  extraContext = {},
} = {}) {
  const candidates = Array.isArray(result.candidates) ? result.candidates : [];
  const attachments = groupOnly ? [{
    kind: ATTACHMENT_KINDS.resultGroup,
    sessionId: result.sessionId,
    candidateIds: candidates.map((item) => item.variantId),
    exactResultCount: result.exactResultCount,
    isComplete: result.isComplete,
  }] : candidates.map((candidate) => ({
    kind: ATTACHMENT_KINDS.candidate,
    candidate,
  }));
  if (candidates.length === 0) {
    const relaxations = (result.diagnostics?.blockingConstraints || [])
      .filter((item) => item.maySuggestRelaxation === true)
      .map((item) => {
        const field = item.constraint?.field;
        if (field === "maxPrice") {
          return {constraintField: field, label: "Zvýšiť rozpočet", message: "zvýšiť rozpočet"};
        }
        if (field === "brand") {
          return {constraintField: field, label: "Skúsiť inú značku", message: "skúsiť inú značku"};
        }
        return null;
      })
      .filter(Boolean);
    if (relaxations.length) {
      attachments.push({kind: ATTACHMENT_KINDS.diagnostics, relaxations});
    }
  }
  return shoppingResult({
    action,
    reply,
    attachments,
    diagnostics: result.diagnostics || null,
    contextPatch: {
      sessionId: result.sessionId,
      queryRevision: result.queryRevision,
      catalogRevision: result.catalogRevision,
      sessionVersion: result.sessionVersion,
      presentedVariantIds: candidates.map((item) => item.variantId),
      presentedCandidates: candidates,
      activeClarification: null,
      ...extraContext,
    },
  });
}

function validateShoppingAiActionInRuntime(action, shoppingContext) {
  return validateAiShoppingAction(
    action,
    (shoppingContext?.presentedVariantIds || []).map(String),
  );
}

function shoppingResult({
  action,
  reply,
  attachments = [],
  diagnostics = null,
  contextPatch = {},
  clearShoppingContext = false,
}) {
  return {
    handled: true,
    response: {
      reply,
      action,
      suggestedItems: [],
      messageAttachments: attachments,
      shoppingContextPatch: contextPatch,
      clearShoppingContext,
      zeroResultDiagnostics: diagnostics,
    },
  };
}

function oneQuestion(action, reply, clarification, contextPatch = {}) {
  return shoppingResult({
    action,
    reply,
    attachments: [clarificationAttachment(clarification, [])],
    contextPatch: {activeClarification: clarification, ...contextPatch},
  });
}

function clarificationAttachment(type, options) {
  return {kind: ATTACHMENT_KINDS.clarification, clarificationType: type, options};
}

function mergeConstraints(existing, additions) {
  const replaced = new Set(additions.map((item) => item.field));
  return [
    ...existing.filter((item) => !replaced.has(item.field)),
    ...additions,
  ];
}

function zeroResultCopy(diagnostics) {
  const blockers = diagnostics?.blockingConstraints || [];
  const fields = blockers
    .filter((item) => item.blocksExactResults)
    .map((item) => item.constraint?.field)
    .filter(Boolean);
  return fields.length ?
    `Presnú zhodu som nenašiel. Blokujúce podmienky: ${fields.join(", ")}.` :
    "Presnú zhodu som nenašiel. Podmienky som automaticky neuvoľnil.";
}

function extractSizes(text) {
  const match = String(text || "").toUpperCase().match(/\b(XXS|XS|S|M|L|XL|XXL)\b/g);
  return [...new Set(match || [])];
}
function isNormalOutfitTopic(value) {
  return /(čo si mám|co si mam).*(obliecť|obliect)|outfit.*(prác|prac|pohreb|hory|turistik)/.test(value);
}
function isWardrobeChoice(value) {
  return /(šatník|satnik|wardrobe|z mojich)/.test(value);
}
function isShoppingChoice(value) {
  return /(shopping|obchod|nové|nove)/.test(value);
}
function isAffirmative(value) {
  return /^(áno|ano|hej|jasné|jasne|no)$/i.test(value.trim());
}
function isAffirmativePrefix(value) {
  return /^(áno|ano|hej|jasné|jasne|no)\b/i.test(value.trim());
}
function isCompletelyNew(value) {
  return /(úplne nový|uplne novy|completely new|všetko nové|vsetko nove)/.test(value);
}
function looksLikeProductReference(value, candidates) {
  if (/(táto|tato|tamtá|tamta|produkt|mikina za|za \d+\s*(?:€|eur))/.test(value)) {
    return true;
  }
  return candidates.some((candidate) => {
    const brand = String(candidate.brand || "").toLowerCase();
    return brand && value.includes(brand);
  });
}
function mutationRequest(context, suffix) {
  const rawOperationId = String(context?.operationId || "").trim();
  const sessionVersion = context?.sessionVersion;
  return {
    ...(rawOperationId ? {operationId: `${rawOperationId}-${suffix}`} : {}),
    ...(Number.isSafeInteger(sessionVersion) ? {expectedVersion: sessionVersion} : {}),
  };
}
function opaqueId(prefix) {
  return `${prefix}_${crypto.randomBytes(8).toString("hex")}`;
}

module.exports = {
  ATTACHMENT_KINDS,
  handleStylistShoppingTurn,
  validateShoppingAiActionInRuntime,
};
