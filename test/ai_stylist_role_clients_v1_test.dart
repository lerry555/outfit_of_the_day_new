import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/ai_stylist_role_clients_v1.dart';

void main() {
  test(
    'responsibility registry pins benchmark roles without touching tier routing',
    () {
      expect(
        AiStylistResponsibilityRegistryV1.forRole(
          AiStylistResponsibilityV1.contextClarification,
        ).modelId,
        'gpt-4o',
      );
      expect(
        AiStylistResponsibilityRegistryV1.forRole(
          AiStylistResponsibilityV1.finalCandidateDecision,
        ).modelId,
        'gpt-5.4-mini',
      );
      expect(
        AiStylistResponsibilityRegistryV1.forRole(
          AiStylistResponsibilityV1.explanation,
        ).modelId,
        'claude-sonnet-5',
      );
    },
  );

  test('context response cannot promote an assumed value to a fact', () {
    final request = ContextClarificationRequestV1(
      knownFacts: const [ContextKnownFactV1(key: 'activity', value: 'walk')],
      unresolvedFacts: const [],
    );
    final response = ContextClarificationResponseV1(
      action: ContextClarificationActionV1.proceed,
      acceptedKnownFactKeys: const ['invented_weather'],
    );
    expect(response.isAllowedFor(request), isFalse);
  });

  test(
    'Minimal Necessary Clarification permits a legitimate second question',
    () {
      final first = ContextClarificationRequestV1(
        knownFacts: const [],
        unresolvedFacts: const [
          ContextMaterialUncertaintyV1(
            factKey: 'terrain',
            materialImpact: 'footwear_family',
          ),
          ContextMaterialUncertaintyV1(
            factKey: 'venue',
            materialImpact: 'formality',
          ),
        ],
      );
      expect(
        MinimalNecessaryClarificationPolicyV1.next(first)!.factKey,
        'terrain',
      );
      final second = ContextClarificationRequestV1(
        knownFacts: const [ContextKnownFactV1(key: 'terrain', value: 'trail')],
        unresolvedFacts: const [
          ContextMaterialUncertaintyV1(
            factKey: 'venue',
            materialImpact: 'formality',
          ),
        ],
        previouslyClarifiedFactKeys: const ['terrain'],
      );
      expect(
        MinimalNecessaryClarificationPolicyV1.next(second)!.factKey,
        'venue',
      );
    },
  );

  test('non-material uncertainty is not escalated into a clarification', () {
    final request = ContextClarificationRequestV1(
      knownFacts: const [],
      unresolvedFacts: const [
        ContextMaterialUncertaintyV1(
          factKey: 'nickname',
          materialImpact: 'style',
        ),
      ],
    );
    expect(MinimalNecessaryClarificationPolicyV1.next(request), isNull);
  });

  test('context model cannot proceed while a material uncertainty remains', () {
    final request = ContextClarificationRequestV1(
      knownFacts: const [],
      unresolvedFacts: const [
        ContextMaterialUncertaintyV1(
          factKey: 'terrain',
          materialImpact: 'terrain_suitability',
        ),
      ],
    );
    final response = ContextClarificationResponseV1(
      action: ContextClarificationActionV1.proceed,
    );
    expect(response.isAllowedFor(request), isFalse);
  });
}
