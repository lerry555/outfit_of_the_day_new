"use strict";

const RAIN_CODES = new Set([51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99]);
const SNOW_CODES = new Set([71, 73, 75, 77, 85, 86]);

const LOCATION_ALIASES_V2 = new Map(Object.entries({
  "tatier": "Tatry",
  "vysokych tatier": "Vysoké Tatry",
  "nizkych tatier": "Nízke Tatry",
  "kosic": "Košice",
  "ziliny": "Žilina",
  "martina": "Martin",
  "prahy": "Praha",
  "viedne": "Viedeň",
  "budapesti": "Budapešť",
  "alp": "Alpy",
  "alpy": "Alpy",
  "alpach": "Alpy",
  "brna": "Brno",
  "londyna": "London",
  "pariza": "Paríž",
  "rima": "Rím",
  "milana": "Miláno",
  "mnichova": "Mníchov",
}));

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


function finiteNumbers(values) {
  return Array.isArray(values) ? values.map(Number).filter(Number.isFinite) : [];
}

function average(values) {
  const numbers = finiteNumbers(values);
  return numbers.length ? numbers.reduce((sum, value) => sum + value, 0) / numbers.length : null;
}

function atHour(values, hour) {
  if (!Array.isArray(values)) return null;
  const value = Number(values[hour]);
  return Number.isFinite(value) ? value : null;
}

function max(values) {
  const numbers = finiteNumbers(values);
  return numbers.length ? Math.max(...numbers) : null;
}

function min(values) {
  const numbers = finiteNumbers(values);
  return numbers.length ? Math.min(...numbers) : null;
}

function normalizeHourly(json) {
  const hourly = json?.hourly && typeof json.hourly === "object" ? json.hourly : {};
  const temperatures = finiteNumbers(hourly.temperature_2m);
  const rainProbability = finiteNumbers(hourly.precipitation_probability);
  const codes = finiteNumbers(hourly.weather_code);
  const wind = finiteNumbers(hourly.wind_speed_10m);
  return {temperatures, rainProbability, codes, wind};
}

function windowHours(key) {
  if (key === "morning") return [6, 7, 8, 9, 10, 11];
  if (key === "noon") return [11, 12, 13, 14, 15, 16];
  if (key === "afternoon") return [12, 13, 14, 15, 16, 17, 18];
  if (key === "evening") return [17, 18, 19, 20, 21, 22];
  if (key === "night") return [0, 1, 2, 3, 4, 5, 20, 21, 22, 23];
  return Array.from({length: 17}, (_, i) => i + 6);
}

function buildSnapshot(json, timeWindowKey = "day") {
  const {temperatures, rainProbability, codes, wind} = normalizeHourly(json);
  const hours = windowHours(timeWindowKey).filter((hour) => hour < temperatures.length || hour < codes.length || hour < wind.length);
  const pick = (values) => hours.map((hour) => Number(values[hour])).filter(Number.isFinite);
  const scopedTemperatures = pick(temperatures);
  const scopedRainProbability = pick(rainProbability);
  const scopedCodes = pick(codes);
  const scopedWind = pick(wind);
  const willRain = scopedCodes.some((code) => RAIN_CODES.has(code)) || scopedRainProbability.some((value) => value >= 40);
  const willSnow = scopedCodes.some((code) => SNOW_CODES.has(code));
  const maxWind = max(scopedWind);
  return {
    timeWindowKey,
    localHours: hours,
    temperatureC: scopedTemperatures,
    weatherCode: scopedCodes,
    precipitationProbability: scopedRainProbability,
    windKph: scopedWind,
    representativeTempC: average(scopedTemperatures),
    minTempC: min(scopedTemperatures),
    maxTempC: max(scopedTemperatures),
    willRain,
    isRainy: willRain,
    willSnow,
    isWindy: maxWind != null ? maxWind >= 30 : false,
    maxWindKph: maxWind,
    precipitationProbabilityMax: max(scopedRainProbability),
    timezone: String(json?.timezone || ""),
  };
}

function normalizeLocationQueryTextV2(value) {
  return String(value || "").trim().replace(/[.!?]+$/g, "").replace(/\s+/g, " ");
}

function foldLocationAliasKeyV2(value) {
  return normalizeLocationQueryTextV2(value)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

function canonicalLocationQueryV2(value) {
  const normalized = normalizeLocationQueryTextV2(value);
  if (!normalized) return "";
  return LOCATION_ALIASES_V2.get(foldLocationAliasKeyV2(normalized)) || normalized;
}

function locationQueryCandidatesV2(query) {
  const raw = normalizeLocationQueryTextV2(query);
  if (!raw) return [];
  const stripped = raw.replace(/^(?:(?:ja\s+)?(?:idem|ideme|pojdem|pojdeme|chystam\s+sa|chystáme\s+sa|chystame\s+sa)\s+)?(?:do|na|v|vo|k|ku|to|in|at)\s+/iu, "").trim();
  const canonical = canonicalLocationQueryV2(stripped || raw);
  // Search the best semantic candidate first. Raw conversational text stays as
  // a fallback for POIs/phrases where the preposition is genuinely useful.
  return [...new Set([canonical, stripped, raw].filter(Boolean))];
}

function openMeteoGranularityV2(result) {
  const featureCode = String(result?.feature_code || result?.featureCode || "").trim().toUpperCase();
  if (/^PCL/.test(featureCode)) return "country";
  if (/^ADM1/.test(featureCode)) return "region";
  if (/^ADM[2-5]/.test(featureCode)) return "locality";
  return "locality";
}

function nominatimGranularityV2(result) {
  const type = String(result?.addresstype || result?.type || "").trim().toLowerCase();
  if (["country"].includes(type)) return "country";
  if (["state", "region", "province"].includes(type)) return "region";
  if (["city", "town", "village", "municipality", "borough", "suburb", "quarter", "neighbourhood"].includes(type)) return "locality";
  if (["house", "building", "amenity", "attraction", "tourism", "hut", "hotel", "station", "peak", "trailhead"].includes(type)) return "poi";
  const category = String(result?.class || "").trim().toLowerCase();
  if (["tourism", "amenity", "building", "leisure", "natural"].includes(category)) return "poi";
  return "locality";
}

function locationIsTooBroadForWeatherV2(location) {
  return String(location?.granularity || "").trim().toLowerCase() === "country";
}

function openMeteoLocationFromJsonV2(json) {
  const result = Array.isArray(json?.results) ? json.results[0] : null;
  const lat = Number(result?.latitude);
  const lng = Number(result?.longitude);
  if (!result || !Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  const labelParts = [result.name, result.admin1, result.country]
    .map((value) => String(value || "").trim())
    .filter(Boolean);
  return {
    providerId: `openmeteo:${String(result.id || `${lat},${lng}`)}`,
    label: labelParts.join(", "),
    lat,
    lng,
    source: "open-meteo-geocoding",
    granularity: openMeteoGranularityV2(result),
    countryCode: String(result.country_code || "").trim().toUpperCase() || null,
  };
}

function nominatimLocationFromJsonV2(json, query) {
  const result = Array.isArray(json) ? json[0] : null;
  const lat = Number(result?.lat);
  const lng = Number(result?.lon);
  if (!result || !Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  const osmType = String(result.osm_type || "place").trim().toLowerCase() || "place";
  const osmId = String(result.osm_id || `${lat},${lng}`).trim();
  const label = String(result.display_name || result.name || query || "").trim().slice(0, 500);
  if (!label) return null;
  return {
    providerId: `nominatim:${osmType}:${osmId}`,
    label,
    lat,
    lng,
    source: "openstreetmap-nominatim",
    granularity: nominatimGranularityV2(result),
    countryCode: String(result?.address?.country_code || "").trim().toUpperCase() || null,
  };
}

async function resolveOpenMeteoLocationCandidateV2(fetchImpl, query) {
  const url = "https://geocoding-api.open-meteo.com/v1/search?" + new URLSearchParams({
    name: query,
    count: "5",
    language: "sk",
    format: "json",
  }).toString();
  const response = await fetchImpl(url, {headers: {Accept: "application/json"}});
  if (!response.ok) throw new Error(`open_meteo_geocoding_http_${response.status}`);
  return openMeteoLocationFromJsonV2(await response.json());
}

async function resolveNominatimLocationCandidateV2(fetchImpl, query) {
  const url = "https://nominatim.openstreetmap.org/search?" + new URLSearchParams({
    q: query,
    format: "jsonv2",
    addressdetails: "1",
    limit: "5",
    "accept-language": "sk,en",
  }).toString();
  const response = await fetchImpl(url, {headers: {
    Accept: "application/json",
    "Accept-Language": "sk,en;q=0.8",
    "User-Agent": "OOTD-AI-Stylist-V2/1.0",
  }});
  if (!response.ok) return null;
  return nominatimLocationFromJsonV2(await response.json(), query);
}

function createOpenMeteoLocationResolverV2({fetchImpl = fetch} = {}) {
  return Object.freeze({
    async resolve(query) {
      const candidates = locationQueryCandidatesV2(query);
      for (const candidate of candidates) {
        const openMeteo = await resolveOpenMeteoLocationCandidateV2(fetchImpl, candidate);
        if (openMeteo) return openMeteo;
        const nominatim = await resolveNominatimLocationCandidateV2(fetchImpl, candidate);
        if (nominatim) return nominatim;
      }
      return null;
    },
  });
}

function createOpenMeteoWeatherToolV2({fetchImpl = fetch, clock = () => Date.now()} = {}) {
  return Object.freeze({
    async getForecast({location, date, timeWindow}) {
      const dateKey = String(date?.dateKey || "").trim();
      if (!dateKey || !location || !Number.isFinite(Number(location.lat)) || !Number.isFinite(Number(location.lng))) {
        throw new TypeError("open_meteo_weather_target_invalid");
      }
      const url = "https://api.open-meteo.com/v1/forecast?" + new URLSearchParams({
        latitude: String(location.lat),
        longitude: String(location.lng),
        hourly: "temperature_2m,precipitation_probability,weather_code,wind_speed_10m",
        timezone: "auto",
        start_date: dateKey,
        end_date: dateKey,
      }).toString();
      const response = await fetchImpl(url, {headers: {Accept: "application/json"}});
      if (!response.ok) throw new Error(`open_meteo_weather_http_${response.status}`);
      const json = await response.json();
      const timeWindowKey = String(timeWindow?.key || "day");
      return {
        locationProviderId: location.providerId,
        dateKey,
        timeWindowKey,
        fetchedAt: new Date(clock()).toISOString(),
        source: "open-meteo",
        snapshot: buildSnapshot(json, timeWindowKey),
      };
    },
  });
}

module.exports = {
  buildSnapshot,
  canonicalLocationQueryV2,
  createOpenMeteoLocationResolverV2,
  createOpenMeteoWeatherToolV2,
  foldLocationAliasKeyV2,
  locationIsTooBroadForWeatherV2,
  localCountryLocationHintV2,
  locationQueryCandidatesV2,
  normalizeCountryNameV2,
  nominatimGranularityV2,
  nominatimLocationFromJsonV2,
  normalizeLocationQueryTextV2,
  openMeteoGranularityV2,
  openMeteoLocationFromJsonV2,
  resolveNominatimLocationCandidateV2,
  resolveOpenMeteoLocationCandidateV2,
  windowHours,
};
