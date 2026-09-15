"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  createGuardedOpenMeteoLocationResolverV2,
  countryScopedLocativeFallbackQueriesV2,
  embeddedCountryLocationScopeV2,
} = require("./guarded_location_resolver_v2");
const {
  explicitStylingDestinationCandidateV2,
} = require("./stylist_one_brain_engine_v2");
const {
  normalizeActivityFirstLocationOrderV2,
} = require("./stylist_production_grounding_guard_v2");

test("wedding in Lyon France becomes a country-scoped event-location candidate", () => {
  const normalized = normalizeActivityFirstLocationOrderV2(
    "zajtra idem na svadbu v Lyone vo Francúzsku a potrebujem outfit",
  );
  assert.equal(
    normalized,
    "zajtra idem v Lyone vo Francúzsku na svadbu a potrebujem outfit",
  );

  const candidate = explicitStylingDestinationCandidateV2(normalized);
  assert.deepEqual(candidate, {
    query: "Lyone vo Francúzsku",
    targetField: "eventLocation",
    resumeAction: "generate_outfit",
  });
  assert.deepEqual(embeddedCountryLocationScopeV2(candidate.query), {
    query: "Lyone",
    countryCode: "FR",
  });
  assert.deepEqual(countryScopedLocativeFallbackQueriesV2("Lyone", "FR"), ["Lyon"]);
});

test("guarded resolver retries a Slovak locative city form inside the explicit country only", async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    const parsed = new URL(url);
    if (parsed.hostname.includes("open-meteo")) {
      const name = parsed.searchParams.get("name");
      calls.push(`open:${name}:${parsed.searchParams.get("countryCode")}`);
      assert.equal(parsed.searchParams.get("countryCode"), "FR");
      if (name === "Lyone") {
        return {ok: true, async json() { return {results: []}; }};
      }
      assert.equal(name, "Lyon");
      return {
        ok: true,
        async json() {
          return {results: [{
            id: 2996944,
            name: "Lyon",
            admin1: "Auvergne-Rhône-Alpes",
            country: "Francúzsko",
            country_code: "FR",
            latitude: 45.74846,
            longitude: 4.84671,
            population: 522250,
            feature_code: "PPLA",
          }]};
        },
      };
    }

    assert.equal(parsed.hostname, "nominatim.openstreetmap.org");
    calls.push(`nominatim:${parsed.searchParams.get("q")}:${parsed.searchParams.get("countrycodes")}`);
    assert.equal(parsed.searchParams.get("q"), "Lyone");
    assert.equal(parsed.searchParams.get("countrycodes"), "fr");
    return {ok: true, async json() { return []; }};
  };

  const resolver = createGuardedOpenMeteoLocationResolverV2({fetchImpl});
  const result = await resolver.resolve("Lyone vo Francúzsku");
  assert.equal(result.countryCode, "FR");
  assert.match(result.label, /Lyon/iu);
  assert.deepEqual(calls, [
    "open:Lyone:FR",
    "nominatim:Lyone:fr",
    "open:Lyon:FR",
  ]);
});

test("a real city name ending in e is not stripped when the original resolves", async () => {
  const calls = [];
  const fetchImpl = async (url) => {
    const parsed = new URL(url);
    if (!parsed.hostname.includes("open-meteo")) {
      throw new Error("Nominatim must not be needed for an exact Nice hit");
    }
    const name = parsed.searchParams.get("name");
    calls.push(name);
    assert.equal(name, "Nice");
    assert.equal(parsed.searchParams.get("countryCode"), "FR");
    return {
      ok: true,
      async json() {
        return {results: [{
          id: 2990440,
          name: "Nice",
          admin1: "Provence-Alpes-Côte d'Azur",
          country: "Francúzsko",
          country_code: "FR",
          latitude: 43.70313,
          longitude: 7.26608,
          population: 342669,
          feature_code: "PPLA",
        }]};
      },
    };
  };

  const resolver = createGuardedOpenMeteoLocationResolverV2({fetchImpl});
  const result = await resolver.resolve("Nice vo Francúzsku");
  assert.equal(result.countryCode, "FR");
  assert.match(result.label, /Nice/iu);
  assert.deepEqual(calls, ["Nice"]);
});
