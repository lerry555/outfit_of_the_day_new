"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createGuardedOpenMeteoLocationResolverV2,
  isActivityOnlyLocationQueryV2,
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
