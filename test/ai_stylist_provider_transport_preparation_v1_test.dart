import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/ai_stylist_provider_transport_preparation_v1.dart';

void main() {
  test('provider preparation is declarative and role-specific', () {
    final decision = AiStylistProviderTransportPreparationsV1.decision
        .toSafeConfig();
    expect(decision['provider'], 'openai');
    expect(decision['modelId'], 'gpt-5.4-mini');
    expect(decision['reasoningEffort'], 'low');
    expect(decision.toString(), isNot(contains('secret')));
    expect(decision.toString(), isNot(contains('apiKey')));
  });

  test(
    'Claude preparation is explanation-only and has no decision wire mode',
    () {
      final explanation = AiStylistProviderTransportPreparationsV1.explanation
          .toSafeConfig();
      expect(explanation['provider'], 'anthropic');
      expect(explanation['modelId'], 'claude-sonnet-5');
      expect(explanation['outputMode'], 'strict_explanation_wire');
    },
  );
}
