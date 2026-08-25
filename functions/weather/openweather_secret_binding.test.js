"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  OPENWEATHER_API_KEY_SECRET,
  resolveOpenWeatherSecret,
} = require("./openweather_secret_binding");

const indexSource = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");

test("OpenWeather resolver fails closed without its bound secret", () => {
  assert.throws(
    () => resolveOpenWeatherSecret({value: () => ""}),
    (error) => error.code === "openweather_secret_unavailable",
  );
});

test("OpenWeather resolver accepts only the bound Secret Manager value", () => {
  assert.equal(resolveOpenWeatherSecret({value: () => "test-weather-secret"}), "test-weather-secret");
  assert.equal(OPENWEATHER_API_KEY_SECRET.name, "OPENWEATHER_API_KEY");
});

test("chatWithStylist alone binds and resolves OpenWeather without legacy fallback", () => {
  const resolver = indexSource.match(
    /function getOpenWeatherKey\(\)\s*\{([\s\S]*?)\n\}/,
  );
  assert.ok(resolver);
  assert.match(resolver[1], /return resolveOpenWeatherSecret\(\);/);
  assert.doesNotMatch(resolver[1], /process\.env|functions\.config|getConfigValue/);
  const chatWithStylist = indexSource.match(
    /exports\.chatWithStylist\s*=([\s\S]*?)\.https\.onRequest/,
  );
  assert.ok(chatWithStylist);
  assert.match(
    chatWithStylist[1],
    /secrets:\s*\[[^\]]*OPENWEATHER_API_KEY_SECRET/,
  );
  assert.equal(
    [...indexSource.matchAll(/fetchWeatherFromOpenWeather\(/g)].length,
    2,
  );
});
