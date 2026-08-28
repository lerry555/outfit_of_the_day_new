import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_chat_outfit_service.dart';
import 'package:outfitofTheDay/Services/stylist_chat_service.dart';
import 'package:outfitofTheDay/data/event_dress_code.dart';
import 'package:outfitofTheDay/utils/stylist_occasion_guidance.dart';

void main() {
  group('Brain V1 public research context', () {
    test('fills missing public facts after a real web-search turn', () {
      final event = StylistChatService.resolvedEventContextFromData({
        'webResearch': {
          'used': true,
          'callCount': 1,
          'publicContext': {
            'performer': 'Example Band',
            'dressCode': {
              'formalityTarget': 3,
              'venueType': 'indoor_casual',
            },
            'durationMinutes': 180,
          },
        },
      });

      expect(event?['performer'], 'Example Band');
      expect(event?['durationMinutes'], 180);
      expect((event?['dressCode'] as Map)['venueType'], 'indoor_casual');
    });

    test('authoritative user/app event context always wins collisions', () {
      final event = StylistChatService.resolvedEventContextFromData({
        'eventContext': {
          'performer': 'User corrected performer',
          'hourLocal': 19,
          'dressCode': {
            'formalityTarget': 7,
            'venueType': 'indoor_formal',
          },
        },
        'webResearch': {
          'used': true,
          'publicContext': {
            'performer': 'Stale web performer',
            'hourLocal': 21,
            'dressCode': {
              'formalityTarget': 2,
              'venueType': 'outdoor',
            },
            'durationMinutes': 120,
          },
        },
      });

      expect(event?['performer'], 'User corrected performer');
      expect(event?['hourLocal'], 19);
      expect((event?['dressCode'] as Map)['formalityTarget'], 7);
      expect(event?['durationMinutes'], 120);
    });

    test('ignores publicContext when web search was not actually used', () {
      final event = StylistChatService.resolvedEventContextFromData({
        'webResearch': {
          'used': false,
          'publicContext': {
            'performer': 'Must not pass',
          },
        },
      });

      expect(event, isNull);
    });

    test('research reaches outfit event and occasion guidance', () {
      final raw = StylistChatService.resolvedEventContextFromData({
        'webResearch': {
          'used': true,
          'callCount': 1,
          'publicContext': {
            'performer': 'Example Band',
            'dressCode': {
              'id': 'arena_concert',
              'labelSk': 'koncert v hale',
              'formalityTarget': 3,
              'venueType': 'indoor_casual',
            },
            'eventStartHour': 20,
            'eventEndHour': 23,
            'durationMinutes': 180,
          },
        },
      });

      final event = StylistChatEventContext.fromDynamic(
        raw,
        now: DateTime(2026, 8, 28, 12),
      );
      final profile = StylistOccasionGuidance.profileFor(
        occasion: event.occasion,
        tempC: 20,
        dressCodeFromAi: event.dressCode,
      );

      expect(event.performer, 'Example Band');
      expect(event.eventStartHour, 20);
      expect(event.durationMinutes, 180);
      expect(profile.dressCode.id, 'arena_concert');
      expect(profile.dressCode.formalityTarget, 3);
      expect(profile.dressCode.venue.wireName, 'indoor_casual');
    });
  });
}
