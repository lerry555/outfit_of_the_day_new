import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_chat_service.dart';
import 'package:outfitofTheDay/Services/stylist_job_consumer.dart';
import 'package:outfitofTheDay/screens/stylist_chat_screen.dart';

StylistJobRaw _doneRaw({
  String reply = 'Outfit je pripravený.',
  String action = 'chat',
  String? chatId,
}) {
  return StylistJobRaw(
    exists: true,
    status: 'done',
    result: <String, dynamic>{
      'reply': reply,
      'action': action,
      'suggestedItems': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'top-1', 'name': 'Biele tričko'},
      ],
      if (chatId != null) 'chatId': chatId,
    },
  );
}

StylistJobConsumer _consumer({
  required Stream<StylistJobRaw> Function(String jobId) watch,
  Future<void> Function(String jobId)? delete,
  Duration? waitTimeout,
  Duration? missingGrace,
}) {
  return StylistJobConsumer(
    watch: watch,
    delete: delete ?? ((_) async {}),
    normalize: StylistChatService.normalizeJobResult,
    waitTimeout: waitTimeout ?? const Duration(milliseconds: 80),
    hydrationMissingGrace: missingGrace ?? const Duration(milliseconds: 40),
  );
}

void main() {
  group('normalizeJobResult', () {
    test('matches the live sendMessage response shape', () {
      final normalized = StylistChatService.normalizeJobResult({
        'reply': 'Ahoj',
        'action': 'chat',
        'suggestedItems': [
          {'id': '1', 'name': 'Košeľa'},
        ],
        'offerWardrobe': true,
      });
      expect(normalized['ok'], isTrue);
      expect(normalized['reply'], 'Ahoj');
      expect(normalized['action'], 'chat');
      expect(normalized['suggestedItems'], isA<List>());
      expect(normalized['offerWardrobe'], isTrue);
    });
  });

  group('job states', () {
    test('done job is normalized for consumption', () async {
      final consumer = _consumer(
        watch: (_) => Stream<StylistJobRaw>.fromIterable([_doneRaw()]),
      );
      final snapshot = await consumer.readOnce('job-done');
      expect(snapshot.status, StylistJobStatus.done);
      expect(snapshot.response?['ok'], isTrue);
      expect(snapshot.response?['reply'], 'Outfit je pripravený.');
      expect(
        (snapshot.response?['suggestedItems'] as List).single['id'],
        'top-1',
      );
    });

    test('pending job waits until done and consumes once', () async {
      final consumer = _consumer(
        watch: (_) async* {
          yield const StylistJobRaw(exists: true, status: 'pending');
          await Future<void>.delayed(const Duration(milliseconds: 15));
          yield _doneRaw(reply: 'Hotovo po čakaní.');
        },
      );
      final snapshot = await consumer.watchForHydration('job-pending');
      expect(snapshot.status, StylistJobStatus.done);
      expect(snapshot.response?['reply'], 'Hotovo po čakaní.');
    });

    test('failed job uses existing ok:false semantics', () async {
      final consumer = _consumer(
        watch: (_) => Stream<StylistJobRaw>.fromIterable([
          const StylistJobRaw(exists: true, status: 'error'),
        ]),
      );
      final snapshot = await consumer.watchForHydration('job-fail');
      expect(snapshot.status, StylistJobStatus.failed);
      expect(snapshot.response?['ok'], isFalse);
      expect(snapshot.response?['action'], 'chat');
    });

    test('missing job is missing, not an invented reply', () async {
      final consumer = _consumer(
        watch: (_) => Stream<StylistJobRaw>.fromIterable([
          const StylistJobRaw.missing(),
        ]),
      );
      final snapshot = await consumer.watchForHydration('job-missing');
      expect(snapshot.status, StylistJobStatus.missing);
      expect(snapshot.response, isNull);
    });
  });

  group('duplicate protection', () {
    test('sourceJobId round-trips through chat persistence maps', () {
      const message = StylistChatMessage(
        text: 'Tu je návrh.',
        isUser: false,
        sourceJobId: 'job-42',
        suggestedItems: [
          {'id': 'a'},
        ],
      );
      final restored = StylistChatMessage.fromMap(message.toMap());
      expect(restored.sourceJobId, 'job-42');
      expect(restored.text, 'Tu je návrh.');
      expect(restored.suggestedItems.single['id'], 'a');
    });

    test('already persisted jobId does not append again', () {
      expect(
        stylistChatAlreadyHasJobResult(
          sourceJobIds: const ['job-1', 'job-2'],
          assistantTexts: const ['starý text'],
          jobId: 'job-2',
          replyText: 'nový text',
        ),
        isTrue,
      );
    });

    test('in-memory reply without jobId still matches by assistant text', () {
      expect(
        stylistChatAlreadyHasJobResult(
          sourceJobIds: const [null],
          assistantTexts: const ['Už to tu je.'],
          jobId: 'job-old',
          replyText: 'Už to tu je.',
        ),
        isTrue,
      );
    });

    test('missing job plus missing reply is not treated as present', () {
      expect(
        stylistChatAlreadyHasJobResult(
          sourceJobIds: const [null],
          assistantTexts: const [],
          jobId: 'job-gone',
          replyText: 'Toto by sa nemalo vymyslieť.',
        ),
        isFalse,
      );
    });
  });

  group('chat targeting', () {
    test('non-empty intent chatId wins', () {
      expect(
        resolveStylistHydrationChatId(
          intentChatId: 'chat-intent',
          resultChatId: 'chat-result',
        ),
        'chat-intent',
      );
    });

    test('empty chatId falls back to result chatId, never invents one', () {
      expect(
        resolveStylistHydrationChatId(intentChatId: '', resultChatId: 'chat-r'),
        'chat-r',
      );
      expect(
        resolveStylistHydrationChatId(intentChatId: '', resultChatId: ''),
        isNull,
      );
      expect(
        resolveStylistHydrationChatId(intentChatId: null, resultChatId: null),
        isNull,
      );
    });
  });

  group('persist before delete', () {
    test('chat persistence completes BEFORE job deletion', () async {
      final order = <String>[];
      final snapshot = StylistJobSnapshot(
        jobId: 'job-persist',
        status: StylistJobStatus.done,
        response: StylistChatService.normalizeJobResult({
          'reply': 'Uložené.',
          'action': 'chat',
        }),
      );

      final ok = await consumeCompletedJobSafely(
        snapshot: snapshot,
        apply: (response) async {
          order.add('apply:${response['reply']}');
        },
        persistChat: () async {
          order.add('persist-start');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          order.add('persist-end');
          return true;
        },
        deleteJob: (id) async {
          order.add('delete:$id');
        },
      );

      expect(ok, isTrue);
      expect(order, [
        'apply:Uložené.',
        'persist-start',
        'persist-end',
        'delete:job-persist',
      ]);
    });

    test('does not delete the job when chat persist fails', () async {
      var deleted = false;
      final ok = await consumeCompletedJobSafely(
        snapshot: StylistJobSnapshot(
          jobId: 'job-keep',
          status: StylistJobStatus.done,
          response: StylistChatService.normalizeJobResult({
            'reply': 'x',
            'action': 'chat',
          }),
        ),
        apply: (_) async {},
        persistChat: () async => false,
        deleteJob: (_) async {
          deleted = true;
        },
      );
      expect(ok, isFalse);
      expect(deleted, isFalse);
    });

    test('awaitJobResult no longer deletes on read', () async {
      var deleted = false;
      final service = StylistChatService(
        jobConsumer: _consumer(
          watch: (_) => Stream<StylistJobRaw>.fromIterable([
            _doneRaw(reply: 'Z jobu.'),
          ]),
          delete: (_) async {
            deleted = true;
          },
        ),
      );
      final recovered = await service.awaitJobResult('job-live');
      expect(recovered?['reply'], 'Z jobu.');
      expect(recovered?['ok'], isTrue);
      expect(deleted, isFalse);
    });
  });

  group('hydration consumption', () {
    test('done job after cold start applies, persists, then deletes', () async {
      final messages = <StylistChatMessage>[
        const StylistChatMessage(text: 'Čo na svadbu?', isUser: true),
      ];
      var persisted = false;
      var deleted = false;

      final snapshot = await _consumer(
        watch: (_) => Stream<StylistJobRaw>.fromIterable([
          _doneRaw(reply: 'Biele tričko a sivé nohavice.', chatId: 'chat-9'),
        ]),
      ).watchForHydration('job-cold');

      final ok = await consumeCompletedJobSafely(
        snapshot: snapshot,
        apply: (response) async {
          messages.add(
            StylistChatMessage(
              text: (response['reply'] ?? '').toString(),
              isUser: false,
              suggestedItems:
                  (response['suggestedItems'] as List?)
                      ?.whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList(growable: false) ??
                  const [],
              sourceJobId: snapshot.jobId,
            ),
          );
        },
        persistChat: () async {
          persisted = messages.any((m) => m.sourceJobId == 'job-cold');
          return persisted;
        },
        deleteJob: (_) async {
          deleted = true;
        },
      );

      expect(ok, isTrue);
      expect(messages.where((m) => !m.isUser), hasLength(1));
      expect(messages.last.text, 'Biele tričko a sivé nohavice.');
      expect(messages.last.sourceJobId, 'job-cold');
      expect(persisted, isTrue);
      expect(deleted, isTrue);
      expect(
        resolveStylistHydrationChatId(
          intentChatId: 'chat-9',
          resultChatId: snapshot.response?['chatId']?.toString(),
        ),
        'chat-9',
      );
    });

    test('repeated tap with same jobId does not duplicate assistant reply', () {
      final messages = [
        const StylistChatMessage(text: 'Ahoj', isUser: true),
        const StylistChatMessage(
          text: 'Odpoveď.',
          isUser: false,
          sourceJobId: 'job-dup',
        ),
      ];
      expect(
        stylistChatAlreadyHasJobResult(
          sourceJobIds: messages.map((m) => m.sourceJobId),
          assistantTexts: messages.where((m) => !m.isUser).map((m) => m.text),
          jobId: 'job-dup',
          replyText: 'Odpoveď.',
        ),
        isTrue,
      );
    });

    test('empty chatId does not invent a thread id', () {
      expect(
        resolveStylistHydrationChatId(intentChatId: '', resultChatId: ''),
        isNull,
      );
    });
  });
}
