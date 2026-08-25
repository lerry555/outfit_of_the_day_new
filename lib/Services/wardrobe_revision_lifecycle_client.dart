/// M11.1 Phase 10A — Wardrobe revision lifecycle callable client.
///
/// Handlers are not yet exported from `functions/index.js`. Production calls
/// soft-fail (`not-found` / `unimplemented`) so UX Firestore writes remain
/// authoritative until export/deploy. Tests inject a fake transport.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'firebase_app_check_bootstrap.dart';

typedef WardrobeLifecycleCallableTransport =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

const String kWardrobeRevisionLifecycleCallableName =
    'wardrobeRevisionLifecycle';
const String kWardrobeLifecycleCallableRegion = 'us-east1';

const String kLifecycleOpInitializeUserPhoto =
    'initialize_user_photo_authority';
const String kLifecycleOpClassificationEdit =
    'apply_classification_metadata_edit';
const String kLifecycleOpUserCorrection = 'apply_user_correction';
const String kLifecycleOpDerivativeCompletion = 'record_derivative_completion';
const String kLifecycleOpSameImageReanalysis = 'request_same_image_reanalysis';

/// Allow-list mirrored from `wardrobe_revision_lifecycle_mutation_service.js`.
const Set<String> kClassificationLifecycleAllowList = {
  'name',
  'brand',
  'canonicalType',
  'canonicalFamily',
  'bodySlots',
  'layerPosition',
  'outfitFunctions',
  'uiProjection',
  'accessoryGroup',
  'multiplicity',
  'colorProfile',
  'styles',
  'patterns',
  'seasons',
  'occasionFit',
  'warmth',
  'formality',
  'attributes',
  'setMembership',
  'fieldSources',
  'fieldConfidence',
  'userOverrideFields',
  'analyzerProvenance',
  'ontologyVersion',
  'taxonomyVersion',
  'kbVersion',
  'logo_prominence',
  'fit',
  'occasions',
  'activities',
  'terrain',
  'visual_description',
  'visual_identity',
  'identity_confidence',
  'confidence',
};

enum WardrobeLifecycleCallStatus { applied, deferredUntilExport, failed }

class WardrobeLifecycleCallResult {
  const WardrobeLifecycleCallResult({
    required this.status,
    required this.operationKind,
    this.reasonCode,
    this.raw,
  });

  final WardrobeLifecycleCallStatus status;
  final String operationKind;
  final String? reasonCode;
  final Map<String, dynamic>? raw;

  bool get ok =>
      status == WardrobeLifecycleCallStatus.applied ||
      status == WardrobeLifecycleCallStatus.deferredUntilExport;
}

class WardrobeRevisionLifecycleClient {
  WardrobeRevisionLifecycleClient({
    WardrobeLifecycleCallableTransport? transport,
    FirebaseAppCheckBootstrap? appCheckBootstrap,
    this.functionName = kWardrobeRevisionLifecycleCallableName,
    this.region = kWardrobeLifecycleCallableRegion,
  }) : _transport = transport,
       _appCheck = appCheckBootstrap ?? FirebaseAppCheckBootstrap.instance;

  final WardrobeLifecycleCallableTransport? _transport;
  final FirebaseAppCheckBootstrap _appCheck;
  final String functionName;
  final String region;

  static WardrobeRevisionLifecycleClient instance =
      WardrobeRevisionLifecycleClient();

  Future<WardrobeLifecycleCallResult> callOperation({
    required String operationKind,
    required String itemId,
    Map<String, dynamic>? patch,
    Map<String, dynamic>? correction,
    String? derivativeKind,
    String? idempotencyKey,
  }) async {
    final data = <String, dynamic>{
      'contractVersion': 1,
      'operationKind': operationKind,
      'itemId': itemId,
      if (idempotencyKey != null && idempotencyKey.isNotEmpty)
        'idempotencyKey': idempotencyKey,
      if (patch != null && patch.isNotEmpty) 'patch': patch,
      if (correction != null && correction.isNotEmpty) 'correction': correction,
      if (derivativeKind != null && derivativeKind.isNotEmpty)
        'derivativeKind': derivativeKind,
    };

    try {
      final gate = await _ensureAppCheckReady(operationKind);
      if (gate != null) return gate;

      final response = await _invoke(data);
      final endpoint = _unwrapEndpointResult(response);
      final status = (endpoint['status'] ?? response['status'] ?? '')
          .toString();
      final reason = (endpoint['reasonCode'] ?? response['reasonCode'])
          ?.toString();
      if (response['ok'] == false) {
        return WardrobeLifecycleCallResult(
          status: WardrobeLifecycleCallStatus.failed,
          operationKind: operationKind,
          reasonCode: reason ?? status,
          raw: response,
        );
      }
      return WardrobeLifecycleCallResult(
        status: WardrobeLifecycleCallStatus.applied,
        operationKind: operationKind,
        reasonCode: reason ?? status,
        raw: response,
      );
    } on FirebaseFunctionsException catch (e) {
      if (_isDeferredUntilExport(e.code)) {
        debugPrint(
          '[WARDROBE_LIFECYCLE] deferred_until_export '
          'op=$operationKind code=${e.code} message=${e.message}',
        );
        return WardrobeLifecycleCallResult(
          status: WardrobeLifecycleCallStatus.deferredUntilExport,
          operationKind: operationKind,
          reasonCode: e.code,
        );
      }
      debugPrint(
        '[WARDROBE_LIFECYCLE] failed op=$operationKind '
        'code=${e.code} message=${e.message}',
      );
      return WardrobeLifecycleCallResult(
        status: WardrobeLifecycleCallStatus.failed,
        operationKind: operationKind,
        reasonCode: e.code,
      );
    } catch (e) {
      debugPrint('[WARDROBE_LIFECYCLE] failed op=$operationKind error=$e');
      return WardrobeLifecycleCallResult(
        status: WardrobeLifecycleCallStatus.failed,
        operationKind: operationKind,
        reasonCode: 'client_error',
      );
    }
  }

  Future<WardrobeLifecycleCallResult?> _ensureAppCheckReady(
    String operationKind,
  ) async {
    // Injected transport is for offline/unit tests — skip live App Check gate.
    if (_transport != null) return null;
    final init = await _appCheck.ensureInitialized();
    if (init.isReady) return null;
    debugPrint(
      '[WARDROBE_LIFECYCLE] deferred_app_check_not_ready '
      'op=$operationKind reason=${init.reasonCode}',
    );
    return WardrobeLifecycleCallResult(
      status: WardrobeLifecycleCallStatus.deferredUntilExport,
      operationKind: operationKind,
      reasonCode: init.reasonCode ?? 'app_check_not_ready',
    );
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> data) async {
    final transport = _transport;
    if (transport != null) {
      return transport(functionName, data);
    }
    final callable = FirebaseFunctions.instanceFor(
      region: region,
    ).httpsCallable(functionName);
    final result = await callable.call(data);
    final raw = result.data;
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{'ok': false, 'reasonCode': 'invalid_response'};
  }

  static Map<String, dynamic> _unwrapEndpointResult(Map<String, dynamic> raw) {
    final nested = raw['result'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
    return raw;
  }

  static bool _isDeferredUntilExport(String code) {
    switch (code) {
      case 'not-found':
      case 'unimplemented':
      case 'unavailable':
      case 'failed-precondition':
      case 'unauthenticated':
      case 'permission-denied':
        return true;
      default:
        return false;
    }
  }
}

/// Builds a JSON-safe classification patch from a client UX save map.
Map<String, dynamic> buildClassificationLifecyclePatch(
  Map<String, dynamic> savedFields,
) {
  final out = <String, dynamic>{};
  for (final key in kClassificationLifecycleAllowList) {
    if (!savedFields.containsKey(key)) continue;
    final value = savedFields[key];
    if (value == null) continue;
    // FieldValue / Timestamp are not callable-JSON safe.
    if (value.runtimeType.toString().contains('FieldValue')) continue;
    if (value is Map || value is List || value is num || value is bool) {
      out[key] = value;
      continue;
    }
    out[key] = value.toString();
  }
  return Map<String, dynamic>.unmodifiable(out);
}
