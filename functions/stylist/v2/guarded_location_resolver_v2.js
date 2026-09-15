"use strict";

const {
  locationQueryCandidatesV2,
  nominatimLocationFromJsonV2,
  openMeteoLocationFromJsonV2,
  resolveNominatimLocationCandidateV2,
} = require("./open_meteo_ports_v2");

const COUNTRY_SCOPE_PREFIX_V2 = "__ootd_country__:";

function normalizeLocationIntentTextV2(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isActivityOnlyLocationQueryV2(value) {
  const normalized = normalizeLocationIntentTextV2(value);
  if (!normalized) return false;
  return /^(?:tura|turu|turistika|turistiku|hiking|trek|treking|vylet|vyletu|dovolenka|dovolenku|koncert|koncertu|festival|festivalu|svadba|svadbu|pohovor|ples|lyzovacka|lyzovacku)$/.test(normalized);
}

function scopedLocationQueryV2(query, countryCode) {
  const raw = String(query || "").trim().slice(0, 240);
  const code = String(countryCode || "").trim().toUpperCase();
  if (!raw || !/^[A-Z]{2}$/.test(code)) return raw;
  return `${COUNTRY_SCOPE_PREFIX_V2}${code}|${raw}`;
}

function parseCountryScopedLocationQueryV2(value) {
  const raw = String(value || "").trim().slice(0, 320);
  if (!raw.startsWith(COUNTRY_SCOPE_PREFIX_V2)) return {query: raw, countryCode: null};
  const rest = raw.slice(COUNTRY_SCOPE_PREFIX_V2.length);
  const splitAt = rest.indexOf("|");
  if (splitAt <= 0) return {query: raw, countryCode: null};
  const countryCode = rest.slice(0, splitAt).trim().toUpperCase();
  const query = rest.slice(splitAt + 1).trim();
  if (!query || !/^[A-Z]{2}$/.test(countryCode)) return {query: raw, countryCode: null};
  return {query, countryCode};
}

function semanticLocationQueryCandidatesV2(query) {
  const base = locationQueryCandidatesV2(query);
  const normalized = normalizeLocationIntentTextV2(query)
    .replace(/^(?:(?:ja\s+)?(?:idem|ideme|pojdem|pojdeme|chystam\s+sa)\s+)?(?:do|na|v|vo|k|ku|to|in|at)\s+/, "")
    .trim();
  const semantic = [];
  if (/^(?:tatry|tatier)$/.test(normalized)) semantic.push("Vysoké Tatry");
  return [...new Set([...semantic, ...base].filter(Boolean))];
}

function locationResultLabelV2(result) {
  return [result?.name, result?.admin1, result?.admin2, result?.country]
    .map((value) => String(value || "").trim())
    .filter(Boolean)
    .join(" ");
}

function locationResultScoreV2(result, query, originalIndex = 0) {
  const wanted = normalizeLocationIntentTextV2(query);
  const name = normalizeLocationIntentTextV2(result?.name);
  const label = normalizeLocationIntentTextV2(locationResultLabelV2(result));
  if (!wanted || !name) return Number.NEGATIVE_INFINITY;

  let score = 0;
  if (name === wanted) score += 1000;
  else if (name.startsWith(wanted) || wanted.startsWith(name)) score += 550;
  else if (name.includes(wanted) || wanted.includes(name)) score += 300;

  const wantedTokens = new Set(wanted.split(" ").filter((token) => token.length > 1));
  const labelTokens = new Set(label.split(" ").filter(Boolean));
  let matchedTokens = 0;
  for (const token of wantedTokens) if (labelTokens.has(token)) matchedTokens += 1;
  if (wantedTokens.size) score += (matchedTokens / wantedTokens.size) * 300;
  if (label === wanted) score += 200;

  const population = Math.max(0, Number(result?.population) || 0);
  score += Math.min(120, Math.log10(population + 1) * 15);
  score -= originalIndex * 0.001;
  return score;
}

function bestOpenMeteoResultV2(json, query, countryCode = null) {
  const results = Array.isArray(json?.results) ? json.results : [];
  const expectedCountryCode = String(countryCode || "").trim().toUpperCase();
  let best = null;
  let bestScore = Number.NEGATIVE_INFINITY;
  for (let index = 0; index < results.length; index += 1) {
    const result = results[index];
    const lat = Number(result?.latitude);
    const lng = Number(result?.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    const resultCountryCode = String(result?.country_code || "").trim().toUpperCase();
    if (expectedCountryCode && resultCountryCode !== expectedCountryCode) continue;
    const score = locationResultScoreV2(result, query, index);
    if (score > bestScore) {
      best = result;
      bestScore = score;
    }
  }
  return best;
}

async function resolveRankedOpenMeteoLocationV2(fetchImpl, query, countryCode = null) {
  const expectedCountryCode = String(countryCode || "").trim().toUpperCase();
  const params = {
    name: query,
    count: expectedCountryCode ? "10" : "5",
    language: "sk",
    format: "json",
  };
  if (/^[A-Z]{2}$/.test(expectedCountryCode)) params.countryCode = expectedCountryCode;
  const url = "https://geocoding-api.open-meteo.com/v1/search?" + new URLSearchParams(params).toString();
  const response = await fetchImpl(url, {headers: {Accept: "application/json"}});
  if (!response.ok) throw new Error(`open_meteo_geocoding_http_${response.status}`);
  const json = await response.json();
  const best = bestOpenMeteoResultV2(json, query, expectedCountryCode);
  return best ? openMeteoLocationFromJsonV2({results: [best]}) : null;
}

async function resolveCountryScopedNominatimLocationV2(fetchImpl, query, countryCode) {
  const url = "https://nominatim.openstreetmap.org/search?" + new URLSearchParams({
    q: query,
    format: "jsonv2",
    addressdetails: "1",
    limit: "5",
    countrycodes: String(countryCode || "").trim().toLowerCase(),
    "accept-language": "sk,en",
  }).toString();
  const response = await fetchImpl(url, {headers: {
    Accept: "application/json",
    "Accept-Language": "sk,en;q=0.8",
    "User-Agent": "OOTD-AI-Stylist-V2/1.0",
  }});
  if (!response.ok) return null;
  const resolved = nominatimLocationFromJsonV2(await response.json(), query);
  if (!resolved) return null;
  return String(resolved.countryCode || "").trim().toUpperCase() === String(countryCode || "").trim().toUpperCase() ?
    resolved : null;
}

function createGuardedOpenMeteoLocationResolverV2({fetchImpl = fetch} = {}) {
  return Object.freeze({
    async resolve(query) {
      const scoped = parseCountryScopedLocationQueryV2(query);
      if (isActivityOnlyLocationQueryV2(scoped.query)) return null;
      for (const candidate of semanticLocationQueryCandidatesV2(scoped.query)) {
        const openMeteo = await resolveRankedOpenMeteoLocationV2(fetchImpl, candidate, scoped.countryCode);
        if (openMeteo) return openMeteo;
        const nominatim = scoped.countryCode ?
          await resolveCountryScopedNominatimLocationV2(fetchImpl, candidate, scoped.countryCode) :
          await resolveNominatimLocationCandidateV2(fetchImpl, candidate);
        if (nominatim) return nominatim;
      }
      return null;
    },
  });
}

module.exports = {
  bestOpenMeteoResultV2,
  createGuardedOpenMeteoLocationResolverV2,
  isActivityOnlyLocationQueryV2,
  locationResultScoreV2,
  normalizeLocationIntentTextV2,
  parseCountryScopedLocationQueryV2,
  scopedLocationQueryV2,
  semanticLocationQueryCandidatesV2,
};
