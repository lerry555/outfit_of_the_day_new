"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createOpenAiOneBrainModelPortV2,
  preserveNonMutatingOutfitV2,
} = require("./openai_one_brain_model_port_v2");

const CURRENT_OUTFIT = {
  itemIds: ["jacket_black", "hoodie_blue", "tee_black", "joggers_gray", "sneakers_white"],
  selectionReasonsByItemId: {
    jacket_black: "pôvodná bunda",
    hoodie_blue: "pôvodná mikina",
    tee_black: "pôvodné tričko",
    joggers_gray: "pôvodné nohavice",
    sneakers_white: "pôvodné tenisky",
  },
  compromises: ["pôvodný kompromis"],
  missingWardrobeNeeds: ["pôvodná potreba"],
};

function envelopeFor(action) {
  return {
    kind: "final",
    result: {
      action,
      assistantText: "Máš aj čierne tenisky.",
      resultingOutfit: {
        itemIds: ["sneakers_black"],
        selectionReasonsByItemId: {sneakers_black: "alternatíva"},
        compromises: [],
        missingWardrobeNeeds: [],
      },
      display: {kind: "items", itemIds: ["sneakers_black"]},
    },
    statePatch: {},
  };
}

for (const action of ["chat", "clarify", "show_items", "explain_outfit", "stop"]) {
  test(`non-mutating ${action} preserves authoritative current outfit while keeping display items`, () => {
    const result = preserveNonMutatingOutfitV2(envelopeFor(action), {
      session: {currentOutfit: CURRENT_OUTFIT},
    });

    assert.deepEqual(result.result.resultingOutfit, CURRENT_OUTFIT);
    assert.deepEqual(result.result.display, {kind: "items", itemIds: ["sneakers_black"]});
  });
}

for (const action of ["generate_outfit", "edit_outfit"]) {
  test(`mutating ${action} keeps model-selected resulting outfit`, () => {
    const envelope = envelopeFor(action);
    const result = preserveNonMutatingOutfitV2(envelope, {
      session: {currentOutfit: CURRENT_OUTFIT},
    });

    assert.deepEqual(result.result.resultingOutfit, envelope.result.resultingOutfit);
  });
}

test("One-Brain answer normalization prevents show_items from mutating current outfit", async () => {
  const port = createOpenAiOneBrainModelPortV2({
    executeStructured: async () => ({
      action: "show_items",
      assistantText: "Máš aj čierne tenisky.",
      resultingOutfitItemIds: ["sneakers_black"],
      selectionReasons: [{itemId: "sneakers_black", reason: "alternatíva"}],
      displayKind: "items",
      displayItemIds: ["sneakers_black"],
      editReplaceItemIds: [],
      editRetainItemIds: [],
      editAllowedSlots: [],
      editAllowedCategories: [],
      editAllowRemovalOnly: false,
      clarificationField: null,
      clarificationQuestion: null,
      offerShopping: false,
      shoppingNeedLabel: null,
      shoppingNeedCanonicalType: null,
      shoppingHardConstraints: [],
      shoppingSoftPreferences: [],
    }),
  });

  const envelope = await port.brainTurn({
    stage: "answer",
    request: {turnId: "browse_sneakers", latestUserInput: "aké iné tenisky mám?"},
    session: {
      context: {},
      currentOutfit: CURRENT_OUTFIT,
      conversationMemory: {},
    },
    toolResults: {
      wardrobeItems: [
        {id: "sneakers_white", name: "Biele tenisky", category: "footwear"},
        {id: "sneakers_black", name: "Čierne tenisky", category: "footwear"},
      ],
    },
    runtimeConstraints: {allowClarification: false},
  });

  assert.equal(envelope.result.action, "show_items");
  assert.deepEqual(envelope.result.resultingOutfit, CURRENT_OUTFIT);
  assert.deepEqual(envelope.result.display, {kind: "items", itemIds: ["sneakers_black"]});
});
