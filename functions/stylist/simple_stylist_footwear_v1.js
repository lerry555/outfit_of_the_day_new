"use strict";

// One validation pass over model-selected IDs and supplied weather facts. This
// module does not parse user language, rank candidates or replace the agent.
const WINTRY_WMO = new Set([56, 57, 66, 67, 71, 73, 75, 77, 85, 86]);
const WINTER_TYPES = new Set(["winter_boots", "snow_boots"]);
const BOOT_TYPES = new Set(["boots", "chelsea_boots", "ankle_boots", ...WINTER_TYPES]);
const TERRAIN_TYPES = new Set(["hiking_shoes", "hiking_boots", "trail_running_shoes"]);
const SNEAKER_TYPES = new Set(["sneakers", "running_shoes", "training_shoes", "basketball_shoes"]);
const WINDOWS = Object.freeze({morning: [5, 11], noon: [12, 17], evening: [18, 23], day: [5, 23]});

function finiteNumber(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value;
}

function scopedWeatherV1(raw, key) {
  const weather = raw && typeof raw === "object" ? raw : {};
  if (key === "today" || key === "tomorrow") return weather[key] || {};
  if (key === "current") return weather.active || weather.event || weather;
  return {};
}

function footwearWeatherFactsV1(raw, key, window = "day") {
  const weather = scopedWeatherV1(raw, key);
  if (weather.fromOpenMeteo === false) return {minTempC: null, wintry: false};
  const range = WINDOWS[window] || WINDOWS.day;
  const inWindow = (values) => Array.isArray(values) && values.length === 24 ?
    values.slice(range[0], range[1] + 1).map(finiteNumber).filter((n) => n !== null) : [];
  let temperatures = inWindow(weather.hourlyTempCByLocalHour);
  if (!temperatures.length) {
    const keys = window === "morning" ? ["morningTempC"] : window === "noon" ? ["noonTempC"] :
      window === "evening" ? ["eveningTempC"] : ["morningTempC", "noonTempC", "eveningTempC", "minTempC", "tempC"];
    temperatures = keys.map((k) => finiteNumber(weather[k])).filter((n) => n !== null);
    // Do not substitute a warm afternoon for an unknown/cold requested morning.
  }
  const codes = inWindow(weather.hourlyWeatherCodeByLocalHour);
  const wintry = codes.some((code) => WINTRY_WMO.has(code)) ||
    weather.willSnow === true || weather.icyGround === true ||
    (finiteNumber(weather.snowDepthCm) ?? 0) > 0;
  return {minTempC: temperatures.length ? Math.min(...temperatures) : null, wintry};
}

function isWinterFootwearV1(item) {
  if (WINTER_TYPES.has(item.canonicalType)) return true;
  // A light Chelsea boot is not a winter boot merely because its name says boot.
  const seasons = new Set((item.seasons || []).map((s) => s.toLowerCase()));
  const winter = seasons.has("winter") || seasons.has("zima");
  const warmSeason = ["summer", "leto", "all_season", "celoročne"].some((s) => seasons.has(s));
  return BOOT_TYPES.has(item.canonicalType) && item.warmth >= 7 && winter && !warmSeason;
}

function validateFootwearV1({items, currentIds, weather, contextKey, assessment, changed}) {
  const errors = [];
  const shoes = items.filter((item) => item.bodySlots.includes("feet"));
  if (!changed) return errors; // Explanation/weather turns preserve exact current IDs.
  const facts = footwearWeatherFactsV1(weather, contextKey, assessment.weatherWindow);
  for (const shoe of shoes.filter((item) => !currentIds.includes(item.id))) {
    const winter = isWinterFootwearV1(shoe);
    // Conservative unmistakably mild conditions, not a calendar-season ban.
    // Cold/snow permits consideration, never proves traction or waterproofing.
    if (winter && !facts.wintry && facts.minTempC !== null && facts.minTempC >= 12) {
      errors.push(`winter_footwear_without_winter_conditions:${shoe.id}`);
    }
    if (assessment.use === "terrain") {
      const winterConditions = facts.wintry || (facts.minTempC !== null && facts.minTempC <= 8);
      if (!TERRAIN_TYPES.has(shoe.canonicalType) && !SNEAKER_TYPES.has(shoe.canonicalType) &&
          !(winter && winterConditions)) {
        errors.push(`terrain_footwear_not_supported:${shoe.id}`);
      }
      if (!TERRAIN_TYPES.has(shoe.canonicalType) && assessment.status !== "conditional") {
        errors.push(`terrain_footwear_requires_honest_limitation:${shoe.id}`);
      }
    }
  }
  return errors;
}

module.exports = {footwearWeatherFactsV1, isWinterFootwearV1, validateFootwearV1};
