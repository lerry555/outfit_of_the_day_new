import 'ai_stylist_disabled_shadow_v1.dart';
import 'ai_stylist_role_clients_v1.dart';

enum AiStylistTraceStageV1 {
  context,
  candidateGeneration,
  finalDecision,
  explanation,
}

enum AiStylistTraceAuthorityV1 { shadow, live }

/// Redacted stage-level event for a future analytics sink. It has no user ID,
/// raw prompt/history, wardrobe images, credentials or provider payloads.
class AiStylistStageTraceEventV1 {
  AiStylistStageTraceEventV1({
    required this.runId,
    required this.stage,
    required this.responsibility,
    required this.requestedModelAlias,
    required this.outcomeType,
    required this.latency,
    required this.authority,
    this.selectedCandidateId,
    this.rejectAll = false,
    this.validatorOutcome,
    this.fallbackReason,
    this.explanationFallbackUsed = false,
  }) {
    if (runId.trim().isEmpty) throw ArgumentError.value(runId, 'runId');
    if (authority != AiStylistTraceAuthorityV1.shadow) {
      throw ArgumentError('only shadow trace authority is currently allowed');
    }
    if (rejectAll && selectedCandidateId != null) {
      throw ArgumentError('reject_all must not include a selected candidate');
    }
  }

  final String runId;
  final AiStylistTraceStageV1 stage;
  final AiStylistResponsibilityV1 responsibility;
  final String requestedModelAlias;
  final String outcomeType;
  final Duration latency;
  final AiStylistTraceAuthorityV1 authority;
  final String? selectedCandidateId;
  final bool rejectAll;
  final String? validatorOutcome;
  final String? fallbackReason;
  final bool explanationFallbackUsed;

  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'stage': stage.name,
    'responsibility': responsibility.name,
    'requestedModelAlias': requestedModelAlias,
    'outcomeType': outcomeType,
    'latencyMs': latency.inMilliseconds,
    'selectedCandidateId': selectedCandidateId,
    'rejectAll': rejectAll,
    if (validatorOutcome != null) 'validatorOutcome': validatorOutcome,
    if (fallbackReason != null) 'fallbackReason': fallbackReason,
    'explanationFallbackUsed': explanationFallbackUsed,
    'authority': authority.name,
  };
}

abstract final class AiStylistShadowTraceEventsV1 {
  static List<AiStylistStageTraceEventV1> fromTrace({
    required String runId,
    required AiStylistShadowTraceV1 trace,
  }) {
    final events = <AiStylistStageTraceEventV1>[
      AiStylistStageTraceEventV1(
        runId: runId,
        stage: AiStylistTraceStageV1.context,
        responsibility: AiStylistResponsibilityV1.contextClarification,
        requestedModelAlias: 'gpt-4o',
        outcomeType: trace.context.status.name,
        latency: trace.stageTimings['context'] ?? Duration.zero,
        authority: AiStylistTraceAuthorityV1.shadow,
      ),
    ];
    if (trace.decision != null) {
      events.add(
        AiStylistStageTraceEventV1(
          runId: runId,
          stage: AiStylistTraceStageV1.finalDecision,
          responsibility: AiStylistResponsibilityV1.finalCandidateDecision,
          requestedModelAlias: 'gpt-5.4-mini',
          outcomeType: trace.decision!.kind.name,
          latency: trace.stageTimings['decision'] ?? Duration.zero,
          authority: AiStylistTraceAuthorityV1.shadow,
          selectedCandidateId: trace.decision!.selectedCandidateId,
          rejectAll: trace.decision!.isRejected,
          validatorOutcome: trace
              .decision!
              .envelope
              .postDecisionValidatorResult
              .reasonCodes
              .join(','),
          fallbackReason: trace.decision!.parseResult.failureCode,
        ),
      );
    }
    if (trace.explanation != null) {
      events.add(
        AiStylistStageTraceEventV1(
          runId: runId,
          stage: AiStylistTraceStageV1.explanation,
          responsibility: AiStylistResponsibilityV1.explanation,
          requestedModelAlias: 'claude-sonnet-5',
          outcomeType: trace.explanation!.usedFallback ? 'fallback' : 'success',
          latency: trace.stageTimings['explanation'] ?? Duration.zero,
          authority: AiStylistTraceAuthorityV1.shadow,
          selectedCandidateId: trace.decision?.selectedCandidateId,
          rejectAll: trace.decision?.isRejected ?? false,
          fallbackReason: trace.explanation!.failureCode,
          explanationFallbackUsed: trace.explanation!.usedFallback,
        ),
      );
    }
    return List.unmodifiable(events);
  }
}
