from pathlib import Path

ports_path = Path("functions/stylist/v2/open_meteo_ports_v2.js")
ports = ports_path.read_text(encoding="utf-8")
marker = 'const LOCATION_ALIASES_V2 = new Map(Object.entries({'
start = ports.index(marker)
insert_at = ports.index('}));', start) + len('}));')
country_block = r'''

// ISO codes are stable data, while localized country names come from the
// Node/ICU locale database. This keeps broad-country detection generic:
// no runtime list of country spellings is maintained.
const ISO_COUNTRY_CODES_V2 = `
AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ
CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR
GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP
KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT
MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW
SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG
UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW
`.trim().split(/\s+/);

let LOCAL_COUNTRY_INDEX_V2 = null;

function normalizeCountryNameV2(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function countryNameVariantsV2(label) {
  const normalized = normalizeCountryNameV2(label);
  if (!normalized) return [];
  const variants = new Set([normalized]);
  if (normalized.length > 3 && normalized.endsWith("o")) {
    const stem = normalized.slice(0, -1);
    for (const suffix of ["a", "u", "e", "om"]) variants.add(stem + suffix);
  }
  if (normalized.length > 3 && normalized.endsWith("a")) {
    const stem = normalized.slice(0, -1);
    for (const suffix of ["y", "e", "u", "ou"]) variants.add(stem + suffix);
  }
  return [...variants];
}

function localCountryIndexV2() {
  if (LOCAL_COUNTRY_INDEX_V2) return LOCAL_COUNTRY_INDEX_V2;
  const index = new Map();
  const skNames = new Intl.DisplayNames(["sk"], {type: "region"});
  const enNames = new Intl.DisplayNames(["en"], {type: "region"});
  for (const countryCode of ISO_COUNTRY_CODES_V2) {
    const skLabel = String(skNames.of(countryCode) || "").trim();
    const enLabel = String(enNames.of(countryCode) || "").trim();
    if (skLabel && skLabel !== countryCode) {
      for (const variant of countryNameVariantsV2(skLabel)) {
        if (!index.has(variant)) index.set(variant, {countryCode, label: skLabel});
      }
    }
    if (enLabel && enLabel !== countryCode) {
      const normalizedEnglish = normalizeCountryNameV2(enLabel);
      if (normalizedEnglish && !index.has(normalizedEnglish)) {
        index.set(normalizedEnglish, {countryCode, label: skLabel || enLabel});
      }
    }
    index.set(countryCode.toLowerCase(), {countryCode, label: skLabel || enLabel || countryCode});
  }
  LOCAL_COUNTRY_INDEX_V2 = index;
  return index;
}

function localCountryLocationHintV2(query) {
  const normalized = normalizeCountryNameV2(query);
  if (!normalized) return null;
  const match = localCountryIndexV2().get(normalized);
  if (!match) return null;
  return {
    providerId: `local-country:${match.countryCode}`,
    label: match.label,
    source: "local-country-index",
    granularity: "country",
    countryCode: match.countryCode,
  };
}
'''
ports = ports[:insert_at] + country_block + ports[insert_at:]
export_old = "  locationIsTooBroadForWeatherV2,\n  locationQueryCandidatesV2,"
assert export_old in ports, "ports export anchor missing"
ports = ports.replace(export_old, "  locationIsTooBroadForWeatherV2,\n  localCountryLocationHintV2,\n  locationQueryCandidatesV2,\n  normalizeCountryNameV2,", 1)
ports_path.write_text(ports, encoding="utf-8")

engine_path = Path("functions/stylist/v2/stylist_one_brain_engine_v2.js")
engine = engine_path.read_text(encoding="utf-8")
import_old = 'const {locationIsTooBroadForWeatherV2} = require("./open_meteo_ports_v2");'
assert import_old in engine, "engine import anchor missing"
engine = engine.replace(import_old, 'const {locationIsTooBroadForWeatherV2, localCountryLocationHintV2} = require("./open_meteo_ports_v2");', 1)
needle = "let resolvedExplicitDestination = null;"
pos = engine.index(needle)
block_start = engine.rfind("\n", 0, pos) + 1
block_end = engine.index("          if (resolvedExplicitDestination) {", pos)
replacement = (
    '          // Country-level destinations must be deterministic even when the\n'
    '          // external geocoder is unavailable or cannot understand an inflected\n'
    '          // Slovak form such as "Švajčiarska". Resolve a local ISO/ICU country\n'
    '          // hint first; use the network resolver only for more specific places.\n'
    '          let resolvedExplicitDestination = localCountryLocationHintV2(explicitDestination.query);\n'
    '          if (!resolvedExplicitDestination) {\n'
    '            try {\n'
    '              resolvedExplicitDestination = await locationResolver.resolve(explicitDestination.query);\n'
    '            } catch (_) {\n'
    '              resolvedExplicitDestination = null;\n'
    '            }\n'
    '          }\n'
)
engine = engine[:block_start] + replacement + engine[block_end:]
engine_path.write_text(engine, encoding="utf-8")

test_path = Path("functions/stylist/v2/stylist_general_location_layering_v2.test.js")
tests = test_path.read_text(encoding="utf-8")
test_import = 'const {oneBrainPromptV2} = require("./openai_one_brain_model_port_v2");\n'
assert test_import in tests, "test import anchor missing"
tests = tests.replace(test_import, test_import + 'const {localCountryLocationHintV2} = require("./open_meteo_ports_v2");\n', 1)

first_test = 'test("general destination extractor finds Poland without country hard-coding", () => {'
assert first_test in tests, "first test anchor missing"
extra_tests = r'''test("local country hint recognizes inflected Slovak country forms without network geocoding", () => {
  assert.equal(localCountryLocationHintV2("Svajciarska")?.countryCode, "CH");
  assert.equal(localCountryLocationHintV2("polska")?.countryCode, "PL");
  assert.equal(localCountryLocationHintV2("Rakuska")?.countryCode, "AT");
  assert.equal(localCountryLocationHintV2("Francuzska")?.countryCode, "FR");
  assert.equal(localCountryLocationHintV2("Viedne"), null, "a city must not be promoted to country");
});

test("exact real Swiss hiking prompt clarifies even when external geocoder is unavailable", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brain: 0, location: 0, wardrobe: 0, weather: 0, shopping: 0, query: null};
  const engine = createStylistOneBrainEngineV2({
    sessionRepository: repository,
    ...enginePorts({calls, resolvedLocation: null}),
    clock: () => NOW,
  });

  const result = await engine.resolveTurn({
    uid: "u_exact_swiss_country",
    request: request("nazdar divocak zajtra ideme do Svajciarska na turu a ja neviem co si mam obliect"),
    bootstrapInput: {
      currentOutfitItemIds: [],
      persistedSelectionReasonsByItemId: {},
      knownExplicitDurableChoices: {},
    },
  });

  assert.equal(result.action, "clarify");
  assert.equal(result.clarification.field, "destination");
  assert.match(result.assistantText, /Kam približne/);
  assert.equal(calls.location, 0, "country recognition must not depend on external geocoder availability");
  assert.equal(calls.brain, 1, "Brain may parse scenario facts but cannot bypass the runtime country guard");
  assert.equal(calls.wardrobe, 0);
  assert.equal(calls.weather, 0);
});

'''
tests = tests.replace(first_test, extra_tests + first_test, 1)

old_expect = '  assert.equal(calls.query, "polska");\n  assert.equal(calls.location, 1);'
assert old_expect in tests, "country expectation anchor missing"
tests = tests.replace(old_expect, '  assert.equal(calls.query, null);\n  assert.equal(calls.location, 0, "known country must be classified locally, without network geocoding");', 1)

pending_start = tests.index('test("pending location answer cannot dead-end as bare acknowledgement"')
resolver_start = tests.index("    locationResolver: {", pending_start)
resolver_end = tests.index("    weatherTool:", resolver_start)
resolver_new = '''    locationResolver: {
      async resolve(query) {
        calls.location += 1;
        calls.queries.push(query);
        return {providerId: "geo:alps", label: "Alpy", lat: 46.5, lng: 10.0,
          source: "fake-geocoder", granularity: "region", countryCode: "CH"};
      },
    },
'''
tests = tests[:resolver_start] + resolver_new + tests[resolver_end:]

old_pending = '  assert.equal(calls.location, 2);\n  assert.equal(calls.queries[1], "do alp");'
assert old_pending in tests, "pending assertion anchor missing"
tests = tests.replace(old_pending, '  assert.equal(calls.location, 1, "only the specific Alps follow-up needs network geocoding");\n  assert.equal(calls.queries[0], "do alp");', 1)
test_path.write_text(tests, encoding="utf-8")

runtime_test_path = Path("functions/stylist/v2/stylist_one_brain_runtime_v2.test.js")
runtime_tests = runtime_test_path.read_text(encoding="utf-8")
runtime_test_start = runtime_tests.index('test("One Brain: country-level hike is narrowed deterministically before the answer stage"')
runtime_test_end = runtime_tests.index('test("One Brain: neviem permanently consumes the pending field', runtime_test_start)
runtime_block = runtime_tests[runtime_test_start:runtime_test_end]
old_runtime_assert = '  assert.equal(calls.location, 1);'
assert old_runtime_assert in runtime_block, "runtime country location assertion missing"
runtime_block = runtime_block.replace(old_runtime_assert, '  assert.equal(calls.location || 0, 0, "broad-country guard must not depend on external geocoder");', 1)
runtime_tests = runtime_tests[:runtime_test_start] + runtime_block + runtime_tests[runtime_test_end:]
runtime_test_path.write_text(runtime_tests, encoding="utf-8")