import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

abstract final class AiStylistRealDevShadowSmokePolicyV1 {
  static const String defineName = 'OOTD_AI_STYLIST_REAL_DEV_SHADOW_SMOKE';
  static const bool _requested = bool.fromEnvironment(
    defineName,
    defaultValue: false,
  );

  static bool get current =>
      permits(isDebugBuild: kDebugMode, explicitlyRequested: _requested);

  @visibleForTesting
  static bool permits({
    required bool isDebugBuild,
    required bool explicitlyRequested,
  }) => isDebugBuild && explicitlyRequested;
}

/// One-shot client entry into the isolated server fixture smoke. The callable
/// response has no route into Home/Stylist state, persistence or explanation.
abstract final class AiStylistRealDevShadowSmokeTriggerV1 {
  static bool _claimedForProcess = false;

  static Future<void> launchIfExplicitlyEnabled() async {
    if (!AiStylistRealDevShadowSmokePolicyV1.current) return;
    if (_claimedForProcess) return;
    _claimedForProcess = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint(
          '[AI_STYLIST_REAL_DEV_SHADOW] smoke_failed code=unauthenticated',
        );
        return;
      }
      await user.getIdToken(true);
      await FirebaseFunctions.instanceFor(region: 'us-east1')
          .httpsCallable('aiStylistDevShadowSmoke')
          .call<Object?>(const <String, Object?>{
            'contractVersion': 1,
            'fixtureId': 'ootd_dev_shadow_minimal_v1',
            'confirmNonAuthoritative': true,
          });
      debugPrint('[AI_STYLIST_REAL_DEV_SHADOW] smoke_completed');
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        '[AI_STYLIST_REAL_DEV_SHADOW] smoke_failed code=${error.code}',
      );
    } catch (_) {
      debugPrint('[AI_STYLIST_REAL_DEV_SHADOW] smoke_failed code=local_error');
    }
  }
}
