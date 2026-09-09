"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createStylistChatV2Handler} = require("./stylist_production_bridge_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");

const NOW = Date.parse("2026-09-09T06:00:00.000Z");

test("first production V2 turn bootstraps persisted selection reasons without fail-closed", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const wardrobeTool = {
    async retrieve(request) {
      const ids = Array.isArray(request?.itemIds) ? request.itemIds : [];
      return ids.map((id) => ({id, category: "tops", bodySlots: ["upper_body"]}));
    },
    async materialize(itemIds, reasonsByItemId) {
      return itemIds.map((id) => ({id, name: id, selectionReason: reasonsByItemId[id] || null}));
    },
  };
  const stylistModel = {
    planningNeedsCurrentOutfit: false,
    async turn() {
      return {
        kind: "final",
        statePatch: {},
        result: {
          action: "chat",
          assistantText: "Outfit nechávam bez zmeny.",
          display: {kind: "none", itemIds: []},
        },
      };
    },
  };
  const warnings = [];
  const handler = createStylistChatV2Handler({
    db: {},
    admin: {},
    logger: {warn(message, data) { warnings.push({message, data}); }},
    resolveOpenAISecret: async () => "unused",
    clock: () => NOW,
    sessionRepository: repository,
    locationResolver: {async resolve() { return null; }},
    weatherTool: {async getForecast() { return null; }},
    modelFactory: () => stylistModel,
    wardrobeToolFactory: () => wardrobeTool,
    shoppingToolFactory: () => ({
      async search() { return {candidateIds: [], appliedHardConstraints: []}; },
    }),
  });

  const response = await handler({
    v2SessionId: "chat_bootstrap",
    turnId: "turn_bootstrap",
    message: "Čo povieš na tento outfit?",
    currentOutfitItemIds: ["shirt", "jeans"],
    currentSelectionReasons: [
      {itemId: "shirt", reason: "sedí k zvyšku"},
      {itemId: "jeans", reason: "vhodný spodný diel"},
    ],
    clientContext: {},
  }, {auth: {uid: "user-a"}});

  assert.equal(response.ok, true);
  assert.equal(response.failClosed, false);
  assert.equal(response.action, "chat");
  assert.deepEqual(response.resultingOutfitItemIds, ["shirt", "jeans"]);
  assert.equal(warnings.length, 0);

  const stored = await repository.get({uid: "user-a", chatId: "chat_bootstrap"});
  assert.deepEqual(stored.state.currentOutfit.selectionReasonsByItemId, {
    shirt: "sedí k zvyšku",
    jeans: "vhodný spodný diel",
  });
});
