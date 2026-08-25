"use strict";

/**
 * Revision lifecycle assignment contract (design foundation).
 *
 * Documents who may bump which revision counters. Does not mutate Firestore
 * or change production write paths in this phase.
 */

const {
  EDIT_CLASSES,
  EDIT_INVALIDATION,
} = require("./wardrobe_qualification_revision_contract");

const LIFECYCLE_ID = "WardrobeRevisionLifecycleAssignment";
const LIFECYCLE_VERSION = "wardrobe-revision-lifecycle-assignment-v1";

/**
 * Production reality notes (Phase 5.3B-7A audit):
 * - No dedicated image-replacement edit flow.
 * - Product-link often has no storagePath.
 * - Delete does not clear Storage path maps.
 */
const LIFECYCLE_HOOKS = Object.freeze({
  newUserPhotoItem: Object.freeze({
    id: "A_new_user_photo_item",
    actor: "backend_after_trusted_upload",
    requiresBackendMutation: true,
    mutationKind: "initialize_user_photo_authority",
    imageRevision: "assign_1_on_create",
    wardrobeItemRevision: "assign_1_on_create",
    notes: "Client may upload Storage object + legacy fields; backend assigns qualificationAuthority via offline mutation service.",
  }),
  newProductLinkItem: Object.freeze({
    id: "B_new_product_link_item",
    actor: "backend_fail_closed_without_original",
    requiresBackendMutation: true,
    mutationKind: null,
    imageRevision: "do_not_initialize_without_wardrobe_source_path",
    wardrobeItemRevision: "do_not_initialize_without_wardrobe_source_path",
    notes: "Product-only provenance cannot invent uploadGeneration. Future product-source authority contract required.",
  }),
  manualClassificationEdit: Object.freeze({
    id: "C_manual_classification_edit",
    actor: "backend_mutation_or_rules_denied_client_bump",
    requiresBackendMutation: true,
    mutationKind: "apply_classification_metadata_edit",
    editClass: EDIT_CLASSES.classificationMetadata,
    imageRevision: "unchanged",
    wardrobeItemRevision: "increment",
    notes: "Client may propose UX metadata fields; wardrobeItemRevision bump must be backend-owned.",
  }),
  userCorrection: Object.freeze({
    id: "D_user_correction",
    actor: "backend_correction_endpoint",
    requiresBackendMutation: true,
    mutationKind: "apply_user_correction",
    editClass: EDIT_CLASSES.userCorrection,
    imageRevision: "unchanged",
    wardrobeItemRevision: "increment",
    notes: "Corrections live inside wardrobeProfile.userCorrections (backend-owned envelope). No client nested mutation.",
  }),
  sameImageReanalysis: Object.freeze({
    id: "E_same_image_reanalysis",
    actor: "backend_analysis_pipeline",
    requiresBackendMutation: true,
    mutationKind: "request_same_image_reanalysis",
    editClass: EDIT_CLASSES.reanalysisSameImage,
    imageRevision: "unchanged",
    wardrobeItemRevision: "unchanged",
    profileRevision: "increment_via_repository",
  }),
  imageReplacement: Object.freeze({
    id: "F_image_replacement",
    actor: "not_implemented_in_production",
    requiresBackendMutation: true,
    mutationKind: null,
    editClass: EDIT_CLASSES.imageChanging,
    imageRevision: "increment_when_flow_exists",
    wardrobeItemRevision: "increment_when_flow_exists",
    notes: "No dedicated production edit re-upload flow today. Do not invent client lifecycle.",
  }),
  derivativeCompletion: Object.freeze({
    id: "G_derivative_completion",
    actor: "backend_triggers",
    requiresBackendMutation: true,
    mutationKind: "record_derivative_completion",
    editClass: EDIT_CLASSES.derivativeCompletion,
    imageRevision: "unchanged",
    wardrobeItemRevision: "unchanged",
    notes: "clean/product paths are not source authority. Offline mutation records derivative fields only.",
  }),
  deleteItem: Object.freeze({
    id: "H_delete",
    actor: "client_owner_delete_whole_document",
    requiresBackendMutation: false,
    mutationKind: null,
    imageRevision: "document_removed",
    wardrobeItemRevision: "document_removed",
    notes: "Whole-doc delete may remain client-allowed; Storage path maps are not cleaned today.",
  }),
});

function lifecyclePlanFor(hookId) {
  const hook = Object.values(LIFECYCLE_HOOKS).find((item) => item.id === hookId);
  if (!hook) throw new Error(`lifecycle_hook_unknown:${hookId}`);
  const editPolicy = hook.editClass ? EDIT_INVALIDATION[hook.editClass] : null;
  return Object.freeze({...hook, editPolicy});
}

module.exports = {
  LIFECYCLE_HOOKS,
  LIFECYCLE_ID,
  LIFECYCLE_VERSION,
  lifecyclePlanFor,
};
