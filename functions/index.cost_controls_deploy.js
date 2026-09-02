"use strict";

// Deployment-only entry point, copied over index.js in the disposable CI
// checkout after preserving it as index.full.js. Never expands deploy scope.
const full = require("./index.full");
for (const name of ["stylistSimpleAgentV1", "analyzeWardrobeSmart", "analyzeClothingImage",
  "generateHomeOutfit", "finalReviewHomeOutfitCandidates", "generateHomeOutfitExplanation"]) {
  if (!full[name]) throw new Error(`approved_function_missing:${name}`);
  exports[name] = full[name];
}
