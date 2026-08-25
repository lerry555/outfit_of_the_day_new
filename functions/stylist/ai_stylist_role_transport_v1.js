"use strict";

// The canonical implementation lives inside the isolated deploy codebase so
// a selective smoke deploy never packages the dirty default Functions source.
// This compatibility export keeps existing offline tests/imports stable.
module.exports = require("../ai_stylist_dev_shadow_codebase/role_transport_v1");
