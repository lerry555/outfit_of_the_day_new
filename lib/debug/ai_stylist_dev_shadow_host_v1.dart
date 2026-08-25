import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/wardrobe_v2/ai_stylist_disabled_shadow_v1.dart';
import '../domain/wardrobe_v2/ai_stylist_observability_v1.dart';
import '../domain/wardrobe_v2/ai_stylist_role_clients_v1.dart';
import '../domain/wardrobe_v2/ai_stylist_shadow_execution_v1.dart';
import '../domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import '../domain/wardrobe_v2/frozen_outfit_decision_request_v1.dart';
import '../domain/wardrobe_v2/frozen_outfit_explanation_contract_v1.dart';
import 'ai_stylist_real_dev_shadow_smoke_trigger_v1.dart';
import 'ai_stylist_shadow_activation_v1.dart';

/// Bounded debug-only ledger. Its run key is derived only from a generation's
/// candidate IDs and redacted weather signature; it holds neither identity nor
/// user-visible output. It prevents rebuilds from creating repeat shadow runs.
abstract final class AiStylistDevShadowRunLedgerV1 {
  static const int _maxKeys = 128;
  static final Queue<String> _keys = Queue<String>();
  static final Set<String> _seen = <String>{};

  static bool claim(String key) {
    if (_seen.contains(key)) return false;
    _seen.add(key);
    _keys.addLast(key);
    while (_keys.length > _maxKeys) {
      _seen.remove(_keys.removeFirst());
    }
    return true;
  }

  @visibleForTesting
  static void reset() {
    _keys.clear();
    _seen.clear();
  }
}

/// Bounded local trace sink. It has no analytics, Firebase or disk dependency.
abstract final class AiStylistDevShadowTraceSinkV1 {
  static const int _maxEvents = 256;
  static final List<AiStylistStageTraceEventV1> _events =
      <AiStylistStageTraceEventV1>[];

  static List<AiStylistStageTraceEventV1> get events =>
      List.unmodifiable(_events);

  static void record(AiStylistStageTraceEventV1 event) {
    if (!kDebugMode) return;
    _events.add(event);
    if (_events.length > _maxEvents) _events.removeAt(0);
    debugPrint(
      '[AI_STYLIST_DEV_SHADOW] run=${event.runId} stage=${event.stage.name} '
      'outcome=${event.outcomeType} authority=${event.authority.name}',
    );
  }

  @visibleForTesting
  static void reset() => _events.clear();
}

class AiStylistDevShadowFakeContextClientV1 implements ContextDecisionClientV1 {
  const AiStylistDevShadowFakeContextClientV1();
  @override
  Future<Object?> interpret(ContextClarificationRequestV1 request) async =>
      const <String, Object?>{'action': 'proceed'};
}

/// Fake by default: reject_all avoids constructing any synthetic "winner".
class AiStylistDevShadowFakeDecisionClientV1
    implements FinalCandidateDecisionClientV1 {
  const AiStylistDevShadowFakeDecisionClientV1();
  @override
  Future<Object?> decide(FrozenOutfitDecisionRequestV1 request) async =>
      const <String, Object?>{
        'action': 'reject_all',
        'selectedCandidateId': null,
      };
}

class AiStylistDevShadowFakeExplanationClientV1 implements ExplanationClientV1 {
  const AiStylistDevShadowFakeExplanationClientV1();
  @override
  Future<Object?> explain(FrozenOutfitExplanationRequestV1 request) async =>
      const <String, Object?>{
        'explanation': 'Výsledok je iba neautoritná vývojová kontrola.',
      };
}

/// Shared Home/Stylist sidecar host. `launchAfterLegacyFinalized` is invoked
/// only with an already-created legacy result and returns immediately.
class AiStylistDevShadowHostV1 {
  const AiStylistDevShadowHostV1({
    this.contextClient = const AiStylistDevShadowFakeContextClientV1(),
    this.decisionClient = const AiStylistDevShadowFakeDecisionClientV1(),
    this.explanationClient = const AiStylistDevShadowFakeExplanationClientV1(),
    this.activationOverride,
  });

  final ContextDecisionClientV1 contextClient;
  final FinalCandidateDecisionClientV1 decisionClient;
  final ExplanationClientV1 explanationClient;
  final AiStylistPathActivationV1? activationOverride;

  void launchAfterLegacyFinalized({
    required Object legacyResult,
    required Iterable<V2FlexibleCandidate> candidates,
    required String weatherSignature,
    bool allowRealProviderSmoke = false,
  }) {
    final activation =
        activationOverride ?? AiStylistPathActivationPolicyV1.current;
    if (!AiStylistPathActivationPolicyV1.permitsShadow(activation)) return;
    final captured = List<V2FlexibleCandidate>.unmodifiable(candidates);
    final runId = _runId(captured, weatherSignature);
    if (!AiStylistDevShadowRunLedgerV1.claim(runId)) return;
    unawaited(
      _execute(
        legacyResult: legacyResult,
        candidates: captured,
        weatherSignature: weatherSignature,
        activation: activation,
        runId: runId,
      ),
    );
    // A second compile-time gate protects the isolated real-provider fixture.
    // Its response is intentionally ignored and cannot enter app state.
    if (allowRealProviderSmoke) {
      unawaited(
        AiStylistRealDevShadowSmokeTriggerV1.launchIfExplicitlyEnabled(),
      );
    }
  }

  Future<void> _execute({
    required Object legacyResult,
    required List<V2FlexibleCandidate> candidates,
    required String weatherSignature,
    required AiStylistPathActivationV1 activation,
    required String runId,
  }) async {
    final ownedItemIds = candidates
        .expand(
          (candidate) => candidate.outfit.items.map((item) => item.itemId),
        )
        .toSet();
    final context = FrozenOutfitResolvedContextV1(
      weather: weatherSignature.isEmpty ? null : weatherSignature,
    );
    final execution = await AiStylistShadowExecutionV1.preserveLegacy(
      legacyResult: legacyResult,
      activation: activation,
      shadowWork: () =>
          AiStylistDisabledShadowRunnerV1(
            contextClient: contextClient,
            decisionClient: decisionClient,
            explanationClient: explanationClient,
          ).runFromGeneratedCandidates(
            contextRequest: ContextClarificationRequestV1(
              knownFacts: weatherSignature.isEmpty
                  ? const []
                  : [
                      ContextKnownFactV1(
                        key: 'weather',
                        value: weatherSignature,
                      ),
                    ],
              unresolvedFacts: const [],
            ),
            resolvedContext: context,
            generatedCandidates: candidates,
            authoritativeOwnedItemIds: ownedItemIds,
          ),
    );
    final trace = execution.shadowTrace;
    if (trace == null) {
      AiStylistDevShadowTraceSinkV1.record(
        AiStylistStageTraceEventV1(
          runId: runId,
          stage: AiStylistTraceStageV1.finalDecision,
          responsibility: AiStylistResponsibilityV1.finalCandidateDecision,
          requestedModelAlias: 'gpt-5.4-mini',
          outcomeType: execution.shadowFailureCode ?? 'not_started',
          latency: Duration.zero,
          authority: AiStylistTraceAuthorityV1.shadow,
          rejectAll: true,
          fallbackReason: execution.shadowFailureCode,
        ),
      );
      return;
    }
    for (final event in AiStylistShadowTraceEventsV1.fromTrace(
      runId: runId,
      trace: trace,
    )) {
      AiStylistDevShadowTraceSinkV1.record(event);
    }
  }

  static String _runId(
    Iterable<V2FlexibleCandidate> candidates,
    String weatherSignature,
  ) {
    final candidateIds =
        candidates
            .map((candidate) => candidate.candidateId)
            .toList(growable: false)
          ..sort();
    final source = <String>[...candidateIds, weatherSignature].join('|');
    var hash = 2166136261;
    for (final code in source.codeUnits) {
      hash ^= code;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 'dev-shadow-${hash.toRadixString(16)}';
  }
}
