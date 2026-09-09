import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_simple_agent_service_v1.dart';
import 'package:outfitofTheDay/widgets/stylist_quick_reply_buttons.dart';

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

  testWidgets('shopping follow-up renders prompt directly above yes-no buttons', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StylistQuickReplyButtons(
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('stylist-quick-reply-prompt')), findsOneWidget);
    expect(find.text('Chceš, aby som ti pomohol vybrať vhodnejší kúsok do šatníka?'), findsOneWidget);
    expect(find.byKey(const ValueKey('stylist-quick-reply-yes')), findsOneWidget);
    expect(find.byKey(const ValueKey('stylist-quick-reply-no')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stylist-quick-reply-yes')));
    await tester.pump();
    expect(selected, 'Áno');

    await tester.tap(find.byKey(const ValueKey('stylist-quick-reply-no')));
    await tester.pump();
    expect(selected, 'Nie');
  });
}
