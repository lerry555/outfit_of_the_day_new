import 'package:flutter/foundation.dart';

/// Lifecycle contract only. `live` is reserved for a later approved rollout;
/// this resolver intentionally never returns it from any runtime/compile-time
/// input in the current application.
enum AiStylistPathActivationV1 { disabled, devShadow, live }

abstract final class AiStylistPathActivationPolicyV1 {
  static const String _devShadowDefine = 'OOTD_AI_STYLIST_DEV_SHADOW';
  static const bool _requestedDevShadow = bool.fromEnvironment(
    _devShadowDefine,
    defaultValue: false,
  );

  static AiStylistPathActivationV1 get current => resolve(
    isDebugBuild: kDebugMode,
    requested: _requestedDevShadow ? 'dev_shadow' : null,
  );

  /// Strict parser for tests and future configuration boundaries. Unknown,
  /// absent and `live` are all disabled until a separately approved mechanism
  /// exists.
  static AiStylistPathActivationV1 resolve({
    required bool isDebugBuild,
    Object? requested,
  }) {
    if (!isDebugBuild || requested != 'dev_shadow') {
      return AiStylistPathActivationV1.disabled;
    }
    return AiStylistPathActivationV1.devShadow;
  }

  static bool permitsShadow(AiStylistPathActivationV1 activation) =>
      activation == AiStylistPathActivationV1.devShadow;

  static String get compileTimeDefineName => _devShadowDefine;
}
