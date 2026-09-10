"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {StaleSessionRevisionError} = require("./stylist_preflight_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {createStylistTurnEngineV2} = require("./stylist_turn_engine_v2");
const {
  CallLedgerV2,
  FakeLocationResolverV2,
  FakeShoppingToolV2,
  FakeStylistModelPortV2,
  FakeWardrobeToolV2,
  FakeWeatherToolV2,
} = require("./fake_ports_v2");

const NOW = Date.parse("2026-09-08T18:00:00.000Z");
const wardrobe = [
  {id: "shirt", category: "tops", bodySlots: ["upper_body"]},
  {id: "jeans", category: "bottoms", bodySlots: ["lower_body"]},
  {id: "shoes", category: "footwear", bodySlots: ["feet"]},
];

function request(chatId, turnId, expectedSessionRevision, latestUserInput) {
  return {
    chatId,
    turnId,
    expectedSessionRevision,
    latestUserInput,
    clientCapabilities: {typedQuickReplies: true, explicitDisplay: true},
  };
}

function finalChat(text) {
  return {
    kind: "final",
    result: {
      action: "chat",
      assistantText: text,
      display: {kind: "none", itemIds: []},
    },
  };
}

function harness({repository, modelResults = []} = {}) {
  const ledger = new CallLedgerV2();
  const sessionRepository = repository || createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const ports = {
    sessionRepository,
    wardrobeTool: new FakeWardrobeToolV2(ledger, wardrobe),
    locationResolver: new FakeLocationResolverV2(ledger, {}),
    weatherTool: new FakeWeatherToolV2(ledger, {}),
    shoppingTool: new FakeShoppingToolV2(ledger),
    stylistModel: new FakeStylistModelPortV2(ledger, modelResults),
    clock: () => NOW,
  };
  return {
    ledger,
    sessionRepository,
    engine: createStylistTurnEngineV2(ports),
    freshEngine() {
      return createStylistTurnEngineV2(ports);
    },
  };
}

test("durable engine commits one authoritative result and replays it without another model call", async () => {
  const h = harness({modelResults: [finalChat("Rifle sú na tento plán v poriadku.")]});
  const first = await h.engine.resolveTurn({
    uid: "user-a",
    request: request("chat-a", "turn-1", 0, "A rifle sú v poriadku?"),
  });
  assert.equal(first.assistantText, "Rifle sú na tento plán v poriadku.");
  assert.equal(first.resultingSessionRevision, 1);
  assert.equal(h.ledger.calls("model", "plan").length, 1);

  const replay = await h.freshEngine().resolveTurn({
    uid: "user-a",
    request: request("chat-a", "turn-1", 0, "Tento text sa pri replayi nesmie znovu vyhodnotiť."),
  });
  assert.deepEqual(replay, first);
  assert.equal(h.ledger.calls("model", "plan").length, 1);

  const stored = await h.sessionRepository.get({uid: "user-a", chatId: "chat-a"});
  assert.equal(stored.state.revision, 1);
  assert.deepEqual(stored.state.replay.turns.at(-1).result, first);
});

test("a fresh engine instance continues from canonical durable session state", async () => {
  const h = harness({modelResults: [finalChat("Prvá odpoveď.")]});
  await h.engine.resolveTurn({
    uid: "user-a",
    request: request("chat-persist", "turn-1", 0, "Čo si myslíš o rifliach?"),
  });

  const second = await h.freshEngine().resolveTurn({
    uid: "user-a",
    request: request("chat-persist", "turn-2", 1, "Ahoj"),
  });
  assert.equal(second.action, "chat");
  assert.equal(second.resultingSessionRevision, 2);

  const stored = await h.sessionRepository.get({uid: "user-a", chatId: "chat-persist"});
  assert.equal(stored.state.revision, 2);
  assert.deepEqual(stored.state.replay.turns.map((entry) => entry.turnId), ["turn-1", "turn-2"]);
  assert.equal(h.ledger.calls("model").length, 1);
});

test("two different turns racing from one revision cannot both overwrite canonical state", async () => {
  const h = harness();
  const outcomes = await Promise.allSettled([
    h.engine.resolveTurn({
      uid: "user-a",
      request: request("chat-race", "left", 0, "Ahoj"),
    }),
    h.freshEngine().resolveTurn({
      uid: "user-a",
      request: request("chat-race", "right", 0, "Čau"),
    }),
  ]);

  assert.equal(outcomes.filter((entry) => entry.status === "fulfilled").length, 1);
  const rejected = outcomes.find((entry) => entry.status === "rejected");
  assert.equal(rejected.reason instanceof StaleSessionRevisionError, true);

  const stored = await h.sessionRepository.get({uid: "user-a", chatId: "chat-race"});
  assert.equal(stored.state.revision, 1);
  assert.equal(stored.state.replay.turns.length, 1);
});

test("same-turn race returns the one committed canonical receipt to both callers", async () => {
  const h = harness({modelResults: [finalChat("Prvý návrh."), finalChat("Druhý návrh.")]});
  const duplicated = request("chat-duplicate", "same-turn", 0, "Čo hovoríš na rifle?");
  const [left, right] = await Promise.all([
    h.engine.resolveTurn({uid: "user-a", request: duplicated}),
    h.freshEngine().resolveTurn({uid: "user-a", request: duplicated}),
  ]);

  assert.deepEqual(left, right);
  const stored = await h.sessionRepository.get({uid: "user-a", chatId: "chat-duplicate"});
  assert.equal(stored.state.revision, 1);
  assert.deepEqual(stored.state.replay.turns.at(-1).result, left);
  assert.ok(h.ledger.calls("model", "plan").length >= 1);
  assert.ok(h.ledger.calls("model", "plan").length <= 2);
});

test("legacy bootstrap keeps exact outfit IDs and reasons before the first V2 turn", async () => {
  const h = harness({modelResults: [finalChat("Aktuálny outfit nechávam bez zmeny.")]});
  await h.engine.resolveTurn({
    uid: "user-a",
    request: request("chat-legacy", "turn-1", 0, "Nechaj outfit tak, len mi ho zhodnoť."),
    bootstrapInput: {
      currentOutfitItemIds: ["shirt", "jeans", "shoes"],
      persistedSelectionReasonsByItemId: {
        shirt: "sedí k zvyšku",
        jeans: "vhodný spodný diel",
        shoes: "pohodlné na chôdzu",
      },
    },
  });

  const stored = await h.sessionRepository.get({uid: "user-a", chatId: "chat-legacy"});
  assert.deepEqual(stored.state.currentOutfit.itemIds, ["shirt", "jeans", "shoes"]);
  assert.deepEqual(stored.state.currentOutfit.selectionReasonsByItemId, {
    shirt: "sedí k zvyšku",
    jeans: "vhodný spodný diel",
    shoes: "pohodlné na chôdzu",
  });
});

test("known canonical state removes redundant normal-turn repository reads", async () => {
  const base = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  await base.ensure({uid: "user-a", chatId: "chat-known"});
  const existing = await base.get({uid: "user-a", chatId: "chat-known"});
  const calls = {ensure: 0, ensureFromLegacy: 0, get: 0, commitTurn: 0};
  const repository = {
    async ensure(args) { calls.ensure += 1; return base.ensure(args); },
    async ensureFromLegacy(args) { calls.ensureFromLegacy += 1; return base.ensureFromLegacy(args); },
    async get(args) { calls.get += 1; return base.get(args); },
    async commitTurn(args) { calls.commitTurn += 1; return base.commitTurn(args); },
  };
  const h = harness({repository, modelResults: [finalChat("Rifle sú v poriadku.")]});
  const result = await h.engine.resolveTurn({
    uid: "user-a",
    request: request("chat-known", "known-1", 0, "A rifle sú v poriadku?"),
    knownCanonicalState: existing.state,
  });
  assert.equal(result.action, "chat");
  assert.equal(calls.ensure, 0);
  assert.equal(calls.ensureFromLegacy, 0);
  assert.equal(calls.get, 0);
  assert.equal(calls.commitTurn, 1);
});
