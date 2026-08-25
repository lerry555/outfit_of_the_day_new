import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/data/conversation_decision.dart';
import 'package:outfitofTheDay/debug/stylist_conversation_qa_runner.dart';
import 'package:outfitofTheDay/utils/activity_traits_inferencer.dart';
import 'package:outfitofTheDay/utils/conversation_reasoner.dart';

void main() {
  group('ActivityTraitsInferencer', () {
    test('túra vyžaduje konkrétnu lokalitu', () {
      final t = ActivityTraitsInferencer.infer(
        'Zajtra chceme ísť na túru, potrebujem outfit.',
      );
      expect(t.requiresSpecificLocation, isTrue);
      expect(t.outdoor, isTrue);
    });

    test('práca — GPS stačí', () {
      final t = ActivityTraitsInferencer.infer('Idem do práce o 8:00.');
      expect(t.routineLocal, isTrue);
      expect(t.requiresSpecificLocation, isFalse);
    });

    test('preklep turu', () {
      final t = ActivityTraitsInferencer.infer('Idem na turu.');
      expect(t.outdoor, isTrue);
      expect(t.requiresSpecificLocation, isTrue);
    });
  });

  group('ConversationReasoner', () {
    test('túra bez miesta → CLARIFY', () {
      final d = ConversationReasoner.evaluate(
        conversation: 'Zajtra chceme ísť na túru, potrebujem outfit.',
        gpsCityLabel: 'Martin, Slovakia',
      );
      expect(d.action, ConversationAction.clarify);
      expect(d.missingInformation, MissingInformation.specificLocation);
    });

    test('práca → GENERATE', () {
      final d = ConversationReasoner.evaluate(
        conversation: 'Idem do práce o 9:00, potrebujem outfit.',
        gpsCityLabel: 'Martin, Slovakia',
      );
      expect(d.action, ConversationAction.generate);
    });

    test('USA → CLARIFY', () {
      final d = ConversationReasoner.evaluate(
        conversation: 'Idem do USA, potrebujem outfit.',
        gpsCityLabel: 'Martin, Slovakia',
      );
      expect(d.action, ConversationAction.clarify);
    });

    test('Oslo → GENERATE', () {
      final d = ConversationReasoner.evaluate(
        conversation: 'Idem do Osla o 9:00, potrebujem outfit.',
        gpsCityLabel: 'Martin, Slovakia',
      );
      expect(d.action, ConversationAction.generate);
    });

    test('Zoo → CLARIFY', () {
      final d = ConversationReasoner.evaluate(
        conversation: 'Idem do Zoo, potrebujem outfit.',
        gpsCityLabel: 'Martin, Slovakia',
      );
      expect(d.action, ConversationAction.clarify);
    });

    test('Zoo Bojnice → GENERATE', () {
      final d = ConversationReasoner.evaluate(
        conversation: 'Idem do Zoo Bojnice o 10:00, potrebujem outfit.',
        gpsCityLabel: 'Martin, Slovakia',
      );
      expect(d.action, ConversationAction.generate);
    });

    test('ferraty → CLARIFY', () {
      final d = ConversationReasoner.evaluate(
        conversation: 'Idem na ferraty, potrebujem outfit.',
        gpsCityLabel: 'Martin, Slovakia',
      );
      expect(d.action, ConversationAction.clarify);
    });

    test('ahoj → PASSTHROUGH', () {
      final d = ConversationReasoner.evaluate(
        conversation: 'Ahoj',
        gpsCityLabel: 'Martin, Slovakia',
      );
      expect(d.action, ConversationAction.passthrough);
    });
  });

  group('StylistConversationQaRunner', () {
    test('má aspoň 300 scenárov', () {
      expect(
        StylistConversationQaRunner.allCases().length,
        greaterThanOrEqualTo(300),
      );
    });

    test('všetky scenáre prejdú', () {
      final run = StylistConversationQaRunner.runAll(emitLogs: false);
      expect(run.meta.source, 'runtime_run');
      expect(run.meta.durationMs, greaterThanOrEqualTo(0));
      if (run.summary.failed > 0) {
        // ignore: avoid_print
        print(run.fullText());
      }
      expect(run.summary.failed, 0, reason: run.fullText());
    });
  });
}
