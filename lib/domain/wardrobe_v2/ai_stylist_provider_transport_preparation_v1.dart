import 'ai_stylist_role_clients_v1.dart';

/// Declarative transport preparation only. It contains no HTTP client, Firebase
/// secret binding, environment lookup or provider call. Runtime transports must
/// be separately injected behind the role interfaces after activation approval.
class AiStylistProviderTransportPreparationV1 {
  const AiStylistProviderTransportPreparationV1({
    required this.binding,
    required this.timeout,
    required this.outputMode,
    this.reasoningEffort,
  });

  final AiStylistResponsibilityBindingV1 binding;
  final Duration timeout;
  final String outputMode;
  final String? reasoningEffort;

  Map<String, Object?> toSafeConfig() => <String, Object?>{
    'role': binding.role.name,
    'provider': binding.provider,
    'modelId': binding.modelId,
    'timeoutMs': timeout.inMilliseconds,
    'outputMode': outputMode,
    if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
  };
}

abstract final class AiStylistProviderTransportPreparationsV1 {
  // Based on the audited benchmark adapter's model-family semantics: GPT-5
  // accepts reasoning effort; classic GPT-4o does not require it. This remains
  // metadata until an approved, mocked transport implementation is wired.
  static final context = AiStylistProviderTransportPreparationV1(
    binding: AiStylistResponsibilityRegistryV1.forRole(
      AiStylistResponsibilityV1.contextClarification,
    ),
    timeout: const Duration(seconds: 30),
    outputMode: 'structured_json',
  );
  static final decision = AiStylistProviderTransportPreparationV1(
    binding: AiStylistResponsibilityRegistryV1.forRole(
      AiStylistResponsibilityV1.finalCandidateDecision,
    ),
    timeout: const Duration(seconds: 30),
    outputMode: 'strict_decision_wire',
    reasoningEffort: 'low',
  );
  static final explanation = AiStylistProviderTransportPreparationV1(
    binding: AiStylistResponsibilityRegistryV1.forRole(
      AiStylistResponsibilityV1.explanation,
    ),
    timeout: const Duration(seconds: 30),
    outputMode: 'strict_explanation_wire',
  );
}
