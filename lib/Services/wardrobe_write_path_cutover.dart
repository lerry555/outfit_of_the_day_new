/// M11.1 Phase 10A — Client wardrobe write-path cutover coordinator.
///
/// After legacy UX Firestore create/update (Rules-allowed fields only),
/// invokes backend lifecycle/authority callables for revision ownership.
/// Soft-defers while handlers remain unexported so UX never breaks.
library;

import 'package:flutter/foundation.dart';

import 'wardrobe_qualification_authority_client.dart';
import 'wardrobe_revision_lifecycle_client.dart';

class WardrobeWritePathCutoverResult {
  const WardrobeWritePathCutoverResult({
    required this.lifecycle,
    this.authority,
  });

  final WardrobeLifecycleCallResult? lifecycle;
  final WardrobeLifecycleCallResult? authority;

  bool get preservedUx => true;
}

class WardrobeWritePathCutover {
  WardrobeWritePathCutover({
    WardrobeRevisionLifecycleClient? lifecycleClient,
    WardrobeQualificationAuthorityClient? authorityClient,
  })  : _lifecycle = lifecycleClient ?? WardrobeRevisionLifecycleClient.instance,
        _authority =
            authorityClient ?? WardrobeQualificationAuthorityClient.instance;

  final WardrobeRevisionLifecycleClient _lifecycle;
  final WardrobeQualificationAuthorityClient _authority;

  static WardrobeWritePathCutover instance = WardrobeWritePathCutover();

  /// Post-save hook for [AddClothingScreen] UX writes.
  ///
  /// - Create with `storagePath` (user-photo): `initialize_user_photo_authority`
  ///   then soft `analyze_current_source`.
  /// - Edit: `apply_classification_metadata_edit` with allow-listed patch.
  /// - Product-link without wardrobe storage: no initialize (backend fail-closed).
  Future<WardrobeWritePathCutoverResult> afterUxSave({
    required bool isEditing,
    required String itemId,
    required Map<String, dynamic> savedFields,
    String? storagePath,
    bool fromProductLink = false,
  }) async {
    assert(itemId.isNotEmpty, 'itemId required');

    if (isEditing) {
      final patch = buildClassificationLifecyclePatch(savedFields);
      if (patch.isEmpty) {
        debugPrint(
          '[WARDROBE_CUTOVER] edit skipped empty_classification_patch '
          'itemId=$itemId',
        );
        return const WardrobeWritePathCutoverResult(lifecycle: null);
      }
      final lifecycle = await _lifecycle.callOperation(
        operationKind: kLifecycleOpClassificationEdit,
        itemId: itemId,
        patch: patch,
        idempotencyKey: 'classification:$itemId:${patch.hashCode}',
      );
      return WardrobeWritePathCutoverResult(lifecycle: lifecycle);
    }

    final path = (storagePath ?? savedFields['storagePath']?.toString() ?? '')
        .trim();
    final hasWardrobeStorage =
        path.startsWith('wardrobe/') && path.split('/').length >= 3;

    if (!hasWardrobeStorage) {
      debugPrint(
        '[WARDROBE_CUTOVER] create skipped no_user_photo_storage '
        'itemId=$itemId productLink=$fromProductLink',
      );
      return const WardrobeWritePathCutoverResult(lifecycle: null);
    }

    final lifecycle = await _lifecycle.callOperation(
      operationKind: kLifecycleOpInitializeUserPhoto,
      itemId: itemId,
      idempotencyKey: 'init:$itemId:$path',
    );

    WardrobeLifecycleCallResult? authority;
    if (lifecycle.ok) {
      authority = await _authority.analyzeCurrentSource(itemId: itemId);
    }

    return WardrobeWritePathCutoverResult(
      lifecycle: lifecycle,
      authority: authority,
    );
  }

  /// Same-image reanalysis path (debug/apply tooling).
  Future<WardrobeLifecycleCallResult> afterSameImageReanalysis({
    required String itemId,
  }) {
    return _lifecycle.callOperation(
      operationKind: kLifecycleOpSameImageReanalysis,
      itemId: itemId,
      idempotencyKey: 'reanalyze:$itemId',
    );
  }
}
