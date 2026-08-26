import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/utils/stylist_chat_entitlement.dart';

void main() {
  group('Stylist chat entitlement', () {
    test('premium resolves positively from either authoritative field', () {
      expect(
        StylistChatEntitlementPolicy.fromUserDocument(const {
          'subscriptionStatus': 'premium',
        }),
        StylistChatEntitlement.premium,
      );
      expect(
        StylistChatEntitlementPolicy.fromUserDocument(const {
          'isPremium': true,
        }),
        StylistChatEntitlement.premium,
      );
    });

    test('loading or failed entitlement never behaves as free', () {
      expect(
        StylistChatEntitlementPolicy.blocksMessage(
          entitlement: StylistChatEntitlement.unknown,
          userMessageCount: 99,
          freeMessageLimit: 3,
        ),
        isFalse,
      );
    });

    test('premium continues beyond three messages', () {
      expect(
        StylistChatEntitlementPolicy.blocksMessage(
          entitlement: StylistChatEntitlement.premium,
          userMessageCount: 4,
          freeMessageLimit: 3,
        ),
        isFalse,
      );
    });

    test('resolved free is blocked at the limit and not before it', () {
      expect(
        StylistChatEntitlementPolicy.blocksMessage(
          entitlement: StylistChatEntitlement.free,
          userMessageCount: 2,
          freeMessageLimit: 3,
        ),
        isFalse,
      );
      expect(
        StylistChatEntitlementPolicy.blocksMessage(
          entitlement: StylistChatEntitlement.free,
          userMessageCount: 3,
          freeMessageLimit: 3,
        ),
        isTrue,
      );
    });

    test('fresh resolved snapshots recover premium after restore or login', () {
      final restored = StylistChatEntitlementPolicy.fromUserDocument(const {
        'subscriptionStatus': 'free',
        'isPremium': false,
      });
      final refreshed = StylistChatEntitlementPolicy.fromUserDocument(const {
        'subscriptionStatus': 'premium',
        'isPremium': true,
      });
      expect(restored, StylistChatEntitlement.free);
      expect(refreshed, StylistChatEntitlement.premium);
    });
  });
}
