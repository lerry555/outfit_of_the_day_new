"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  bestOpenMeteoResultV2,
  createGuardedOpenMeteoLocationResolverV2,
  isActivityOnlyLocationQueryV2,
  semanticLocationQueryCandidatesV2,
} = require("./guarded_location_resolver_v2");

function jsonResponse(body, ok = true) {
  return {ok, status: ok ? 200 : 500, async json() { return body; }};
}

test("activity-only Slovak words are never sent to the geocoder", async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    calls.push(String(url));
    return jsonResponse({results: [{
      id: 999,
      name: "Ţāhrū’ī",
      admin1: "Hormozgan Province",
      country: "Irán",
      latitude: 27.1,
      longitude: 56.2,
    }]});
  };
  const resolver = createGuardedOpenMeteoLocationResolverV2({fetchImpl});

  assert.equal(isActivityOnlyLocationQueryV2("túru"), true);
  assert.equal(isActivityOnlyLocationQueryV2("koncert"), true);
  assert.equal(isActivityOnlyLocationQueryV2("svadbu"), true);
  assert.equal(await resolver.resolve("túru"), null);
  assert.equal(calls.length, 0);
});

test("real geographic targets still delegate to Open-Meteo", async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    calls.push(String(url));
    return jsonResponse({results: [{
      id: 123,
      name: "Vysoké Tatry",
      admin1: "Prešovský kraj",
      country: "Slovensko",
      latitude: 49.14,
      longitude: 20.22,
    }]});
  };
  const resolver = createGuardedOpenMeteoLocationResolverV2({fetchImpl});
  const location = await resolver.resolve("Vysoké Tatry");

  assert.equal(isActivityOnlyLocationQueryV2("Vysoké Tatry"), false);
  assert.equal(location.providerId, "openmeteo:123");
  assert.equal(location.countryCode, null);
  assert.equal(calls.length, 1);
});

test("generic Tatry follow-up prefers the Slovak High Tatras over an unrelated Czech namesake", async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    const parsed = new URL(String(url));
    calls.push(parsed.searchParams.get("name"));
    return jsonResponse({results: [
      {
        id: 111,
        name: "Tatry",
        admin1: "Juhočeský kraj",
        country: "Česko",
        country_code: "CZ",
        latitude: 49.18,
        longitude: 14.11,
        population: 80,
      },
      {
        id: 222,
        name: "Vysoké Tatry",
        admin1: "Prešovský kraj",
        country: "Slovensko",
        country_code: "SK",
        latitude: 49.14,
        longitude: 20.22,
        population: 4000,
      },
    ]});
  };
  const resolver = createGuardedOpenMeteoLocationResolverV2({fetchImpl});
  const location = await resolver.resolve("do Tatier");

  assert.equal(semanticLocationQueryCandidatesV2("do Tatier")[0], "Vysoké Tatry");
  assert.equal(location.providerId, "openmeteo:222");
  assert.equal(location.countryCode, "SK");
  assert.match(location.label, /Vysoké Tatry/);
  assert.match(location.label, /Slovensko/);
  assert.deepEqual(calls, ["Vysoké Tatry"]);
});

test("explicit Low Tatras are not rewritten to High Tatras", () => {
  assert.equal(semanticLocationQueryCandidatesV2("Nízke Tatry")[0], "Nízke Tatry");
});

test("same-name global places use population only as a relevance tie-breaker", () => {
  const best = bestOpenMeteoResultV2({results: [
    {
      id: 10,
      name: "Paris",
      admin1: "Texas",
      country: "United States",
      latitude: 33.66,
      longitude: -95.55,
      population: 25000,
    },
    {
      id: 20,
      name: "Paris",
      admin1: "Île-de-France",
      country: "France",
      latitude: 48.85,
      longitude: 2.35,
      population: 2100000,
    },
  ]}, "Paris");

  assert.equal(best.id, 20);
});
