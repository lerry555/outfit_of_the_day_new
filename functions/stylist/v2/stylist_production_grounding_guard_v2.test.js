"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  bestOpenMeteoResultV2,
  createGuardedOpenMeteoLocationResolverV2,
  parseCountryScopedLocationQueryV2,
  scopedLocationQueryV2,
} = require("./guarded_location_resolver_v2");
const {
  createGroundedStylistChatV2Handler,
  normalizeActivityFirstLocationOrderV2,
  qualifyPendingLocationQueryV2,
} = require("./stylist_production_grounding_guard_v2");

function broadPendingState(countryCode = "US", field = "destination") {
  return {
    context: {
      destination: field === "destination" ? {
        providerId: `local-country:${countryCode}`,
        label: countryCode,
        granularity: "country",
        countryCode,
      } : null,
      eventLocation: field === "eventLocation" ? {
        providerId: `local-country:${countryCode}`,
        label: countryCode,
        granularity: "country",
        countryCode,
      } : null,
    },
    conversationMemory: {
      pendingQuestion: {field},
    },
  };
}

test("activity-first destination wording is normalized without changing meaning", () => {
  assert.equal(
    normalizeActivityFirstLocationOrderV2("zajtra idem na festival do Francúzska a potrebujem outfit"),
    "zajtra idem do Francúzska na festival a potrebujem outfit",
  );
  assert.equal(
    normalizeActivityFirstLocationOrderV2("idem na svadbu v Lyone a neviem čo na seba"),
    "idem v Lyone na svadbu a neviem čo na seba",
  );
  assert.equal(
    normalizeActivityFirstLocationOrderV2("zajtra idem do Paríža na výlet"),
    "zajtra idem do Paríža na výlet",
  );
});

test("pending broad-country refinement becomes an internal country-scoped query", () => {
  const scoped = qualifyPendingLocationQueryV2("Colorado", broadPendingState("US"));
  assert.deepEqual(parseCountryScopedLocationQueryV2(scoped), {
    query: "Colorado",
    countryCode: "US",
  });

  assert.equal(
    qualifyPendingLocationQueryV2("Colorado", {
      context: {destination: {granularity: "region", countryCode: "US"}},
      conversationMemory: {pendingQuestion: {field: "destination"}},
    }),
    "Colorado",
  );
});

test("Open-Meteo ranking hard-filters a contextual parent country", () => {
  const brazil = {
    id: 1,
    name: "Colorado",
    admin1: "Paraná",
    country: "Brazília",
    country_code: "BR",
    latitude: -22.84,
    longitude: -51.97,
    population: 250000,
    feature_code: "PPL",
  };
  const usa = {
    id: 2,
    name: "Colorado",
    admin1: "Colorado",
    country: "Spojené štáty",
    country_code: "US",
    latitude: 39.0,
    longitude: -105.5,
    population: 5900000,
    feature_code: "ADM1",
  };
  assert.equal(bestOpenMeteoResultV2({results: [brazil, usa]}, "Colorado", "US"), usa);
  assert.equal(bestOpenMeteoResultV2({results: [brazil]}, "Colorado", "US"), null);
});

test("guarded resolver sends the parent country filter to Open-Meteo", async () => {
  const fetchImpl = async (url) => {
    const parsed = new URL(url);
    assert.match(parsed.hostname, /open-meteo/);
    assert.equal(parsed.searchParams.get("name"), "Colorado");
    assert.equal(parsed.searchParams.get("countryCode"), "US");
    return {
      ok: true,
      async json() {
        return {results: [
          {
            id: 11,
            name: "Colorado",
            admin1: "Colorado",
            country: "Spojené štáty",
            country_code: "US",
            latitude: 39.0,
            longitude: -105.5,
            population: 5900000,
            feature_code: "ADM1",
          },
        ]};
      },
    };
  };
  const resolver = createGuardedOpenMeteoLocationResolverV2({fetchImpl});
  const result = await resolver.resolve(scopedLocationQueryV2("Colorado", "US"));
  assert.equal(result.countryCode, "US");
  assert.match(result.label, /Colorado/);
  assert.doesNotMatch(result.label, /Braz/iu);
});

test("country-scoped Nominatim fallback also receives a hard countrycodes filter", async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    const parsed = new URL(url);
    calls.push(parsed);
    if (parsed.hostname.includes("open-meteo")) {
      assert.equal(parsed.searchParams.get("countryCode"), "US");
      return {
        ok: true,
        async json() {
          return {results: []};
        },
      };
    }
    assert.equal(parsed.hostname, "nominatim.openstreetmap.org");
    assert.equal(parsed.searchParams.get("countrycodes"), "us");
    return {
      ok: true,
      async json() {
        return [{
          osm_type: "relation",
          osm_id: 161961,
          display_name: "Colorado, United States",
          lat: "39.0000",
          lon: "-105.5000",
          addresstype: "state",
          address: {country_code: "us"},
        }];
      },
    };
  };
  const resolver = createGuardedOpenMeteoLocationResolverV2({fetchImpl});
  const result = await resolver.resolve(scopedLocationQueryV2("Colorado", "US"));
  assert.equal(result.countryCode, "US");
  assert.equal(result.granularity, "region");
  assert.equal(calls.length, 2);
});

test("production grounding wrapper prefers parent country and falls back to a new country only when explicitly named", async () => {
  const resolverCalls = [];
  const locationResolver = {
    async resolve(query) {
      resolverCalls.push(query);
      const parsed = parseCountryScopedLocationQueryV2(query);
      if (parsed.countryCode === "US" && parsed.query === "Colorado") {
        return {label: "Colorado, United States", granularity: "region", countryCode: "US", lat: 39, lng: -105};
      }
      if (parsed.countryCode === "US" && parsed.query === "Kanada") return null;
      if (query === "Kanada") {
        return {label: "Kanada", granularity: "country", countryCode: "CA"};
      }
      return null;
    },
  };
  const sessionRepository = {
    async get() { return {state: broadPendingState("US")}; },
  };
  const handlerFactory = ({locationResolver: contextualResolver}) => async (data) => ({
    message: data.message,
    resolved: await contextualResolver.resolve(data.message),
  });
  const handler = createGroundedStylistChatV2Handler({handlerFactory, locationResolver, sessionRepository});

  const colorado = await handler({chatId: "us-chat", message: "Colorado"}, {auth: {uid: "u"}});
  assert.equal(colorado.resolved.countryCode, "US");
  assert.deepEqual(resolverCalls.slice(0, 1).map(parseCountryScopedLocationQueryV2), [
    {query: "Colorado", countryCode: "US"},
  ]);

  const canada = await handler({chatId: "us-chat", message: "Kanada"}, {auth: {uid: "u"}});
  assert.equal(canada.resolved.countryCode, "CA");
  assert.deepEqual(resolverCalls.slice(1).map((entry) => parseCountryScopedLocationQueryV2(entry)), [
    {query: "Kanada", countryCode: "US"},
    {query: "Kanada", countryCode: null},
  ]);
});

test("pending refinement never escapes parent country to a global same-name result", async () => {
  const resolverCalls = [];
  const locationResolver = {
    async resolve(query) {
      resolverCalls.push(query);
      const parsed = parseCountryScopedLocationQueryV2(query);
      if (parsed.countryCode === "US" && parsed.query === "Colorado") return null;
      if (query === "Colorado") {
        return {label: "Colorado, Paraná, Brazília", granularity: "locality", countryCode: "BR", lat: -22.84, lng: -51.97};
      }
      return null;
    },
  };
  const sessionRepository = {
    async get() { return {state: broadPendingState("US")}; },
  };
  const handlerFactory = ({locationResolver: contextualResolver}) => async (data) => ({
    resolved: await contextualResolver.resolve(data.message),
  });
  const handler = createGroundedStylistChatV2Handler({handlerFactory, locationResolver, sessionRepository});

  const colorado = await handler({chatId: "us-chat", message: "Colorado"}, {auth: {uid: "u"}});
  assert.equal(colorado.resolved, null);
  assert.deepEqual(resolverCalls.map(parseCountryScopedLocationQueryV2), [
    {query: "Colorado", countryCode: "US"},
  ]);
});

test("parallel chats keep their country scopes isolated", async () => {
  const seen = [];
  const states = {
    us: broadPendingState("US"),
    fr: broadPendingState("FR"),
  };
  const sessionRepository = {
    async get({chatId}) { return {state: states[chatId]}; },
  };
  const locationResolver = {
    async resolve(query) {
      await new Promise((resolve) => setTimeout(resolve, query.includes("Colorado") ? 10 : 1));
      seen.push(parseCountryScopedLocationQueryV2(query));
      const parsed = parseCountryScopedLocationQueryV2(query);
      return {label: parsed.query, granularity: "region", countryCode: parsed.countryCode, lat: 1, lng: 1};
    },
  };
  const handlerFactory = ({locationResolver: contextualResolver}) => async (data) => ({
    resolved: await contextualResolver.resolve(data.message),
  });
  const handler = createGroundedStylistChatV2Handler({handlerFactory, locationResolver, sessionRepository});

  const [usResult, frResult] = await Promise.all([
    handler({chatId: "us", message: "Colorado"}, {auth: {uid: "u"}}),
    handler({chatId: "fr", message: "Lyon"}, {auth: {uid: "u"}}),
  ]);
  assert.equal(usResult.resolved.countryCode, "US");
  assert.equal(frResult.resolved.countryCode, "FR");
  assert.deepEqual(seen.sort((a, b) => a.countryCode.localeCompare(b.countryCode)), [
    {query: "Lyon", countryCode: "FR"},
    {query: "Colorado", countryCode: "US"},
  ]);
});
