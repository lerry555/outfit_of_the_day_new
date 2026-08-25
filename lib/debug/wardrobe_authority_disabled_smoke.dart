/// Debug-only production disabled-mode smoke for wardrobe authority callables.
///
/// Enabled solely via:
/// `--dart-define=OOTD_WARDROBE_AUTHORITY_DISABLED_SMOKE=true`
/// Optional: `--dart-define=OOTD_SMOKE_ITEM_ID=<itemId>`
///
/// Never included in release UI. Does not log tokens/UID/URLs.
library;

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../Services/firebase_app_check_bootstrap.dart';
import '../Services/wardrobe_qualification_authority_client.dart';
import '../Services/wardrobe_revision_lifecycle_client.dart';

abstract final class WardrobeAuthorityDisabledSmoke {
  static const enabled = bool.fromEnvironment(
    'OOTD_WARDROBE_AUTHORITY_DISABLED_SMOKE',
  );
  static const itemIdDefine = String.fromEnvironment('OOTD_SMOKE_ITEM_ID');

  static bool _started = false;

  /// Schedule one-shot smoke after Firebase Auth is available (Google Sign-In).
  /// Returns true when the define is on so callers can skip CaptureAuth-style
  /// early exit and instead show AuthGate for interactive sign-in.
  static bool scheduleAfterAuthIfEnabled() {
    if (!kDebugMode || !enabled || _started) return enabled && kDebugMode;
    _started = true;
    // Fire-and-forget; result is emitted to logcat.
    // ignore: unawaited_futures
    _runWhenAuthenticated();
    return true;
  }

  static Future<void> _runWhenAuthenticated() async {
    final marker = 'WARDROBE_AUTHORITY_DISABLED_SMOKE_RESULT';
    try {
      var user = FirebaseAuth.instance.currentUser;
      // Drop non-Google / unusable sessions left on the emulator (e.g. failed
      // anonymous attempts). Smoke requires a real Google Sign-In session.
      if (user != null && user.isAnonymous) {
        await FirebaseAuth.instance.signOut();
        user = null;
      }
      if (user != null) {
        try {
          await user.getIdToken(true);
        } on FirebaseAuthException {
          await FirebaseAuth.instance.signOut();
          user = null;
        }
      }
      user ??= await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null && !u.isAnonymous)
          .timeout(
            const Duration(minutes: 3),
            onTimeout: () => null,
          );
      if (user == null) {
        _emit(marker, {
          'ok': false,
          'verdict': 'auth_unavailable',
          'reasonCode': 'capture_auth_unavailable',
        });
        return;
      }

      final appCheck =
          await FirebaseAppCheckBootstrap.instance.ensureInitialized();
      final itemId = itemIdDefine.trim();
      if (itemId.isEmpty) {
        _emit(marker, {
          'ok': false,
          'verdict': 'item_id_required',
          'reasonCode': 'smoke_item_id_missing',
          'appCheckReady': appCheck.isReady,
          'appCheckReason': appCheck.reasonCode,
          'appCheckProvider': appCheck.providerKind.name,
          'isDebugBuild': appCheck.isDebugBuild,
        });
        return;
      }

      final lifecycleClient = WardrobeRevisionLifecycleClient.instance;
      final authorityClient = WardrobeQualificationAuthorityClient.instance;

      final lifecycle = await lifecycleClient.callOperation(
        operationKind: kLifecycleOpSameImageReanalysis,
        itemId: itemId,
        idempotencyKey: 'm11-1-10er-lifecycle-smoke-1',
      );
      final authority = await authorityClient.analyzeCurrentSource(
        itemId: itemId,
        idempotencyKey: 'm11-1-10er-authority-smoke-1',
      );

      _emit(marker, {
        'ok': true,
        'projectHint': 'outfitoftheday-4d401',
        'region': kWardrobeLifecycleCallableRegion,
        'lifecycleCallable': kWardrobeRevisionLifecycleCallableName,
        'authorityCallable': kWardrobeQualificationAuthorityCallableName,
        'itemFingerprint': _fingerprint(itemId),
        'uidFingerprint': _fingerprint(user.uid),
        'authVia': 'google_sign_in_session',
        'appCheckReady': appCheck.isReady,
        'appCheckReason': appCheck.reasonCode,
        'appCheckProvider': appCheck.providerKind.name,
        'isDebugBuild': appCheck.isDebugBuild,
        'authPresent': true,
        'emulatorFunctions': false,
        'lifecycle': {
          'status': lifecycle.status.name,
          'reasonCode': lifecycle.reasonCode,
          'operationKind': lifecycle.operationKind,
          'ok': lifecycle.ok,
        },
        'authority': {
          'status': authority.status.name,
          'reasonCode': authority.reasonCode,
          'operationKind': authority.operationKind,
          'ok': authority.ok,
        },
      });
    } catch (e) {
      _emit(marker, {
        'ok': false,
        'verdict': 'smoke_harness_error',
        'reasonCode': 'client_error',
        'errorType': e.runtimeType.toString(),
        'errorCode': e is FirebaseAuthException ? e.code : null,
        'errorMessage': e is FirebaseAuthException
            ? e.message
            : e.toString().length > 160
                ? e.toString().substring(0, 160)
                : e.toString(),
      });
    }
  }

  static void _emit(String marker, Map<String, Object?> payload) {
    debugPrint('$marker ${jsonEncode(payload)}');
  }

  static String _fingerprint(String value) {
    var hash = 0;
    for (final code in value.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
