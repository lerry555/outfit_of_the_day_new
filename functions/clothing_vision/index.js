"use strict";

module.exports = {
  ...require("./model_task_registry"),
  ...require("./storage_ownership"),
  ...require("./production_schema"),
  ...require("./production_allowlists"),
  createKbIndex: require("./kb_index").createKbIndex,
  validateProductionGeminiOutput:
    require("./production_output_validator").validateProductionGeminiOutput,
  adaptToProductionClientResponse:
    require("./production_response_adapter").adaptToProductionClientResponse,
  createGeminiClothingAnalyzerClient:
    require("./gemini_clothing_analyzer_client").createGeminiClothingAnalyzerClient,
  createAnalyzeClothingImageHandler:
    require("./analyze_clothing_image_handler").createAnalyzeClothingImageHandler,
  getClothingAnalyzerGeminiPromptV1:
    require("./prompts/clothing_analyzer_gemini_v1").getClothingAnalyzerGeminiPromptV1,
  GEMINI_API_KEY_SECRET:
    require("./gemini_secret_binding").GEMINI_API_KEY_SECRET,
};
