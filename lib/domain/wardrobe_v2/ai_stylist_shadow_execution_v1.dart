import '../../debug/ai_stylist_shadow_activation_v1.dart';
import 'ai_stylist_disabled_shadow_v1.dart';

/// A non-authoritative wrapper around a completed legacy result. The generic
/// legacy value is carried by identity and is never writable by shadow work.
class AiStylistShadowExecutionResultV1<TLegacy> {
  const AiStylistShadowExecutionResultV1({
    required this.legacyResult,
    required this.activation,
    this.shadowTrace,
    this.shadowFailureCode,
  });

  final TLegacy legacyResult;
  final AiStylistPathActivationV1 activation;
  final AiStylistShadowTraceV1? shadowTrace;
  final String? shadowFailureCode;

  bool get shadowExecuted => shadowTrace != null || shadowFailureCode != null;
  bool get shadowAuthoritative => false;
}

typedef AiStylistShadowWorkV1 = Future<AiStylistShadowTraceV1> Function();

/// This is intentionally not wired into Home or Stylist. If a future debug
/// callsite invokes it, any failure remains observational and the completed
/// legacy result is returned unchanged.
abstract final class AiStylistShadowExecutionV1 {
  static Future<AiStylistShadowExecutionResultV1<TLegacy>>
  preserveLegacy<TLegacy>({
    required TLegacy legacyResult,
    required AiStylistPathActivationV1 activation,
    required AiStylistShadowWorkV1 shadowWork,
  }) async {
    if (!AiStylistPathActivationPolicyV1.permitsShadow(activation)) {
      return AiStylistShadowExecutionResultV1(
        legacyResult: legacyResult,
        activation: AiStylistPathActivationV1.disabled,
      );
    }
    try {
      return AiStylistShadowExecutionResultV1(
        legacyResult: legacyResult,
        activation: activation,
        shadowTrace: await shadowWork(),
      );
    } catch (_) {
      return AiStylistShadowExecutionResultV1(
        legacyResult: legacyResult,
        activation: activation,
        shadowFailureCode: 'shadow_execution_failed',
      );
    }
  }
}
