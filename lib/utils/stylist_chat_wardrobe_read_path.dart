import 'package:flutter/foundation.dart';

import '../domain/wardrobe_profile/wardrobe_profile_read_path.dart';
import 'home_debug_logging.dart';
import 'home_wardrobe_normalizer.dart';

typedef ChatLegacyWardrobeNormalizer =
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> rawItems);

/// Chat-facing entry point to the same M11 read-path used by Home.
///
/// The class owns no classification or resolution policy. It selects between
/// the unchanged legacy Chat projection and the shared resolved pipeline.
final class StylistChatWardrobeReadPath {
  const StylistChatWardrobeReadPath({
    this.useResolvedProfiles = kUseResolvedWardrobeProfilesInChat,
    this.legacyNormalizer = _legacyChatNormalizer,
    this.itemProjector,
  });

  final bool useResolvedProfiles;
  final ChatLegacyWardrobeNormalizer legacyNormalizer;
  final WardrobeProfileItemProjector? itemProjector;

  WardrobeProfileReadPathResult build(List<Map<String, dynamic>> rawItems) {
    final result = WardrobeProfileReadPath(
      useResolvedProfiles: useResolvedProfiles,
      legacyNormalizer: legacyNormalizer,
      itemProjector: itemProjector,
    ).build(rawItems);
    if (kDebugMode) debugPrint(_logLine(result, rawItems.length));
    return result;
  }

  static String _logLine(
    WardrobeProfileReadPathResult result,
    int rawItemCount,
  ) =>
      '[M11_CHAT_READ_PATH] enabled=${result.usedResolvedProfiles} '
      'wholeFallback=${result.wholePipelineFallback} rawItems=$rawItemCount '
      'items=${result.items.length} '
      'resolvedWithoutFallback=${result.resolvedWithoutFallback} '
      'compatibilityFallbackItems=${result.compatibilityFallbackItems} '
      'canonicalUnknownItems=${result.canonicalUnknownItems} '
      'fallbackProperties=${result.fallbackProperties} '
      'signature=${result.wardrobeSignature}';

  static List<Map<String, dynamic>> _legacyChatNormalizer(
    List<Map<String, dynamic>> rawItems,
  ) => HomeWardrobeNormalizer.normalizeWardrobeForHome(rawItems, log: false);
}
