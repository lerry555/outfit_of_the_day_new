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

  test('plain and natural friendly greetings use local fast path', () {
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('Čau!')?['modelPath'], 'local_fast');
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('čauko divočák')?['modelPath'], 'local_fast');
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('cauko kamarat')?['modelPath'], 'local_fast');
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('Díky 🙌')?['modelPath'], 'local_fast');
  });

  test('real stylist requests never get swallowed by local fast path', () {
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('ahoj, zajtra idem na koncert a potrebujem outfit'), isNull);
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('čauko, potrebujem outfit na túru'), isNull);
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('zajtra idem na túru a potrebujem outfit'), isNull);
    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('Áno'), isNull);
  });

  test('new chat keeps one V2 session when Firestore chat id appears after first turn', () {
    final service = StylistSimpleAgentServiceV1();

    final provisional = service.debugStableV2SessionIdForTurn(null);
    expect(provisional, startsWith('v2_'));
    service.debugMarkV2TurnAccepted(provisional);

    final afterUiChatCreated = service.debugStableV2SessionIdForTurn('real-chat-1');
    expect(afterUiChatCreated, provisional);
    service.debugMarkV2TurnAccepted(afterUiChatCreated, chatId: 'real-chat-1');

    expect(service.debugStableV2SessionIdForTurn('real-chat-1'), provisional);

    final switchedThread = service.debugStableV2SessionIdForTurn('real-chat-2');
    expect(switchedThread, 'real-chat-2');
    service.debugMarkV2TurnAccepted(switchedThread, chatId: 'real-chat-2');

    final freshBlankChat = service.debugStableV2SessionIdForTurn(null);
    expect(freshBlankChat, startsWith('v2_'));
    expect(freshBlankChat, isNot(provisional));
    expect(freshBlankChat, isNot('real-chat-2'));
  });
}
