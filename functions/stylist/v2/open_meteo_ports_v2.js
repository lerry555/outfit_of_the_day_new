"use strict";

const RAIN_CODES = new Set([51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99]);
const SNOW_CODES = new Set([71, 73, 75, 77, 85, 86]);

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
  return Array.from({length: 17}, (_, i) => i + 6); // coarse daytime window 06-22
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

function createOpenMeteoLocationResolverV2({fetchImpl = fetch} = {}) {
  return Object.freeze({
    async resolve(query) {
      const text = String(query || "").trim().replace(/[.!?]+$/g, "");
      if (!text) return null;
      const url = "https://geocoding-api.open-meteo.com/v1/search?" + new URLSearchParams({
        name: text,
        count: "5",
        language: "sk",
        format: "json",
      }).toString();
      const response = await fetchImpl(url, {headers: {Accept: "application/json"}});
      if (!response.ok) throw new Error(`open_meteo_geocoding_http_${response.status}`);
      const json = await response.json();
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
      };
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
      return {
        locationProviderId: location.providerId,
        dateKey,
        timeWindowKey: String(timeWindow?.key || "day"),
        fetchedAt: new Date(clock()).toISOString(),
        source: "open-meteo",
        snapshot: buildSnapshot(json, String(timeWindow?.key || "day")),
      };
    },
  });
}

module.exports = {
  buildSnapshot,
  windowHours,
  createOpenMeteoLocationResolverV2,
  createOpenMeteoWeatherToolV2,
};
