import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_simple_agent_service_v1.dart';
import 'package:outfitofTheDay/widgets/stylist_quick_reply_buttons.dart';

void main() {
  test('server shopping prompt survives callable DTO normalization', () {
    final result = StylistSimpleAgentResultV1.fromCallableData(<String, dynamic>{
      'simpleAgent': true,
      'failClosed': false,
      'stylistComment': 'Tenisky sú kompromis.',
      'resultingOutfitItemIds': <String>[], 'displayItemIds': <String>[],
      'resultingOutfitItems': <Map<String, dynamic>>[], 'displayItems': <Map<String, dynamic>>[],
      'outfitChanged': false, 'quickReplyMode': 'yes_no',
      'quickReplyPrompt': 'Chceš, aby som ti vybral vhodnejšie turistické topánky?',
    });
    expect(result.quickReplyPrompt, 'Chceš, aby som ti vybral vhodnejšie turistické topánky?');
    expect(result.toUiResponse()['quickReplyPrompt'], result.quickReplyPrompt);
  });

  testWidgets('shopping prompt is rendered with Ano/Nie controls', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StylistQuickReplyButtons(
      prompt: 'Chceš, aby som ti vybral vhodnejšie turistické topánky?', onSelected: (_) {},
    ))));
    expect(find.text('Chceš, aby som ti vybral vhodnejšie turistické topánky?'), findsOneWidget);
    expect(find.text('Áno'), findsOneWidget);
    expect(find.text('Nie'), findsOneWidget);
  });
}
