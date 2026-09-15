"use strict";

const {createOpenMeteoLocationResolverV2} = require("./open_meteo_ports_v2");

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

function createGuardedOpenMeteoLocationResolverV2({fetchImpl = fetch} = {}) {
  const delegate = createOpenMeteoLocationResolverV2({fetchImpl});
  return Object.freeze({
    async resolve(query) {
      if (isActivityOnlyLocationQueryV2(query)) return null;
      return delegate.resolve(query);
    },
  });
}

module.exports = {
  createGuardedOpenMeteoLocationResolverV2,
  isActivityOnlyLocationQueryV2,
  normalizeLocationIntentTextV2,
};
