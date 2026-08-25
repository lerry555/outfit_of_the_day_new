import '../../models/outfit_context_state.dart';
import 'ai_stylist_role_clients_v1.dart';
import 'frozen_outfit_decision_request_v1.dart';

/// Deterministic projection of existing context state into the disabled U/D/R
/// path. It copies only already-known values; it never turns an inference,
/// profile preference, raw conversation, or null into a fact.
abstract final class AiStylistKnownContextAdapterV1 {
  static FrozenOutfitResolvedContextV1 resolvedContext(
    OutfitContextState state,
  ) => FrozenOutfitResolvedContextV1(
    activity: _known(state.activityHint),
    occasion: _known(state.occasion),
    environment: state.activityLocationKnown
        ? _known(state.activityLocationLabel)
        : null,
    relevantKnownTimingFacts: <String, String?>{
      'dateKey': _known(state.dateKey),
      'hourLocal': state.hourExplicit && state.hourLocal != null
          ? state.hourLocal.toString()
          : null,
    },
  );

  static ContextClarificationRequestV1 clarificationRequest(
    OutfitContextState state, {
    Iterable<ContextMaterialUncertaintyV1> unresolvedFacts = const [],
    Iterable<String> previouslyClarifiedFactKeys = const [],
  }) {
    final context = resolvedContext(state).toJson();
    final facts = <ContextKnownFactV1>[];
    for (final entry in context.entries) {
      if (entry.value is String) {
        facts.add(
          ContextKnownFactV1(key: entry.key, value: entry.value! as String),
        );
      }
    }
    final timing = context['relevantKnownTimingFacts'];
    if (timing is Map) {
      for (final entry in timing.entries) {
        if (entry.value is String) {
          facts.add(
            ContextKnownFactV1(
              key: 'timing.${entry.key}',
              value: entry.value as String,
            ),
          );
        }
      }
    }
    return ContextClarificationRequestV1(
      knownFacts: facts,
      unresolvedFacts: unresolvedFacts,
      previouslyClarifiedFactKeys: previouslyClarifiedFactKeys,
    );
  }
}

String? _known(String? value) =>
    value?.trim().isNotEmpty == true ? value!.trim() : null;
