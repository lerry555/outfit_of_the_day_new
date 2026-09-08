"use strict";

// Used only in the disposable deployment checkout; never expands deploy scope.
const full = require("./index.full");
if (!full.stylistSimpleAgentV1) throw new Error("approved_function_missing");
exports.stylistSimpleAgentV1 = full.stylistSimpleAgentV1;
