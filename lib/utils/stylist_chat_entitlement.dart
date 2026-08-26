enum StylistChatEntitlement { unknown, free, premium }

abstract final class StylistChatEntitlementPolicy {
  static StylistChatEntitlement fromUserDocument(Map<String, dynamic>? data) {
    final status = (data?['subscriptionStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (data?['isPremium'] == true || status == 'premium') {
      return StylistChatEntitlement.premium;
    }
    // A successfully resolved user document is authoritative FREE unless it
    // positively says Premium. Loading and read failures never reach here.
    return StylistChatEntitlement.free;
  }

  static bool blocksMessage({
    required StylistChatEntitlement entitlement,
    required int userMessageCount,
    required int freeMessageLimit,
  }) {
    return entitlement == StylistChatEntitlement.free &&
        userMessageCount >= freeMessageLimit;
  }
}
