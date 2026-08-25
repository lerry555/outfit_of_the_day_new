import 'frozen_outfit_decision_orchestration_v1.dart';
import 'frozen_outfit_explanation_contract_v1.dart';

enum AiStylistResponsibilityV1 {
  contextClarification,
  finalCandidateDecision,
  explanation,
}

class AiStylistResponsibilityBindingV1 {
  const AiStylistResponsibilityBindingV1({
    required this.role,
    required this.provider,
    required this.modelId,
  });
  final AiStylistResponsibilityV1 role;
  final String provider;
  final String modelId;
}

/// Additive registry. It intentionally does not touch the legacy tier router.
abstract final class AiStylistResponsibilityRegistryV1 {
  static const bindings = <AiStylistResponsibilityBindingV1>[
    AiStylistResponsibilityBindingV1(
      role: AiStylistResponsibilityV1.contextClarification,
      provider: 'openai',
      modelId: 'gpt-4o',
    ),
    AiStylistResponsibilityBindingV1(
      role: AiStylistResponsibilityV1.finalCandidateDecision,
      provider: 'openai',
      modelId: 'gpt-5.4-mini',
    ),
    AiStylistResponsibilityBindingV1(
      role: AiStylistResponsibilityV1.explanation,
      provider: 'anthropic',
      modelId: 'claude-sonnet-5',
    ),
  ];

  static AiStylistResponsibilityBindingV1 forRole(
    AiStylistResponsibilityV1 role,
  ) => bindings.singleWhere((binding) => binding.role == role);
}

enum ContextClarificationActionV1 { proceed, askClarification, stop }

class ContextKnownFactV1 {
  const ContextKnownFactV1({required this.key, required this.value});
  final String key;
  final String value;
}

class ContextClarificationRequestV1 {
  ContextClarificationRequestV1({
    required Iterable<ContextKnownFactV1> knownFacts,
    required Iterable<ContextMaterialUncertaintyV1> unresolvedFacts,
    Iterable<String> previouslyClarifiedFactKeys = const <String>[],
  }) : knownFacts = List.unmodifiable(knownFacts),
       unresolvedFacts = List.unmodifiable(unresolvedFacts),
       previouslyClarifiedFactKeys = Set.unmodifiable(
         previouslyClarifiedFactKeys,
       );
  final List<ContextKnownFactV1> knownFacts;
  final List<ContextMaterialUncertaintyV1> unresolvedFacts;
  final Set<String> previouslyClarifiedFactKeys;

  Map<String, Object?> toCanonicalPayload() => <String, Object?>{
    'contractVersion': 1,
    'responsibility': 'contextClarification',
    'task':
        'Interpret only supplied facts. Ask only for a listed material uncertainty. Never invent facts.',
    'knownFacts': <String, String>{
      for (final fact in knownFacts) fact.key: fact.value,
    },
    'unresolvedMaterialFactKeys': unresolvedFacts
        .map((fact) => fact.factKey)
        .toList(growable: false),
    'previouslyClarifiedFactKeys': previouslyClarifiedFactKeys.toList(
      growable: false,
    ),
    'allowedActions': const ['proceed', 'ask_clarification', 'stop'],
  };
}

class ContextMaterialUncertaintyV1 {
  const ContextMaterialUncertaintyV1({
    required this.factKey,
    required this.materialImpact,
  });
  final String factKey;
  final String materialImpact;
}

class ContextClarificationResponseV1 {
  ContextClarificationResponseV1({
    required this.action,
    this.clarificationFactKey,
    Iterable<String> acceptedKnownFactKeys = const <String>[],
  }) : acceptedKnownFactKeys = Set.unmodifiable(acceptedKnownFactKeys) {
    if (action == ContextClarificationActionV1.askClarification &&
        (clarificationFactKey == null ||
            clarificationFactKey!.trim().isEmpty)) {
      throw ArgumentError('askClarification requires clarificationFactKey');
    }
  }
  final ContextClarificationActionV1 action;
  final String? clarificationFactKey;
  final Set<String> acceptedKnownFactKeys;

  /// No values can be inserted by this contract, preventing model assumptions
  /// from becoming facts. Only caller-supplied known fact keys may be accepted.
  bool isAllowedFor(ContextClarificationRequestV1 request) {
    if (!acceptedKnownFactKeys.every(
      (key) => request.knownFacts.any((fact) => fact.key == key),
    )) {
      return false;
    }
    final required = MinimalNecessaryClarificationPolicyV1.next(request);
    if (action == ContextClarificationActionV1.proceed) {
      return required == null;
    }
    if (action != ContextClarificationActionV1.askClarification) {
      return true;
    }
    return request.unresolvedFacts.any(
      (fact) =>
          fact.factKey == clarificationFactKey &&
          _isMaterialImpact(fact.materialImpact),
    );
  }
}

/// Strict, provider-neutral context wire parser. It has no field through which
/// a context provider can invent a fact value, choose a candidate or alter an
/// explanation.
abstract final class ContextClarificationTransportAdapterV1 {
  static ContextClarificationResponseV1 parse(Object? wire) {
    if (wire is ContextClarificationResponseV1) return wire;
    if (wire is! Map) throw const FormatException('context_payload_not_object');
    final map = Map<Object?, Object?>.from(wire);
    const allowed = <String>{
      'action',
      'clarificationFactKey',
      'acceptedKnownFactKeys',
    };
    if (map.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('context_payload_unknown_field');
    }
    final action = switch (map['action']) {
      'proceed' => ContextClarificationActionV1.proceed,
      'ask_clarification' => ContextClarificationActionV1.askClarification,
      'stop' => ContextClarificationActionV1.stop,
      null => throw const FormatException('context_action_missing'),
      _ => throw const FormatException('context_action_invalid'),
    };
    final clarificationFactKey = map['clarificationFactKey'];
    if (clarificationFactKey != null && clarificationFactKey is! String) {
      throw const FormatException('context_clarification_key_invalid');
    }
    if (action == ContextClarificationActionV1.askClarification &&
        (clarificationFactKey is! String ||
            clarificationFactKey.trim().isEmpty)) {
      throw const FormatException('context_clarification_key_missing');
    }
    final accepted = map['acceptedKnownFactKeys'];
    if (accepted != null &&
        (accepted is! List || accepted.any((value) => value is! String))) {
      throw const FormatException('context_accepted_fact_keys_invalid');
    }
    return ContextClarificationResponseV1(
      action: action,
      clarificationFactKey: clarificationFactKey as String?,
      acceptedKnownFactKeys: accepted == null
          ? const []
          : List<String>.from(accepted as List),
    );
  }
}

bool _isMaterialImpact(String value) => const {
  'footwear_family',
  'protection_layering',
  'formality',
  'terrain_suitability',
  'outfit_acceptability',
}.contains(value);

/// Disabled-path policy representation for Minimal Necessary Clarification.
/// It does not impose a global one-question limit: after a user resolves one
/// material uncertainty, a distinct remaining material uncertainty may be
/// asked in the next request.
abstract final class MinimalNecessaryClarificationPolicyV1 {
  static ContextMaterialUncertaintyV1? next(
    ContextClarificationRequestV1 request,
  ) {
    for (final fact in request.unresolvedFacts) {
      if (_isMaterialImpact(fact.materialImpact) &&
          !request.previouslyClarifiedFactKeys.contains(fact.factKey)) {
        return fact;
      }
    }
    return null;
  }
}

abstract interface class ContextDecisionClientV1 {
  Future<Object?> interpret(ContextClarificationRequestV1 request);
}

/// The role aliases make authority boundaries explicit at call sites.
abstract interface class FinalCandidateDecisionClientV1
    implements FrozenOutfitDecisionClientV1 {}

abstract interface class ExplanationClientV1
    implements FrozenOutfitExplanationClientV1 {}
