"use strict";

/** No Secret Manager import or lookup lives here. Binding is an activation-time concern. */
const SECRET_REQUIREMENTS = Object.freeze({
  openai: Object.freeze({secretName: "OPENAI_API_KEY", productionBindingVerified: false}),
  anthropic: Object.freeze({secretName: "ANTHROPIC_API_KEY", productionBindingVerified: false}),
});

function injectedCredentialProvider(getter) {
  if (typeof getter !== "function") throw new Error("credential_provider_required");
  return async () => {
    const value = await getter();
    return typeof value === "string" ? value.trim() : "";
  };
}

module.exports = {SECRET_REQUIREMENTS, injectedCredentialProvider};
