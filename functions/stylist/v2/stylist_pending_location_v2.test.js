"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {clone, createEmptySessionStateV2, validateStylistSessionStateV2} = require("./stylist_session_state_v2");
const {
  cleanLocationAnswerFragmentV2,
  createStylistTurnCoordinatorV2,
  pendingLocationResolutionQueriesV2,
} = require("./stylist_turn_coordinator_v2");
const {
  createOpenMeteoLocationResolverV2,
  locationQueryCandidatesV2,
} = require("./open_meteo_ports_v2");
const {
  CallLedgerV2,
  FakeLocationResolverV2,
  FakeShoppingToolV2,
  FakeStylistModelPortV2,
  FakeWardrobeToolV2,
  FakeWeatherToolV2,
  InMemorySessionRepositoryV2,
} = require("./fake_ports_v2");

const NOW = Date.parse("2026-09-09T07:30:00.000Z");
const martinGps = {
  providerId: "gps:49.06360,18.92170",
  label: "Martin",
  lat: 49.0636,
  lng: 18.9217,
  observedAt: "2026-09-09T07:25:00.000Z",
  source: "device_gps",
};

function place(providerId, label, lat, lng, granularity = "locality") {
  return {providerId, label, lat, lng, source: "fake-location", granularity};
}

function pendingLocationState({chatId, field = "destination", activityId = "hiking", attempts = [], currentLocation = null}) {
  const state = clone(createEmptySessionStateV2(chatId));
  state.context.activity = {id: activityId, label: activityId, source: "user"};
  state.context.date = {dateKey: "2026-09-10", source: "user"};
  state.context.timeWindow = null;
  state.context.groundingRequirements = {
    weatherRequired: true,
    weatherLocationField: field,
    terrainRequiredFields: [],
  };
  if (currentLocation) state.context.currentLocationObservation = clone(currentLocation);
  state.conversationMemory.pendingQuestion = {
    type: "question",
    actionId: field === "eventLocation" ? "clarify_event_location" : "clarify_destination",
    field,
    question: field === "eventLocation" ? "Kde približne sa podujatie koná?" : "Kam približne ideš?",
    acceptsYesNo: false,
  };
  if (attempts.length) state.conversationMemory.pendingQuestion.attemptedAnswers = [...attempts];
  return validateStylistSessionStateV2(state);
}

function request(chatId, turnId, expectedSessionRevision, latestUserInput) {
  return {
    chatId,
    turnId,
    expectedSessionRevision,
    latestUserInput,
    explicitUiActionId: null,
    freshClientObservations: {},
    clientCapabilities: {},
  };
}

function continueChatEnvelope() {
  return {kind: "final", result: {action: "chat", assistantText: "Rozumiem, pokračujem s týmto miestom.", display: {kind: "none", itemIds: []}}, statePatch: {}};
}

function harness(initialState, resolutions = {}, modelResults = [continueChatEnvelope()]) {
  const ledger = new CallLedgerV2();
  const sessionRepository = new InMemorySessionRepositoryV2(ledger, [initialState]);
  const coordinator = createStylistTurnCoordinatorV2({
    sessionRepository,
    wardrobeTool: new FakeWardrobeToolV2(ledger, []),
    locationResolver: new FakeLocationResolverV2(ledger, resolutions),
    weatherTool: new FakeWeatherToolV2(ledger, {}),
    shoppingTool: new FakeShoppingToolV2(ledger),
    stylistModel: new FakeStylistModelPortV2(ledger, modelResults),
    clock: () => NOW,
  });
  return {coordinator, ledger, sessionRepository};
}

function jsonResponse(body, {ok = true, status = 200} = {}) {
  return {ok, status, async json() { return body; }};
}

test("pending destination geocoder miss falls back once and continues instead of asking again", async () => {
  const state = pendingLocationState({chatId: "pending-region"});
  const h = harness(state);

  const result = await h.coordinator.resolveTurn(request("pending-region", "turn-1", 0, "do Tatier"));
  assert.equal(result.action, "chat");
  assert.equal(result.clarification, null);
  assert.notEqual(result.assistantText, "Kam presne ideš?");

  const saved = await h.sessionRepository.read("pending-region");
  assert.equal(saved.context.destination.label, "Tatier");
  assert.equal(saved.context.destination.source, "user_text");
  assert.equal(saved.context.groundingRequirements.weatherRequired, false);
  assert.equal(saved.conversationMemory.pendingQuestion, null);
  assert.equal(h.ledger.calls("model", "plan").length, 0);
  assert.equal(h.ledger.calls("model", "final").length, 1);
  assert.ok(h.ledger.calls("location", "resolve").length >= 1);
});

test("a more specific follow-up is combined with the previous broad answer and advances without a time-of-day interrogation", async () => {
  const state = pendingLocationState({chatId: "pending-poi", attempts: ["do Tatier"]});
  const teryho = place("place:teryho", "Téryho chata, Vysoké Tatry", 49.1902, 20.1990, "poi");
  const h = harness(state, {"Téryho chata, Tatier": teryho});

  const result = await h.coordinator.resolveTurn(request("pending-poi", "turn-1", 0, "Téryho chata"));
  assert.equal(result.action, "chat");
  assert.notEqual(result.assistantText, "Kam presne ideš?");

  const saved = await h.sessionRepository.read("pending-poi");
  assert.equal(saved.context.destination.providerId, "place:teryho");
  assert.equal(saved.context.timeWindow.key, "day");
  assert.equal(saved.conversationMemory.pendingQuestion, null);
  assert.deepEqual(h.ledger.calls("location", "resolve")[0].args, {query: "Téryho chata, Tatier"});
  assert.equal(h.ledger.calls("weather", "getForecast").length, 1);
  assert.equal(h.ledger.calls("model", "plan").length, 0);
  assert.equal(h.ledger.calls("model", "final").length, 1);
});

test("remote event location wins over current GPS and broad day default avoids redundant time question", async () => {
  const state = pendingLocationState({
    chatId: "remote-concert",
    field: "eventLocation",
    activityId: "concert",
    currentLocation: martinGps,
  });
  const arena = place("place:o2-praha", "O2 arena, Praha", 50.1044, 14.4936, "poi");
  const h = harness(state, {"O2 arena Praha": arena});

  const result = await h.coordinator.resolveTurn(request("remote-concert", "turn-1", 0, "O2 arena Praha"));
  assert.equal(result.action, "chat");

  const saved = await h.sessionRepository.read("remote-concert");
  assert.equal(saved.context.eventLocation.providerId, "place:o2-praha");
  assert.equal(saved.context.currentLocationObservation.providerId, martinGps.providerId);
  assert.equal(saved.context.destination, null);
  assert.equal(saved.context.timeWindow.key, "day");
  assert.equal(h.ledger.calls("weather", "getForecast")[0].args.location.providerId, "place:o2-praha");
});

test("wedding location fragment is accepted without forcing a time-of-day question", async () => {
  const state = pendingLocationState({chatId: "wedding", field: "eventLocation", activityId: "wedding"});
  const zilina = place("place:zilina", "Žilina", 49.2231, 18.7394);
  const h = harness(state, {Žilina: zilina});

  const result = await h.coordinator.resolveTurn(request("wedding", "turn-1", 0, "Žilina"));
  assert.equal(result.action, "chat");
  const saved = await h.sessionRepository.read("wedding");
  assert.equal(saved.context.eventLocation.providerId, "place:zilina");
  assert.equal(saved.context.timeWindow.key, "day");
});

test("natural fragment answers are resolved in the context of the pending destination question", async () => {
  const cases = [
    ["Bratislava", "Bratislava"],
    ["do Košíc", "Košíc"],
    ["na Donovaly", "Donovaly"],
    ["Štrbské Pleso", "Štrbské Pleso"],
  ];

  for (let index = 0; index < cases.length; index += 1) {
    const [input, resolverQuery] = cases[index];
    const chatId = `fragment-${index}`;
    const resolved = place(`place:${index}`, input, 48 + index / 10, 17 + index / 10);
    const state = pendingLocationState({chatId});
    const h = harness(state, {[resolverQuery]: resolved});

    const result = await h.coordinator.resolveTurn(request(chatId, "turn-1", 0, input));
    assert.equal(result.action, "chat", input);
    const saved = await h.sessionRepository.read(chatId);
    assert.equal(saved.context.destination.providerId, `place:${index}`, input);
    assert.equal(saved.context.timeWindow.key, "day", input);
  }
});

test("unresolvable location answer does not create a second questionnaire turn", async () => {
  const state = pendingLocationState({chatId: "unknown-place"});
  const h = harness(state);

  const result = await h.coordinator.resolveTurn(request("unknown-place", "turn-1", 0, "nejaká dolina"));

  assert.equal(result.action, "chat");
  assert.equal(result.clarification, null);
  assert.notEqual(result.assistantText, "Kam presne ideš?");
  const saved = await h.sessionRepository.read("unknown-place");
  assert.equal(saved.conversationMemory.pendingQuestion, null);
  assert.equal(saved.context.groundingRequirements.weatherRequired, false);
  assert.equal(h.ledger.calls("model", "plan").length, 0);
  assert.equal(h.ledger.calls("model", "final").length, 1);
});

test("pending query helpers combine retained context and prefer canonical geocoder candidates", () => {
  assert.equal(cleanLocationAnswerFragmentV2("na Donovaly"), "Donovaly");
  assert.deepEqual(
    pendingLocationResolutionQueriesV2({attemptedAnswers: ["do Tatier"]}, "Téryho chata"),
    ["Téryho chata, Tatier", "Téryho chata"],
  );
  assert.deepEqual(locationQueryCandidatesV2("na Donovaly"), ["Donovaly", "na Donovaly"]);
  assert.deepEqual(locationQueryCandidatesV2("do Tatier"), ["Tatry", "Tatier", "do Tatier"]);
});

test("location resolver falls back from Open-Meteo to Nominatim for a POI", async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    const value = String(url);
    calls.push(value);
    if (value.includes("geocoding-api.open-meteo.com")) return jsonResponse({results: []});
    if (value.includes("nominatim.openstreetmap.org")) {
      return jsonResponse([{
        osm_type: "node",
        osm_id: 123456,
        class: "tourism",
        type: "alpine_hut",
        display_name: "Téryho chata, Vysoké Tatry, Slovensko",
        lat: "49.1902",
        lon: "20.1990",
      }]);
    }
    throw new Error(`unexpected URL ${value}`);
  };

  const resolved = await createOpenMeteoLocationResolverV2({fetchImpl}).resolve("Téryho chata");
  assert.equal(resolved.providerId, "nominatim:node:123456");
  assert.equal(resolved.source, "openstreetmap-nominatim");
  assert.equal(resolved.granularity, "poi");
  assert.equal(resolved.lat, 49.1902);
  assert.equal(calls.length, 2);
});

test("location resolver uses the cleaned canonical candidate first", async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    const parsed = new URL(String(url));
    calls.push(parsed.toString());
    if (parsed.hostname === "geocoding-api.open-meteo.com") {
      const query = parsed.searchParams.get("name");
      if (query === "Donovaly") {
        return jsonResponse({results: [{id: 77, name: "Donovaly", admin1: "Žilinský kraj", country: "Slovensko", latitude: 48.8777, longitude: 19.2240}]});
      }
      return jsonResponse({results: []});
    }
    if (parsed.hostname === "nominatim.openstreetmap.org") return jsonResponse([]);
    throw new Error(`unexpected URL ${parsed.toString()}`);
  };

  const resolved = await createOpenMeteoLocationResolverV2({fetchImpl}).resolve("na Donovaly");
  assert.equal(resolved.providerId, "openmeteo:77");
  assert.equal(resolved.label, "Donovaly, Žilinský kraj, Slovensko");
  assert.equal(resolved.granularity, "locality");
  assert.equal(calls.length, 1);
  assert.equal(new URL(calls[0]).searchParams.get("name"), "Donovaly");
});

test("production resolver canonicalizes the reproduced do Tatier answer before geocoding", async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    const parsed = new URL(String(url));
    calls.push(parsed.toString());
    if (parsed.hostname === "geocoding-api.open-meteo.com") {
      const query = parsed.searchParams.get("name");
      if (query === "Tatry") {
        return jsonResponse({results: [{id: 999, name: "Vysoké Tatry", admin1: "Prešovský kraj", country: "Slovensko", latitude: 49.1667, longitude: 20.1333}]});
      }
      return jsonResponse({results: []});
    }
    if (parsed.hostname === "nominatim.openstreetmap.org") return jsonResponse([]);
    throw new Error(`unexpected URL ${parsed.toString()}`);
  };

  const resolved = await createOpenMeteoLocationResolverV2({fetchImpl}).resolve("do Tatier");
  assert.equal(resolved.providerId, "openmeteo:999");
  assert.match(resolved.label, /Vysoké Tatry/u);
  assert.equal(calls.length, 1);
  assert.equal(new URL(calls[0]).searchParams.get("name"), "Tatry");
});
