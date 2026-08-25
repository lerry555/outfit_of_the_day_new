"use strict";

/** Fixture-free production-safe provider composition. Not wired to callables. */

const {decodeTrustedVisionQualificationInput, stableCanonicalSerialize} =
  require("./trusted_vision_qualification_input");
const {attestFraming} = require("./vision_framing_attestor");
const {qualifyApplicability} = require("./vision_property_applicability_qualifier");
const {qualifyVisibility} = require("./vision_visibility_trust_qualifier");
const {qualifyNegativeClaims} = require("./vision_negative_claim_corroborator");
const {qualifyAbsenceBundles} = require("./observation_absence_qualifier");
const {provideObservationEvidence, PROVIDER_ID: OBSERVATION_PROVIDER_ID,
  PROVIDER_VERSION: OBSERVATION_PROVIDER_VERSION} =
  require("./vision_observation_evidence_provider");
const {inferCapabilities, PROVIDER_VERSION: CAPABILITY_PROVIDER_VERSION,
  QUALIFICATION_INPUT_CONTRACT_VERSION} =
  require("./wardrobe_capability_inference_provider");
const {prepareVisionIdentityQualificationInput, applyFramingToSubject,
  assessMultiPhotoConsistency, permitsCanonical: permitsCanonicalSubject} =
  require("./prepare_vision_identity_qualification_input");
const {qualifyVisionIdentity} = require("./vision_identity_qualifier");
const {prepareVisionFamilyIdentityInput, permitsFamily} =
  require("./prepare_vision_family_identity_input");
const {resolveVisionFamilyIdentity} = require("./vision_family_identity_resolver");
const {prepareVisionKnowledgeBasePriorInput} =
  require("./prepare_vision_knowledge_base_prior_input");
const {provideWardrobeKnowledgeBasePriors} =
  require("./wardrobe_knowledge_base_prior_provider");
const {prepareWardrobeProfileResolverInput} =
  require("./prepare_wardrobe_profile_resolver_input");
const {resolveWardrobeProfile} = require("./wardrobe_profile_resolver");
const {prepareQualifiedVisionPersistenceMapperInput, PRODUCTION_CONTEXT_MODE,
  PERSISTENCE_SCHEMA_VERSION, PERSISTENCE_EVIDENCE_VERSION,
  RESOLVER_COMPATIBILITY_VERSION} =
  require("./prepare_qualified_vision_persistence_mapper_input");
const {mapQualifiedVisionPersistence} = require("./qualified_vision_persistence_mapper");
const {loadCanonicalResolverStructuredTaxonomyArtifact} =
  require("./canonical_resolver_structured_taxonomy_loader");
const {loadVisionCanonicalFamilyRegistryArtifact} =
  require("./vision_canonical_family_registry_loader");
const {loadClothingKnowledgeBasePriorArtifact} =
  require("./clothing_knowledge_base_prior_loader");

const CONTRACT_ID = "LiveParserBackendQualificationOrchestrator/v1";
const CONTRACT_VERSION = 1;
const ORCHESTRATOR_VERSION = "live-parser-backend-qualification-orchestrator-v1";
const OUTPUT_CONTRACT = "LiveParserBackendQualificationResult/v1";
const REGION_PROPERTIES = Object.freeze(["coverage", "hasHood", "frontClosure",
  "visibleBulk", "necklineShape", "visiblePocketStructure",
  "visibleStretchCue", "footwearConstruction", "footwearFastening",
  "soleProfile", "visibleTread", "footwearUpperHeight"]);

function runLiveParserBackendQualification(raw, dependencies = {}) {
  let stage = "trusted_input_decode";
  try {
    const trusted = decodeTrustedVisionQualificationInput(
      raw, requireObject(dependencies.expectedRuntime,
        "expected_runtime_required"));
    const responses = trusted.parserResult.views.map((view) => view.response);
    assertAnalysisAuthority(trusted, responses);
    const primary = responses[trusted.analysisIdentity.primaryViewIndex];

    stage = "artifact_integrity";
    const structuredTaxonomy = (dependencies.loadStructuredTaxonomy ||
      loadCanonicalResolverStructuredTaxonomyArtifact)({
      expectedContentSha256:
        trusted.artifactIntegrity.structuredTaxonomyArtifactSha256});
    const familyRegistry = (dependencies.loadFamilyRegistry ||
      loadVisionCanonicalFamilyRegistryArtifact)({expectedContentSha256:
      trusted.artifactIntegrity.canonicalFamilyArtifactSha256});
    const knowledgeBaseArtifact = (dependencies.loadKnowledgeBaseArtifact ||
      loadClothingKnowledgeBasePriorArtifact)({expectedContentSha256:
      trusted.artifactIntegrity.knowledgeBaseArtifactSha256});
    const allowedCanonicalTypes = [...new Set([
      ...structuredTaxonomy.categorySubCanonical.values(),
      ...familyRegistry.canonicalToFamily.keys(),
      ...knowledgeBaseArtifact.items.map((item) => item.canonicalType),
    ])].sort(compareUtf16);

    stage = "framing";
    const framing = responses.map((response) => attestFraming({
      inputAssessment: response.inputAssessment,
      subject: response.subjectAssessment,
      quality: response.quality,
      attestations: response.subjectAssessment.framingAttestations}));
    const systemSubjects = framing.map((report, index) => {
      const subject = applyFramingToSubject(
        report, responses[index].subjectAssessment);
      return deepFreeze({...subject,
        permitsCanonical: permitsCanonicalSubject(subject),
        permitsFamily: permitsFamily(subject)});
    });
    const multiPhotoAssessment = mapperMultiPhoto(assessMultiPhotoConsistency(
      systemSubjects, responses.length === 1 ? {contractVersion: 1,
        physicalIdentityClaim: "undeclared", source: "unknown",
        reasonCodes: ["default_undeclared"]} :
        trusted.multiViewSubjectBinding));
    const complementaryRegions = collectComplementaryRegions(responses);
    const conflictingPositiveProperties = collectPositiveConflicts(responses);

    stage = "applicability";
    const rawBundles = responses.map(toObservationBundle);
    const applicability = rawBundles.map((bundle, index) =>
      qualifyApplicability({bundle, subject: systemSubjects[index]}));

    stage = "visibility";
    const visibility = applicability.map((report, index) => qualifyVisibility({
      bundle: report.qualifiedBundle,
      inputAssessment: responses[index].inputAssessment,
      viewCount: responses.length, complementaryRegions}));

    stage = "negative_claim";
    const negativeClaims = visibility.map((report, index) =>
      qualifyNegativeClaims({bundle: report.qualifiedBundle,
        subject: systemSubjects[index], framing: framing[index],
        viewCount: responses.length,
        sameItemViews: multiPhotoAssessment.sameItemViews,
        complementaryRegions, conflictingPositiveProperties}));

    stage = "absence";
    const absenceQualification = qualifyAbsenceBundles({bundles:
      negativeClaims.map((report) => report.qualifiedBundle)});
    const qualifiedObservationBundles = [absenceQualification.qualifiedBundle];

    stage = "observation_evidence";
    const observationProviderOutput = qualifiedObservationBundles
      .flatMap((bundle) => provideObservationEvidence(bundle));
    const observationEvidence = structuredClone(observationProviderOutput)
      .sort((left, right) => compareUtf16(left.id, right.id));

    stage = "capability";
    const capabilityProviderOutput = inferCapabilities({
      oracleContractVersion: 1,
      upstreamProviderId: OBSERVATION_PROVIDER_ID,
      upstreamProviderVersion: OBSERVATION_PROVIDER_VERSION,
      qualificationInputContractVersion: QUALIFICATION_INPUT_CONTRACT_VERSION,
      providerVersion: CAPABILITY_PROVIDER_VERSION,
      analysisId: trusted.analysisIdentity.rootAnalysisId,
      observedAt: primary.observedAt,
      sourceReference: primary.sourceReference,
      observationEvidence});
    const capabilityEvidence = projectCapabilityWire(capabilityProviderOutput);

    stage = "identity_input_prepare";
    const identityInput = prepareVisionIdentityQualificationInput({responses,
      multiViewSubjectBinding: trusted.multiViewSubjectBinding,
      observationEvidence, allowedCanonicalTypes,
      taxonomyRegistrySha256: structuredTaxonomy.structuredTaxonomySourceSha256,
      expectedTaxonomyRegistrySha256:
        structuredTaxonomy.structuredTaxonomySourceSha256});
    const canonicalConsistency = identityInput.consistency;

    stage = "identity_qualification";
    const identityQualification = qualifyVisionIdentity({
      identityEvidence: identityInput.identityEvidence,
      consistency: identityInput.consistency,
      declaredByEvidenceId: identityInput.declaredByEvidenceId,
      inputIsValid: identityInput.inputIsValid});

    stage = "family_input_prepare";
    const familyInput = prepareVisionFamilyIdentityInput({responses,
      multiViewSubjectBinding: trusted.multiViewSubjectBinding,
      identityQualificationReport: {selectedCanonicalType:
        identityQualification.report.selectedCanonicalType ?? null,
      state: identityQualification.report.state}, allowedCanonicalTypes,
      familyTaxonomySha256: familyRegistry.familyTaxonomySha256,
      expectedFamilyTaxonomySha256: familyRegistry.familyTaxonomySha256});

    stage = "family_resolver";
    const familyIdentity = resolveVisionFamilyIdentity(familyInput);

    stage = "kb_input_prepare";
    const observationProvenance = provenance(primary);
    const kbInput = prepareVisionKnowledgeBasePriorInput({
      documentMode: "vision_empty", observationEvidence,
      observationProvenance,
      qualifiedIdentityEvidence:
        identityQualification.qualifiedIdentityEvidence,
      capabilityEvidence});

    stage = "kb_provider";
    const knowledgeBaseEvidence = (dependencies.provideKnowledgeBasePriors ||
      provideWardrobeKnowledgeBasePriors)(kbInput, {
      kbArtifact: knowledgeBaseArtifact,
      expectedArtifactContentSha256:
        trusted.artifactIntegrity.knowledgeBaseArtifactSha256});

    stage = "resolver_input_prepare";
    const resolverInput = prepareWardrobeProfileResolverInput({
      itemId: trusted.revisionContext.itemId,
      resolverCompatibilityVersion: RESOLVER_COMPATIBILITY_VERSION,
      observationEvidence, observationProvenance,
      qualifiedIdentityEvidence:
        identityQualification.qualifiedIdentityEvidence,
      capabilityEvidence, knowledgeBaseEvidence,
      familyIdentityReport: {present: true, ignoredByResolver: true}});

    stage = "resolver";
    const resolvedWardrobeProfile = (dependencies.resolveProfile ||
      resolveWardrobeProfile)(resolverInput);

    stage = "mapper_input_prepare";
    const mapperInput = prepareQualifiedVisionPersistenceMapperInput({
      contextMode: PRODUCTION_CONTEXT_MODE,
      analysisId: trusted.analysisIdentity.rootAnalysisId,
      modelVersion: primary.modelVersion, schemaVersion: primary.schemaVersion,
      inputAssessment: primary.inputAssessment,
      observationEvidence, observationProvenance,
      qualifiedIdentityEvidence:
        identityQualification.qualifiedIdentityEvidence,
      identityQualification: identityQualification.report,
      familyIdentity, capabilityEvidence, multiPhotoAssessment,
      persistenceSchemaVersion: PERSISTENCE_SCHEMA_VERSION,
      persistenceEvidenceVersion: PERSISTENCE_EVIDENCE_VERSION,
      resolverCompatibilityVersion: RESOLVER_COMPATIBILITY_VERSION,
      trustedMappingContext: buildTrustedMappingContext(trusted, primary,
        dependencies.persistenceRevision)});

    stage = "mapper";
    const mapperResult = (dependencies.mapPersistence ||
      mapQualifiedVisionPersistence)({...mapperInput,
      contextMode: PRODUCTION_CONTEXT_MODE, trustedRevisionAuthority: true});

    const result = {contractVersion: CONTRACT_VERSION,
      contractId: OUTPUT_CONTRACT, orchestratorId: CONTRACT_ID,
      orchestratorVersion: ORCHESTRATOR_VERSION, status: "qualified",
      rootAnalysisId: trusted.analysisIdentity.rootAnalysisId,
      analysisKind: trusted.analysisIdentity.analysisKind,
      perViewQualificationReports: responses.map((response, index) => ({index,
        viewId: trusted.parserResult.views[index].viewId,
        analysisId: response.analysisId, framing: framing[index],
        applicability: applicability[index], visibility: visibility[index],
        negativeClaims: negativeClaims[index]})),
      qualifiedObservationBundles, negativeClaimReports: negativeClaims,
      absenceQualificationReport: absenceQualification,
      observationProviderOutput, observationEvidence,
      capabilityProviderOutput, capabilityEvidence,
      canonicalConsistency,
      identityInput, identityQualificationReport: identityQualification.report,
      qualifiedIdentityEvidence:
        identityQualification.qualifiedIdentityEvidence,
      familyInput, familyIdentityReport: familyIdentity,
      knowledgeBaseInput: kbInput, knowledgeBaseEvidence,
      resolverInput, resolvedWardrobeProfile, mapperInput, mapperResult,
      diagnostics: {stage: "complete", reasonCodes: []}};
    result.canonicalJson = stableCanonicalSerialize(result);
    return deepFreeze(result);
  } catch (error) {
    return failure(stage, error);
  }
}

function toObservationBundle(response) {
  return deepFreeze({analysisId: response.analysisId,
    modelVersion: response.modelVersion,
    sourceReference: response.sourceReference, observedAt: response.observedAt,
    quality: structuredClone(response.quality),
    ...Object.fromEntries(Object.entries(response.observations).map(
      ([property, value]) => [property, projectObservation(value)]))});
}

function projectObservation(value) {
  if (value.state === "observed") return structuredClone(value);
  if (value.state === "not_applicable") {
    return {state: "not_applicable", confidence: 1};
  }
  if (value.state === "not_visible") {
    return {state: "not_visible", confidence: 0,
      visibilityScope: "not_visible"};
  }
  return {state: "unknown", confidence: 0};
}

function collectComplementaryRegions(responses) {
  const result = {};
  for (const property of REGION_PROPERTIES) {
    const regions = new Set();
    let present = false;
    for (const response of responses) {
      const observation = response.observations[property];
      if (observation == null) continue;
      present = true;
      for (const region of observation.visibleRegions || []) regions.add(region);
    }
    if (present) result[property] = [...regions].sort(compareUtf16);
  }
  return deepFreeze(result);
}

function collectPositiveConflicts(responses) {
  const policies = {frontClosure: (value) => value === "none",
    visiblePocketStructure: (value) => value === "none",
    hasHood: (value) => value === false,
    visibleStretchCue: (value) => value === false};
  return deepFreeze(Object.keys(policies).filter((property) => {
    const values = responses.map((response) => response.observations[property])
      .filter((item) => item?.state === "observed")
      .map((item) => item.value);
    return values.some(policies[property]) &&
      values.some((value) => !policies[property](value));
  }).sort(compareUtf16));
}

function mapperMultiPhoto(value) {
  const {binding, ...rest} = value;
  return deepFreeze({...rest, multiViewSubjectBinding: binding});
}

function provenance(primary) {
  return deepFreeze({observedAt: primary.observedAt,
    modelVersion: primary.modelVersion,
    sourceReference: primary.sourceReference});
}

function buildTrustedMappingContext(trusted, primary, persistenceRevision) {
  const revision = trusted.revisionContext;
  const timestamp = revision.sourceUpdatedAt;
  const mappedRevision = persistenceRevision == null ?
    (revision.expectedProfileRevision ?? 0) : persistenceRevision;
  if (!Number.isInteger(mappedRevision) || mappedRevision < 0) {
    throw new Error("persistence_revision_invalid");
  }
  return deepFreeze({analysisId: trusted.analysisIdentity.rootAnalysisId,
    analysisKind: trusted.analysisIdentity.analysisKind,
    completedAt: timestamp, createdAt: timestamp,
    generationId: revision.generationId,
    ...(revision.sourceImageSha256 ?
      {imageHash: revision.sourceImageSha256} : {}),
    imageRevision: revision.imageRevision,
    modelIdentifier: trusted.parserAttestation.modelIdentifier,
    pipelineVersion: trusted.parserAttestation.pipelineVersion,
    promptVersion: trusted.parserAttestation.promptVersion,
    qualificationVersion: trusted.parserAttestation.qualificationVersion,
    revision: mappedRevision,
    storagePath: revision.sourceStoragePath, updatedAt: timestamp,
    uploadGeneration: revision.uploadGeneration,
    visionSchemaVersion: primary.schemaVersion,
    wardrobeItemRevision: revision.wardrobeItemRevision});
}

function projectCapabilityWire(items) {
  return items.map((item) => {
    const projected = {active: item.active !== false,
      confidence: item.confidence, createdAt: item.createdAt, id: item.id,
      method: item.method, modelVersion: item.modelVersion,
      nature: item.nature, property: item.property, source: item.source,
      value: item.value, verified: item.verified === true};
    if (item.sourceReference) projected.sourceReference = item.sourceReference;
    if (item.valueState && item.valueState !== "known") {
      projected.valueState = item.valueState;
    }
    return projected;
  });
}

function assertAnalysisAuthority(trusted, responses) {
  const identity = trusted.analysisIdentity;
  if (responses[identity.primaryViewIndex].analysisId !== identity.rootAnalysisId) {
    throw coded("analysis_identity_mismatch");
  }
  responses.forEach((response, index) => {
    if (response.analysisId !== identity.perViewAnalysisIds[index].analysisId) {
      throw coded("analysis_identity_mismatch");
    }
  });
  if (!new Set(["initial_analysis", "reanalysis"]).has(identity.analysisKind)) {
    throw coded("analysis_kind_mismatch");
  }
}

function failure(stage, error) {
  const reason = error?.code || error?.message || "unknown_failure";
  return deepFreeze({contractVersion: CONTRACT_VERSION,
    contractId: OUTPUT_CONTRACT, orchestratorId: CONTRACT_ID,
    orchestratorVersion: ORCHESTRATOR_VERSION,
    status: failureStatus(stage, String(reason)), rootAnalysisId: null,
    analysisKind: null,
    diagnostics: {stage, reasonCodes: [sanitize(reason)]}});
}

function failureStatus(stage, reason) {
  if (stage === "trusted_input_decode") {
    if (/unknown_field/.test(reason)) {
      if (/analysisKind/.test(reason)) return "analysis_kind_mismatch";
      return "invalid_trusted_input";
    }
    if (/analysis_kind|analysisKind/.test(reason)) return "analysis_kind_mismatch";
    if (/analysis/.test(reason)) return "analysis_identity_mismatch";
    if (/view_order/.test(reason)) return "view_ordering_mismatch";
    if (/artifact/.test(reason)) return "artifact_integrity_mismatch";
    if (/attestation|provenance|model|prompt|pipeline|qualification/.test(reason)) {
      return "parser_attestation_mismatch";
    }
    return "invalid_trusted_input";
  }
  if (/input_assessment_invalid/.test(reason)) return "invalid_trusted_input";
  if (stage === "artifact_integrity") return "artifact_integrity_mismatch";
  if (stage === "resolver") return "resolver_failed";
  if (stage === "mapper") return "mapper_failed";
  if (stage.endsWith("prepare")) return "provider_input_build_failed";
  if (/mismatch/.test(reason)) return "internal_contract_mismatch";
  return "provider_output_invalid";
}

function requireObject(value, reason) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw coded(reason);
  }
  return value;
}
function sanitize(value) { return String(value)
  .replace(/[^a-zA-Z0-9_:.-]/g, "_").slice(0, 160); }
function coded(code) { const error = new Error(code); error.code = code;
  return error; }
function compareUtf16(left, right) { return left < right ? -1 : left > right ? 1 : 0; }
function deepFreeze(value) { if (value && typeof value === "object" &&
    !Object.isFrozen(value)) { Object.values(value).forEach(deepFreeze);
  Object.freeze(value); } return value; }

module.exports = {CONTRACT_ID, CONTRACT_VERSION, ORCHESTRATOR_VERSION,
  OUTPUT_CONTRACT, buildTrustedMappingContext, collectComplementaryRegions,
  collectPositiveConflicts, runLiveParserBackendQualification,
  toObservationBundle};
