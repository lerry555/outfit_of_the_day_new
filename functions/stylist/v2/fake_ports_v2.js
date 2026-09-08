"use strict";

const {clone, createEmptySessionStateV2, validateStylistSessionStateV2} = require("./stylist_session_state_v2");

class CallLedgerV2 {
  constructor() {
    this.entries = [];
  }

  record(port, method, args = {}) {
    this.entries.push({port, method, args: clone(args)});
  }

  calls(port, method) {
    return this.entries.filter((entry) => entry.port === port && (!method || entry.method === method));
  }
}

class InMemorySessionRepositoryV2 {
  constructor(ledger, initialStates = []) {
    this.ledger = ledger;
    this.states = new Map(initialStates.map((state) => [state.chatId, clone(state)]));
  }

  async read(chatId) {
    this.ledger.record("session", "read", {chatId});
    return clone(this.states.get(chatId) || createEmptySessionStateV2(chatId));
  }

  async write(state) {
    const validated = validateStylistSessionStateV2(state);
    this.ledger.record("session", "write", {chatId: state.chatId, revision: state.revision});
    this.states.set(state.chatId, clone(validated));
    return clone(validated);
  }
}

class FakeWardrobeToolV2 {
  constructor(ledger, items = []) {
    this.ledger = ledger;
    this.items = clone(items);
  }

  async retrieve({scope, itemIds = [], category = null}) {
    this.ledger.record("wardrobe", "retrieve", {scope, itemIds, category});
    if (scope === "current_outfit") return clone(this.items.filter((item) => itemIds.includes(item.id)));
    if (scope === "category") return clone(this.items.filter((item) => item.category === category));
    if (scope === "none") return [];
    return clone(this.items);
  }
}

class FakeLocationResolverV2 {
  constructor(ledger, resolutions = {}) {
    this.ledger = ledger;
    this.resolutions = clone(resolutions);
  }

  async resolve(query) {
    this.ledger.record("location", "resolve", {query});
    return clone(this.resolutions[query] || null);
  }
}

class FakeWeatherToolV2 {
  constructor(ledger, snapshots = {}) {
    this.ledger = ledger;
    this.snapshots = clone(snapshots);
  }

  async getForecast(target) {
    this.ledger.record("weather", "getForecast", target);
    const key = `${target.location.providerId}|${target.date.dateKey}|${target.timeWindow.key}`;
    const snapshot = this.snapshots[key] || {summary: "unknown"};
    return {
      locationProviderId: target.location.providerId,
      dateKey: target.date.dateKey,
      timeWindowKey: target.timeWindow.key,
      fetchedAt: "2026-09-08T08:00:00.000Z",
      source: "fake-weather-v2",
      snapshot: clone(snapshot),
    };
  }
}

class FakeShoppingToolV2 {
  constructor(ledger, result = {candidateIds: []}) {
    this.ledger = ledger;
    this.result = clone(result);
  }

  async search(context) {
    this.ledger.record("shopping", "search", context);
    return {...clone(this.result), appliedHardConstraints: clone(context.hardConstraints)};
  }
}

class FakeStylistModelPortV2 {
  constructor(ledger, scriptedResults = []) {
    this.ledger = ledger;
    this.scriptedResults = clone(scriptedResults);
  }

  async turn(input) {
    this.ledger.record("model", "turn", input);
    if (!this.scriptedResults.length) throw new Error("no fake stylist result scripted");
    return clone(this.scriptedResults.shift());
  }
}

module.exports = {
  CallLedgerV2,
  FakeLocationResolverV2,
  FakeShoppingToolV2,
  FakeStylistModelPortV2,
  FakeWardrobeToolV2,
  FakeWeatherToolV2,
  InMemorySessionRepositoryV2,
};
