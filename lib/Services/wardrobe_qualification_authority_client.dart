/// M11.1 Phase 10A/10C — Wardrobe qualification authority callable client.
///
/// Soft-fails until handlers are deployed. Waits for App Check bootstrap
/// before live callable invocation (SDK attaches token automatically).
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'firebase_app_check_bootstrap.dart';
import 'wardrobe_revision_lifecycle_client.dart';

const String kWardrobeQualificationAuthorityCallableName =
    'wardrobeQualificationAuthority';

const String kAuthorityActionAnalyzeCurrentSource = 'analyze_current_source';
const String kAuthorityActionReanalyzeCurrentSource =
    'reanalyze_current_source';

class WardrobeQualificationAuthorityClient {
  WardrobeQualificationAuthorityClient({
    WardrobeLifecycleCallableTransport? transport,
    FirebaseAppCheckBootstrap? appCheckBootstrap,
    this.functionName = kWardrobeQualificationAuthorityCallableName,
    this.region = kWardrobeLifecycleCallableRegion,
  }) : _transport = transport,
       _appCheck = appCheckBootstrap ?? FirebaseAppCheckBootstrap.instance;

  final WardrobeLifecycleCallableTransport? _transport;
  final FirebaseAppCheckBootstrap _appCheck;
  final String functionName;
  final String region;

  static WardrobeQualificationAuthorityClient instance =
      WardrobeQualificationAuthorityClient();

  Future<WardrobeLifecycleCallResult> analyzeCurrentSource({
    required String itemId,
    bool reanalyze = false,
    String? idempotencyKey,
  }) async {
    final action = reanalyze
        ? kAuthorityActionReanalyzeCurrentSource
        : kAuthorityActionAnalyzeCurrentSource;
    final data = <String, dynamic>{
      'contractVersion': 1,
      'itemId': itemId,
      'action': action,
      if (idempotencyKey != null && idempotencyKey.isNotEmpty)
        'idempotencyKey': idempotencyKey,
    };

    try {
      if (_transport == null) {
        final init = await _appCheck.ensureInitialized();
        if (!init.isReady) {
          debugPrint(
            '[WARDROBE_AUTHORITY] deferred_app_check_not_ready '
            'action=$action reason=${init.reasonCode}',
          );
          return WardrobeLifecycleCallResult(
            status: WardrobeLifecycleCallStatus.deferredUntilExport,
            operationKind: action,
            reasonCode: init.reasonCode ?? 'app_check_not_ready',
          );
        }
      }

      final response = await _invoke(data);
      if (response['ok'] == false) {
        return WardrobeLifecycleCallResult(
          status: WardrobeLifecycleCallStatus.failed,
          operationKind: action,
          reasonCode: response['reasonCode']?.toString() ?? 'authority_failed',
          raw: response,
        );
      }
      return WardrobeLifecycleCallResult(
        status: WardrobeLifecycleCallStatus.applied,
        operationKind: action,
        reasonCode: response['result'] is Map
            ? (response['result'] as Map)['reasonCode']?.toString()
            : response['status']?.toString(),
        raw: response,
      );
    } on FirebaseFunctionsException catch (e) {
      if (_isDeferred(e.code)) {
        debugPrint(
          '[WARDROBE_AUTHORITY] deferred_until_export '
          'action=$action code=${e.code} message=${e.message}',
        );
        return WardrobeLifecycleCallResult(
          status: WardrobeLifecycleCallStatus.deferredUntilExport,
          operationKind: action,
          reasonCode: e.code,
        );
      }
      debugPrint(
        '[WARDROBE_AUTHORITY] failed action=$action '
        'code=${e.code} message=${e.message}',
      );
      return WardrobeLifecycleCallResult(
        status: WardrobeLifecycleCallStatus.failed,
        operationKind: action,
        reasonCode: e.code,
      );
    } catch (e) {
      debugPrint('[WARDROBE_AUTHORITY] failed action=$action error=$e');
      return WardrobeLifecycleCallResult(
        status: WardrobeLifecycleCallStatus.failed,
        operationKind: action,
        reasonCode: 'client_error',
      );
    }
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

  static bool _isDeferred(String code) {
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
