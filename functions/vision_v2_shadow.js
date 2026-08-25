"use strict";

const crypto = require("crypto");

const SCHEMA_VERSION = 9;
const MODEL_VERSION = "gpt-4o-mini";
const MAX_IDENTITY_CANDIDATES = 3;

const OBSERVATION_ENUMS = Object.freeze({
  coverage: ["minimal", "partial", "full"],
  hasHood: [true, false],
  frontClosure: ["none", "partial_zip", "full_zip", "buttons", "snaps", "other"],
  visibleBulk: ["low", "medium", "high"],
  surfaceAppearance: [
    "knit", "woven", "fleece_like", "quilted", "smooth", "textured", "mesh",
    "leather_like",
  ],
  necklineShape: ["crew", "v_neck", "scoop", "high_neck", "collared", "other"],
  visiblePocketStructure: ["none", "standard", "cargo", "patch", "other"],
  visibleStretchCue: [true, false],
  sportyCues: ["low", "medium", "high"],
  formalCues: ["low", "medium", "high"],
  footwearConstruction: ["open", "partially_open", "closed"],
  footwearFastening: [
    "laces", "zipper", "elastic_side_panels", "slip_on", "straps", "buckles",
    "other",
  ],
  soleProfile: ["thin", "standard", "chunky"],
  visibleTread: ["low", "moderate", "pronounced"],
  footwearUpperHeight: ["low_cut", "ankle", "high_shaft"],
});
const OBSERVATION_STATES = ["observed", "unknown", "not_visible", "not_applicable"];
const VISIBILITY_SCOPES = ["complete", "sufficient", "partial", "not_visible"];
const VISUAL_REGIONS = [
  "full_silhouette", "front", "side", "back", "collar", "neckline",
  "pocket_area", "footwear_upper", "fastening_area", "sole_profile",
  "outsole", "surface_detail",
];
const INPUT_ASSESSMENTS = [
  "valid_single_item", "multiple_items", "insufficient_visual_information",
  "non_wardrobe_object", "ambiguous_subject",
];
const SUBJECT_CARDINALITY_STATES = [
  "single_item_supported", "single_item_uncertain", "multiple_items",
  "fragment_only", "no_wardrobe_subject", "ambiguous_subject",
];
const SAME_ITEM_STATES = [
  "same_item_supported", "same_item_uncertain", "different_items_suspected",
  "conflicting_subjects", "not_applicable",
];
const SUBJECT_DOMAINS = [
  "garment_upper", "garment_lower", "garment_outerwear", "footwear",
  "accessory", "unknown", "mixed",
];
const FRAMING_CLASSES = [
  "full_item", "mostly_visible", "partial_item", "detail_only",
  "ambiguous_framing", "no_item",
];
const ITEM_EXTENTS = ["whole", "broad", "local", "indeterminate"];
const SILHOUETTE_CONTINUITY = [
  "continuous", "partially_continuous", "local_only", "indeterminate",
];
const SUBJECT_ORIENTATIONS = ["front", "side", "back", "mixed", "unknown"];
const BOUNDARIES = ["top", "bottom", "left", "right"];
const CROP_INDICATORS = [
  "top_cropped", "bottom_cropped", "left_cropped", "right_cropped",
  "severe_crop",
];
const QUALITY_OCCLUSION = ["none", "partial", "substantial"];
const QUALITY_LEVELS = ["low", "medium", "high"];
const PROPERTY_CONFIDENCE_RUBRIC = Object.freeze({
  coverage:
    "Garment coverage means how much of the wearer's body this garment shape " +
    "would cover, not whether the item is fully inside the image. Use minimal " +
    "for visibly low-coverage shapes such as sleeveless tank-like garments, " +
    "partial for intermediate coverage, and full for long/full coverage. Very " +
    "high requires the complete garment shape to be visible.",
  hasHood: "Very high only when the full collar/back attachment region is visible; otherwise not_visible.",
  frontClosure: "Very high only when the complete front closure region is unobstructed.",
  visibleBulk: "Usually high or medium because a single view can distort volume; never infer insulation.",
  surfaceAppearance: "Describe visible surface only, not material composition; use medium when texture detail is limited.",
  necklineShape: "Very high only for a clear unobstructed neckline; covered or cropped means not_visible.",
  visiblePocketStructure:
    "Observed none requires all pocket-relevant front and side regions to be " +
    "visible; a single front view usually requires unknown or not_visible " +
    "because side/back pockets may be hidden. Very high confidence for none " +
    "is exceptional. A clearly visible pocket type may use high confidence.",
  visibleStretchCue: "Observed false requires a directly visible construction cue proving absence; otherwise unknown/not_visible.",
  sportyCues: "A gestalt cue, normally medium/high rather than very high.",
  formalCues: "A gestalt cue, normally medium/high rather than very high.",
  footwearConstruction: "Very high only when the complete upper construction is visible.",
  footwearFastening: "Very high only when the entry/fastening region is clearly visible.",
  soleProfile: "Use high/medium from a clear side view; hidden side profile means not_visible.",
  visibleTread: "Very high only for a clear outsole view; outsole outside frame means not_visible, visible but unclear means unknown.",
  footwearUpperHeight: "Use high/medium from a clear side view showing sole through opening.",
});

function stripCodeFences(value) {
  let text = String(value || "").trim();
  if (text.startsWith("```")) {
    const newline = text.indexOf("\n");
    if (newline >= 0) text = text.slice(newline + 1);
  }
  if (text.endsWith("```")) text = text.slice(0, text.lastIndexOf("```")).trim();
  return text;
}

function normalizeTaxonomy(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value
    .filter((item) => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => /^[a-z][a-z0-9_]{1,63}$/.test(item)))]
    .sort();
}

function parseVisionV2Response(rawText, {
  allowedCanonicalTypes,
  analysisId,
  sourceReference,
  observedAt,
  modelVersion = MODEL_VERSION,
} = {}) {
  const errors = [];
  let raw;
  try {
    raw = JSON.parse(stripCodeFences(rawText));
  } catch (_) {
    return {ok: false, errors: ["invalid_json"], value: null};
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return {ok: false, errors: ["root_not_object"], value: null};
  }

  const quality = parseQuality(raw.quality, errors);
  const inputAssessment = INPUT_ASSESSMENTS.includes(raw.inputAssessment) ?
    raw.inputAssessment : "insufficient_visual_information";
  if (!INPUT_ASSESSMENTS.includes(raw.inputAssessment)) {
    errors.push("input_assessment.invalid");
  }
  const subjectAssessment = parseSubjectAssessment(
    raw.subjectAssessment, errors);
  const observations = {};
  const inputObservations = raw.observations;
  if (!inputObservations || typeof inputObservations !== "object" ||
      Array.isArray(inputObservations)) {
    errors.push("missing_observations");
  }
  for (const [property, allowedValues] of Object.entries(OBSERVATION_ENUMS)) {
    const parsed = parseObservation(inputObservations && inputObservations[property],
      property, allowedValues, errors);
    if (parsed) observations[property] = parsed;
  }

  const taxonomy = new Set(normalizeTaxonomy(allowedCanonicalTypes));
  const candidates = parseIdentityCandidates(raw.identityCandidates, taxonomy, errors);
  const directInferences = raw.directInferences == null ? {} :
    (typeof raw.directInferences === "object" && !Array.isArray(raw.directInferences) ?
      raw.directInferences : {});
  if (raw.directInferences != null && directInferences !== raw.directInferences) {
    errors.push("invalid_direct_inferences");
  }

  const value = {
    schemaVersion: SCHEMA_VERSION,
    analysisId: String(analysisId || raw.analysisId || "").trim(),
    modelVersion: String(modelVersion || raw.modelVersion || "").trim(),
    sourceReference: String(sourceReference || "").trim(),
    observedAt: String(observedAt || new Date().toISOString()),
    quality,
    inputAssessment,
    subjectAssessment,
    observations,
    identityCandidates: candidates,
    directInferences,
    validationErrors: [...new Set(errors)].sort(),
  };
  if (!value.analysisId) errors.push("missing_analysis_id");
  if (!value.sourceReference) errors.push("missing_source_reference");
  value.validationErrors = [...new Set(errors)].sort();
  return {ok: true, errors: value.validationErrors, value};
}

function parseSubjectAssessment(value, errors) {
  const input = value && typeof value === "object" && !Array.isArray(value) ?
    value : {};
  const result = {
    subjectCountEstimate: Number.isInteger(input.subjectCountEstimate) ?
      Math.max(0, Math.min(3, input.subjectCountEstimate)) : 0,
    primarySubjectPresent: input.primarySubjectPresent === true,
    reasonCodes: Array.isArray(input.reasonCodes) ?
      [...new Set(input.reasonCodes.filter((item) => typeof item === "string"))]
        .sort() : [],
  };
  if (!Number.isInteger(input.subjectCountEstimate)) {
    errors.push("subject_assessment.subject_count.invalid");
  }
  copyEnum(input, result, "cardinalityState",
    SUBJECT_CARDINALITY_STATES, errors, "subject_assessment");
  copyEnum(input, result, "sameItemConsistency",
    SAME_ITEM_STATES, errors, "subject_assessment");
  copyEnum(input, result, "subjectDomain",
    SUBJECT_DOMAINS, errors, "subject_assessment");
  copyEnum(input, result, "framingClass",
    FRAMING_CLASSES, errors, "subject_assessment");
  result.framingAttestations = parseFramingAttestations(
    input.framingAttestations, errors);
  return result;
}

function parseFramingAttestations(value, errors) {
  const input = value && typeof value === "object" && !Array.isArray(value) ?
    value : {};
  const result = {};
  for (const property of ["localDetailOnly", "primarySilhouetteContinuous"]) {
    if (typeof input[property] === "boolean") result[property] = input[property];
    else errors.push(`framing_attestations.${property}.invalid`);
  }
  for (const [property, allowed] of [
    ["visibleItemExtent", ITEM_EXTENTS],
    ["subjectOrientation", SUBJECT_ORIENTATIONS],
  ]) copyEnum(input, result, property, allowed, errors, "framing_attestations");
  for (const [property, allowed] of [
    ["visibleBoundaries", BOUNDARIES],
    ["cropIndicators", CROP_INDICATORS],
  ]) {
    if (Array.isArray(input[property]) &&
        input[property].every((item) => allowed.includes(item))) {
      result[property] = [...new Set(input[property])].sort();
    } else {
      errors.push(`framing_attestations.${property}.invalid`);
      result[property] = [];
    }
  }
  return result;
}

function parseQuality(value, errors) {
  const input = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  if (input !== value) errors.push("missing_quality");
  const output = {};
  if (typeof input.itemFullyVisible === "boolean") {
    output.itemFullyVisible = input.itemFullyVisible;
  } else {
    errors.push("quality.itemFullyVisible.invalid");
  }
  copyEnum(input, output, "occlusion", QUALITY_OCCLUSION, errors, "quality");
  copyEnum(input, output, "backgroundInterference", QUALITY_LEVELS, errors, "quality");
  copyEnum(input, output, "clarity", QUALITY_LEVELS, errors, "quality");
  return output;
}

function copyEnum(input, output, property, allowed, errors, prefix) {
  if (allowed.includes(input[property])) output[property] = input[property];
  else errors.push(`${prefix}.${property}.invalid`);
}

function parseObservation(value, property, allowedValues, errors) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    errors.push(`observations.${property}.missing`);
    return null;
  }
  if (!OBSERVATION_STATES.includes(value.state)) {
    errors.push(`observations.${property}.state.invalid`);
    return null;
  }
  if (!VISIBILITY_SCOPES.includes(value.visibilityScope)) {
    errors.push(`observations.${property}.visibility_scope.invalid`);
    return null;
  }
  if (!Array.isArray(value.visibleRegions) ||
      value.visibleRegions.some((item) => !VISUAL_REGIONS.includes(item))) {
    errors.push(`observations.${property}.visible_regions.invalid`);
    return null;
  }
  const visibleRegions = [...new Set(value.visibleRegions)].sort();
  const confidence = Number(value.confidence);
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
    errors.push(`observations.${property}.confidence.invalid`);
    return null;
  }
  if (value.state !== "observed") {
    return {
      state: value.state,
      confidence,
      visibilityScope: value.visibilityScope,
      visibleRegions,
    };
  }
  if (!allowedValues.includes(value.value)) {
    errors.push(`observations.${property}.value.invalid`);
    return null;
  }
  return {
    state: "observed",
    value: value.value,
    confidence,
    visibilityScope: value.visibilityScope,
    visibleRegions,
  };
}

function parseIdentityCandidates(value, taxonomy, errors) {
  if (!Array.isArray(value)) {
    errors.push("identity_candidates.invalid");
    return [];
  }
  const result = [];
  const seen = new Set();
  for (const candidate of value.slice(0, MAX_IDENTITY_CANDIDATES)) {
    if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
      errors.push("identity_candidate.invalid");
      continue;
    }
    const canonicalType = String(candidate.canonicalType || "").trim();
    const confidence = Number(candidate.confidence);
    if (!taxonomy.has(canonicalType)) {
      errors.push(`identity_candidate.canonical.invalid:${canonicalType || "empty"}`);
      continue;
    }
    if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
      errors.push(`identity_candidate.confidence.invalid:${canonicalType}`);
      continue;
    }
    if (seen.has(canonicalType)) continue;
    seen.add(canonicalType);
    const definingObservations = parseObservationReferences(
      candidate.definingObservations);
    const supportingObservations = parseObservationReferences(
      candidate.supportingObservations);
    if (!Array.isArray(candidate.definingObservations)) {
      errors.push(`identity_candidate.defining_observations.invalid:${canonicalType}`);
    }
    if (!Array.isArray(candidate.supportingObservations)) {
      errors.push(`identity_candidate.supporting_observations.invalid:${canonicalType}`);
    }
    result.push({
      canonicalType,
      confidence,
      definingObservations,
      supportingObservations,
    });
  }
  result.sort((a, b) =>
    b.confidence - a.confidence || a.canonicalType.localeCompare(b.canonicalType));
  const total = result.reduce((sum, item) => sum + item.confidence, 0);
  if (total > 1.000001) {
    for (const item of result) item.confidence = item.confidence / total;
    errors.push("identity_candidates.confidence_normalized");
  }
  return result;
}

function parseObservationReferences(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value
    .filter((item) => typeof item === "string" &&
      Object.hasOwn(OBSERVATION_ENUMS, item)))].sort();
}

function buildVisionV2Prompt(canonicalTypes) {
  const taxonomy = normalizeTaxonomy(canonicalTypes);
  return [
    "Analyze exactly one clothing item. Return one strict JSON object only.",
    "Before observations: count separate wardrobe subjects, decide whether all visible parts belong",
    "to one physical item, classify framing, and classify the broad subject domain.",
    "A local feature detail is not a whole item. A sole is not sneaker identity, a zipper is not",
    "jacket identity, and a pocket detail is not pants identity.",
    "Declare framingClass separately from framingAttestations. Attest boundaries, extent,",
    "silhouette continuity, orientation, local-detail status, and crop independently.",
    "full_item is forbidden when only a neckline, zipper, pocket, fastening, tread, sole,",
    "surface patch, or other local construction detail is shown.",
    "A local property may be observed without proving a whole-item silhouette or family.",
    "Two separate garments or footwear objects must be multiple_items or ambiguous_subject;",
    "never merge their observations into one identity.",
    "First assess the input as valid_single_item, multiple_items, insufficient_visual_information,",
    "non_wardrobe_object, or ambiguous_subject. Do not force a clothing identity for invalid input.",
    "Separate visible observations from identity inference. Do not infer capabilities.",
    "Evaluate only observations applicable to subjectDomain. Garment-only properties on footwear",
    "and footwear-only properties on garments MUST be not_applicable, never observed none/false.",
    "Never return warmth, mobility, breathability, wind/rain protection, formality,",
    "walking comfort, traction, seasons, occasions, or layer roles.",
    "For every observation use {state,value?,confidence,visibilityScope,visibleRegions}.",
    "state is observed, unknown, not_visible, or not_applicable.",
    "Use observed false only when absence is actually visible. If hidden by angle, use not_visible.",
    "ABSENCE OF VISIBLE EVIDENCE IS NOT A NEGATIVE OBSERVATION.",
    "none/false requires positive evidence that the entire relevant region and path are visible.",
    "Low contrast, crop, occlusion, or the wrong orientation cannot corroborate absence.",
    "For upper/outerwear closure assess the full front closure path. A trousers fly/waistband",
    "is a different visual question and must not be called closure=none merely because no zip is obvious.",
    "For EACH property first decide whether its relevant region is in the image.",
    "visibilityScope is complete, sufficient, partial, or not_visible and refers only to",
    "the region needed to judge that property, not to the whole item or image.",
    "visibleRegions must list only actually shown regions from this enum:",
    JSON.stringify(VISUAL_REGIONS),
    "visibleRegions is the list of ALL actually visible evidence areas relevant",
    "to that specific observation in THIS image. The same vocabulary applies to",
    "positives and negatives. full_silhouette never substitutes for a required",
    "property-specific region.",
    "If the collar area is visible, include collar. If the back is visible, include back.",
    "If the front is visible, include front. If a side is visible, include side.",
    "If the pocket zone is visible, include pocket_area. If a fastening path is visible,",
    "include fastening_area (and footwear_upper for footwear fastening).",
    "Keep visibleRegions consistent with every POSITIVE observed value.",
    "Positive examples: hasHood=true must include collar or back;",
    "a concrete necklineShape must include neckline;",
    "a visible zipper/front closure must include front or fastening_area;",
    "cargo or standard pockets must include pocket_area;",
    "footwear fastening must include fastening_area or footwear_upper;",
    "visible tread must include outsole.",
    "ABSENCE REGION-SET RULES (match the downstream visibility contract):",
    "For an observed absence, listing one loosely related region is usually not enough.",
    "Declare every property-specific region that is actually visible and used as evidence.",
    "If several required evidence areas are visible together, declare all of them.",
    "Never invent a region that is not truly shown. Never add a region only to pass qualification.",
    "If a required evidence area is outside the view, use not_visible or unknown per the",
    "existing rules—do not fabricate absence with incomplete evidence.",
    "Complementary same-item views may later combine declared regions downstream;",
    "each view must still declare only what THAT image actually shows.",
    "hasHood=false: downstream absence trust needs collar AND back evidence.",
    "Declare collar only when the collar/neck attachment area is visible.",
    "Declare back only when the back/hood-attachment area is visible.",
    "collar+back together is justified only when both areas are truly shown",
    "(one mixed/back-inclusive view, or separately across complementary same-item views).",
    "A front/collar-only view must NOT invent back coverage; prefer hasHood=not_visible",
    "unless the complete collar/back attachment path is actually visible.",
    "visiblePocketStructure=none: downstream absence trust needs front AND side AND",
    "pocket_area, complete scope, and complementary same-item views.",
    "Declare front when the front is visible; side when a side is visible;",
    "pocket_area when the zone where a pocket would appear is directly visible.",
    "Do not invent side or pocket_area from a pure back view that does not show them.",
    "frontClosure=none: only when this view can inspect the front closure path.",
    "Declare front (and fastening_area when that path is shown). Scope must be sufficient.",
    "A back-only view MUST NOT claim frontClosure=none merely because a zipper is unseen;",
    "use frontClosure=not_visible or unknown instead.",
    "A front or mixed view without a visible closure construction may use none with front.",
    "visibleStretchCue=false remains almost never valid on a static photo; prefer unknown",
    "or not_visible. Do not claim elasticity absence from a resting image.",
    "Worked examples:",
    "A) Hood absence with back/mixed view showing collar and back attachment: hasHood=false",
    "with visibleRegions including collar and back.",
    "B) Hood absence on front-only/collar-only view: hasHood=not_visible (do not invent back).",
    "C) Pocket absence when front, side, and pocket zone are visible: none with those regions.",
    "D) Pocket absence with only full_silhouette: invalid; use not_visible/unknown instead.",
    "E) Front view with no closure construction: frontClosure=none with front.",
    "F) Back view where the front closure path is unseen: frontClosure=not_visible or unknown,",
    "never known none.",
    "G) Positive full_zip: frontClosure=full_zip with front and/or fastening_area.",
    "H) Prefer unknown/not_visible over inventing an absence region set.",
    "Counterexamples (invalid): hasHood=false with only full_silhouette;",
    "visiblePocketStructure=none with only full_silhouette;",
    "frontClosure=none on a back-only view; inventing side/back/pocket_area not shown.",
    "A negative value requires complete scope for regions that may extend to side/back,",
    "or sufficient scope only where the relevant region is inherently local and visible.",
    "If that region is outside the view or only its opposite side is shown, state MUST be not_visible.",
    "A shoe shown only from above or the side MUST use visibleTread=not_visible when the outsole tread is not shown.",
    "A front-only top MUST use hasHood=not_visible unless the hood or the complete collar/back attachment area is visible.",
    "Use unknown only when the relevant region IS visible but its construction or value cannot be judged reliably.",
    "Stretch is usually unknown/not_visible in a static image; never infer false from no obvious stretch.",
    "necklineShape describes only visible neckline geometry; use not_visible when the neckline is cropped or covered.",
    "visiblePocketStructure describes visible external pockets, not storage capacity or function.",
    "footwearFastening describes only a visible fastening/entry construction.",
    "Property confidence measures direct visibility of this property in this image.",
    "0.95 is exceptional: only an unmistakable directly visible detail with no reasonable alternative.",
    "Do not repeat 0.95 as a generic confidence across many properties.",
    "0.80-0.94 means clear with minor uncertainty; 0.60-0.79 means probable.",
    "Below 0.60 prefer unknown or not_visible instead of an observed guess.",
    "Apply this per-property confidence rubric:",
    JSON.stringify(PROPERTY_CONFIDENCE_RUBRIC),
    "Do not confuse garment coverage with itemFullyVisible; they measure different things.",
    "itemFullyVisible means the complete silhouette is inside the frame.",
    "occlusion is physical obstruction; reverse-side or out-of-frame details use per-property not_visible.",
    "backgroundInterference measures impaired boundaries; clarity measures focus, lighting and detail.",
    "Unknown means the image cannot support a claim. Do not insert neutral defaults.",
    "Return at most 3 identity candidates. They must come only from this taxonomy:",
    JSON.stringify(taxonomy),
    "Identity reasoning order is mandatory: first finish observations, then identify the broad garment/footwear family,",
    "then check visible subtype-defining evidence, and only then propose a specific subtype.",
    "Each candidate must separately list definingObservations and supportingObservations.",
    "A defining observation is indispensable for distinguishing this subtype from sibling types.",
    "A supporting observation is compatible but does not distinguish the subtype by itself.",
    "List only OBSERVED properties. Generic image visibility is never identity support.",
    "Coverage, closure, smooth surface, laces, closed construction and generic sporty appearance are often neutral.",
    "Do not list them as defining unless that exact value distinguishes the candidate from sibling types.",
    "Before returning candidates, reconsider every observed defining feature against the allowed canonical keys.",
    "Observed necklineShape=v_neck requires considering v_neck_t_shirt; crew does not support that subtype.",
    "Identity confidence measures the strength of those listed visible observations for this exact canonical.",
    "Candidate confidences are 0..1 and their sum must not exceed 1.",
    "If identity is ambiguous, return fewer candidates or an empty array.",
    "Prefer a supported general canonical over an unsupported specific subtype.",
    "A specific subtype above 0.70 requires all required definingObservations to be directly visible.",
    "If defining evidence is absent, prefer a generic canonical when one exists.",
    "Generic canonical is not a fallback for partial/detail framing. detail_only, multiple_items,",
    "mixed domain, or inconsistent subjects must return no identity candidates.",
    "If no generic canonical exists, keep the subtype uncertain rather than pretending it is confirmed.",
    "A sporty-looking low shoe is not automatically running_shoes.",
    "A high-top fashion sneaker is not automatically basketball_shoes.",
    "An outdoor-looking jacket is not automatically hiking_jacket.",
    "Plain trousers are not automatically chinos.",
    "Performance subtypes require visible construction evidence beyond aesthetic or sporty cues.",
    "For footwear, preserve a generic sneakers or boots candidate when the broad family is clear but",
    "performance use is not visually established. Never infer intended sport or activity as a visual fact.",
    "Generic full-length woven trousers do not by themselves justify chinos above 0.70.",
    "Puffer jacket above 0.70 requires both clearly quilted/padded construction and high visible bulk.",
    "Never use identity confidence 1.0; reserve at most 0.95 for unmistakable identity.",
    "Exact value enums per observation:",
    JSON.stringify(OBSERVATION_ENUMS),
    "The attached JSON Schema is authoritative. Populate every observation property.",
  ].join("\n");
}

function buildVisionV2ResponseFormat(canonicalTypes) {
  const observationProperties = {};
  for (const [property, values] of Object.entries(OBSERVATION_ENUMS)) {
    observationProperties[property] = {
      description:
        "Classify region visibility before value. Use not_visible when the " +
        "property's relevant region is outside the view; use unknown only " +
        "when that region is visible but inconclusive.",
      anyOf: [
        {
          description:
            "Directly visible positive or negative observation; never infer " +
            "absence from a hidden region.",
          type: "object",
          additionalProperties: false,
          required: [
            "state", "value", "confidence", "visibilityScope", "visibleRegions",
          ],
          properties: {
            state: {type: "string", const: "observed"},
            value: {
              type: typeof values[0] === "boolean" ? "boolean" : "string",
              enum: values,
            },
            confidence: {type: "number", minimum: 0, maximum: 1},
            visibilityScope: {
              type: "string",
              enum: VISIBILITY_SCOPES,
            },
            visibleRegions: {
              type: "array",
              items: {type: "string", enum: VISUAL_REGIONS},
            },
          },
        },
        {
          description:
            "not_visible means the relevant region is not shown; unknown " +
            "means it is shown but inconclusive; not_applicable means the " +
            "property cannot apply to this item class.",
          type: "object",
          additionalProperties: false,
          required: ["state", "confidence", "visibilityScope", "visibleRegions"],
          properties: {
            state: {
              type: "string",
              enum: ["unknown", "not_visible", "not_applicable"],
            },
            confidence: {type: "number", minimum: 0, maximum: 1},
            visibilityScope: {
              type: "string",
              enum: VISIBILITY_SCOPES,
            },
            visibleRegions: {
              type: "array",
              items: {type: "string", enum: VISUAL_REGIONS},
            },
          },
        },
      ],
    };
  }
  return {
    type: "json_schema",
    json_schema: {
      name: "clothing_vision_v2_shadow",
      strict: true,
      schema: {
        type: "object",
        additionalProperties: false,
        required: ["schemaVersion", "inputAssessment", "subjectAssessment",
          "quality", "observations",
          "identityCandidates", "directInferences"],
        properties: {
          schemaVersion: {type: "integer", const: SCHEMA_VERSION},
          inputAssessment: {type: "string", enum: INPUT_ASSESSMENTS},
          subjectAssessment: {
            type: "object",
            additionalProperties: false,
            required: [
              "subjectCountEstimate", "cardinalityState",
              "primarySubjectPresent", "sameItemConsistency",
              "subjectDomain", "framingClass", "reasonCodes",
              "framingAttestations",
            ],
            properties: {
              subjectCountEstimate: {type: "integer", minimum: 0, maximum: 3},
              cardinalityState: {
                type: "string", enum: SUBJECT_CARDINALITY_STATES,
              },
              primarySubjectPresent: {type: "boolean"},
              sameItemConsistency: {
                type: "string", enum: SAME_ITEM_STATES,
              },
              subjectDomain: {type: "string", enum: SUBJECT_DOMAINS},
              framingClass: {type: "string", enum: FRAMING_CLASSES},
              framingAttestations: {
                type: "object",
                additionalProperties: false,
                required: [
                  "visibleBoundaries", "primarySilhouetteContinuous",
                  "visibleItemExtent", "localDetailOnly", "cropIndicators",
                  "subjectOrientation",
                ],
                properties: {
                  visibleBoundaries: {
                    type: "array",
                    items: {type: "string", enum: BOUNDARIES},
                  },
                  primarySilhouetteContinuous: {type: "boolean"},
                  visibleItemExtent: {type: "string", enum: ITEM_EXTENTS},
                  localDetailOnly: {type: "boolean"},
                  cropIndicators: {
                    type: "array",
                    items: {type: "string", enum: CROP_INDICATORS},
                  },
                  subjectOrientation: {
                    type: "string", enum: SUBJECT_ORIENTATIONS,
                  },
                },
              },
              reasonCodes: {
                type: "array",
                maxItems: 8,
                items: {type: "string"},
              },
            },
          },
          quality: {
            type: "object",
            additionalProperties: false,
            required: ["itemFullyVisible", "occlusion",
              "backgroundInterference", "clarity"],
            properties: {
              itemFullyVisible: {type: "boolean"},
              occlusion: {type: "string", enum: QUALITY_OCCLUSION},
              backgroundInterference: {type: "string", enum: QUALITY_LEVELS},
              clarity: {type: "string", enum: QUALITY_LEVELS},
            },
          },
          observations: {
            type: "object",
            additionalProperties: false,
            required: Object.keys(OBSERVATION_ENUMS),
            properties: observationProperties,
          },
          identityCandidates: {
            type: "array",
            maxItems: MAX_IDENTITY_CANDIDATES,
            items: {
              type: "object",
              additionalProperties: false,
              required: [
                "canonicalType",
                "confidence",
                "definingObservations",
                "supportingObservations",
              ],
              properties: {
                canonicalType: {
                  type: "string",
                  enum: normalizeTaxonomy(canonicalTypes),
                },
                confidence: {type: "number", minimum: 0, maximum: 1},
                definingObservations: {
                  type: "array",
                  maxItems: 6,
                  items: {
                    type: "string",
                    enum: Object.keys(OBSERVATION_ENUMS),
                  },
                },
                supportingObservations: {
                  type: "array",
                  maxItems: 6,
                  items: {
                    type: "string",
                    enum: Object.keys(OBSERVATION_ENUMS),
                  },
                },
              },
            },
          },
          directInferences: {
            type: "object",
            additionalProperties: false,
            properties: {},
          },
        },
      },
    },
  };
}

function createVisionV2ShadowHandler({fetchImpl, getApiKey, logger, authorize}) {
  return async (req, res) => {
    if (req.method !== "POST") return res.status(405).send("POST required.");
    if (!authorize) return res.status(503).json({error: "shadow_auth_not_configured"});
    const authorization = await authorize(req);
    if (!authorization || !authorization.uid) {
      return res.status(401).json({error: "unauthenticated"});
    }
    const imageUrl = String(req.body && req.body.imageUrl || "").trim();
    const canonicalTypes = normalizeTaxonomy(req.body && req.body.canonicalTypes);
    if (!imageUrl) return res.status(400).send("Missing imageUrl.");
    if (!canonicalTypes.length) return res.status(400).send("Missing canonicalTypes.");
    const apiKey = getApiKey();
    if (!apiKey) return res.status(500).send("OPENAI_API_KEY is not configured.");

    const analysisId = crypto.randomUUID();
    const observedAt = new Date().toISOString();
    const prompt = buildVisionV2Prompt(canonicalTypes);
    const requestBody = {
      model: MODEL_VERSION,
      temperature: 0,
      response_format: buildVisionV2ResponseFormat(canonicalTypes),
      messages: [
        {role: "system", content: prompt},
        {role: "user", content: [
          {type: "text", text: "Analyze the visible item using the exact schema."},
          {type: "image_url", image_url: {url: imageUrl}},
        ]},
      ],
    };
    const startedAt = Date.now();
    try {
      const response = await fetchImpl("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {"Content-Type": "application/json", Authorization: `Bearer ${apiKey}`},
        body: JSON.stringify(requestBody),
      });
      if (!response.ok) {
        const body = await response.text();
        logger.error("[VISION_V2_SHADOW][openai]", response.status, body);
        const retryable = [429, 502, 503, 504].includes(response.status);
        return res.status(retryable ? response.status : 422).json({
          error: "vision_upstream_error",
          retryable,
          upstreamStatus: response.status,
        });
      }
      const data = await response.json();
      const text = data && data.choices && data.choices[0] &&
        data.choices[0].message && data.choices[0].message.content;
      const parsed = parseVisionV2Response(text, {
        allowedCanonicalTypes: canonicalTypes,
        analysisId,
        sourceReference: imageUrl,
        observedAt,
        modelVersion: MODEL_VERSION,
      });
      if (!parsed.ok) {
        return res.status(422).json({
          schemaVersion: SCHEMA_VERSION,
          analysisId,
          validationErrors: parsed.errors,
        });
      }
      return res.status(200).json({
        ...parsed.value,
        diagnostics: {
          latencyMs: Date.now() - startedAt,
          modelCallCount: 1,
          inputPayloadBytes: Buffer.byteLength(JSON.stringify(requestBody)),
          outputPayloadBytes: Buffer.byteLength(String(text || "")),
          observationFieldCount: Object.keys(OBSERVATION_ENUMS).length,
        },
      });
    } catch (error) {
      logger.error("[VISION_V2_SHADOW][failure]", error);
      return res.status(500).json({error: "vision_shadow_failure"});
    }
  };
}

async function runVisionV2ShadowBatch(items, analyze, {
  concurrency = 1,
  maxAttempts = 4,
  baseBackoffMs = 1000,
  pacingMs = 750,
  jitterRatio = 0.2,
  random = Math.random,
  sleep = (milliseconds) =>
    new Promise((resolve) => setTimeout(resolve, milliseconds)),
} = {}) {
  const results = new Array(items.length);
  let cursor = 0;
  async function worker() {
    while (cursor < items.length) {
      const index = cursor++;
      const item = items[index];
      const startedAt = Date.now();
      const retries = [];
      let response;
      let error;
      for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
        try {
          response = await analyze(item, attempt);
          error = null;
          break;
        } catch (caught) {
          error = caught;
          const status = Number(caught && caught.status);
          const retryable = status === 429 || status === 502 ||
            status === 503 || status === 504;
          const retryAfterMs = Number(caught && caught.retryAfterMs);
          const baseDelay = Number.isFinite(retryAfterMs) && retryAfterMs > 0 ?
            retryAfterMs : baseBackoffMs * (2 ** (attempt - 1));
          const jitter = baseDelay * jitterRatio * random();
          const delayMs = Math.round(baseDelay + jitter);
          retries.push({
            attempt,
            status,
            retryable,
            reason: status === 429 ? "rate_limited" : "transient_upstream",
            delayMs: retryable && attempt < maxAttempts ? delayMs : 0,
          });
          if (!retryable || attempt >= maxAttempts) break;
          await sleep(delayMs);
        }
      }
      results[index] = {
        item,
        ok: response !== undefined,
        response: response === undefined ? null : response,
        error: error ? String(error.message || error) : null,
        attempts: retries.length + (response === undefined ? 0 : 1),
        retries,
        latencyMs: Date.now() - startedAt,
      };
      if (pacingMs > 0 && cursor < items.length) await sleep(pacingMs);
    }
  }
  const workerCount = Math.max(1, Math.min(concurrency, items.length));
  await Promise.all(Array.from({length: workerCount}, () => worker()));
  return results;
}

module.exports = {
  MAX_IDENTITY_CANDIDATES,
  MODEL_VERSION,
  OBSERVATION_ENUMS,
  PROPERTY_CONFIDENCE_RUBRIC,
  SCHEMA_VERSION,
  buildVisionV2Prompt,
  buildVisionV2ResponseFormat,
  createVisionV2ShadowHandler,
  normalizeTaxonomy,
  parseVisionV2Response,
  runVisionV2ShadowBatch,
};
