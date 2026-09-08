import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_simple_agent_service_v1.dart';

void main() {
  test('emoji greeting uses local fast path', () {
    final result = StylistSimpleAgentServiceV1.localFastReplyForMessage('ahoj 💪');
    expect(result, isNotNull);
    expect(result!['ok'], isTrue);
    expect(result['modelPath'], 'local_fast');
    expect(result['outfitChanged'], isFalse);
    expect(result['displayItemIds'], isEmpty);
  });

  test('plain greeting and thanks are local fast paths', () {
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('Čau!')?['modelPath'], 'local_fast');
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('Díky 🙌')?['modelPath'], 'local_fast');
  });

  test('real stylist requests never get swallowed by local fast path', () {
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('ahoj, zajtra idem na koncert a potrebujem outfit'), isNull);
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('zajtra idem na túru a potrebujem outfit'), isNull);
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('Áno'), isNull);
  });
}
