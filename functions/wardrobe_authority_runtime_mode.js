"use strict";

/**
 * Wardrobe authority runtime mode contract.
 * Production default: disabled (fail-closed).
 */

const MODE_ID = "WardrobeAuthorityRuntimeMode";
const MODE_VERSION = "wardrobe-authority-runtime-mode-v1";

const AUTHORITY_MODES = Object.freeze({
  disabled: "disabled",
  shadow: "shadow",
  controlledWrite: "controlled_write",
});

const DEFAULT_MODE = AUTHORITY_MODES.disabled;

/**
 * @param {unknown} raw
 * @returns {Readonly<{mode: string, source: string}>}
 */
function resolveWardrobeAuthorityMode(raw) {
  if (raw == null || raw === "") {
    return Object.freeze({
      mode: DEFAULT_MODE,
      source: "default_fail_closed",
      modeId: MODE_ID,
      modeVersion: MODE_VERSION,
    });
  }
  const value = String(raw).trim();
  if (!Object.values(AUTHORITY_MODES).includes(value)) {
    const err = new Error(`invalid_authority_mode:${value}`);
    err.code = "invalid_authority_mode";
    throw err;
  }
  return Object.freeze({
    mode: value,
    source: "explicit_config",
    modeId: MODE_ID,
    modeVersion: MODE_VERSION,
  });
}

function isWriteEnabled(mode) {
  return mode === AUTHORITY_MODES.controlledWrite;
}

function isShadowEnabled(mode) {
  return mode === AUTHORITY_MODES.shadow;
}

function isDisabled(mode) {
  return mode === AUTHORITY_MODES.disabled || mode == null;
}

module.exports = {
  MODE_ID,
  MODE_VERSION,
  AUTHORITY_MODES,
  DEFAULT_MODE,
  resolveWardrobeAuthorityMode,
  isWriteEnabled,
  isShadowEnabled,
  isDisabled,
};
