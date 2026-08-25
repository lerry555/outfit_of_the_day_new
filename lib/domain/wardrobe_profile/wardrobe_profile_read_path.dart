import '../../utils/home_wardrobe_read_path.dart';
import '../../utils/home_wardrobe_normalizer.dart';

typedef WardrobeProfileLegacyNormalizer = HomeLegacyWardrobeNormalizer;
typedef WardrobeProfileItemProjector = HomeResolvedItemProjector;
typedef ResolvedWardrobeProjection = HomeResolvedWardrobeItem;
typedef WardrobeProfileReadPathResult = HomeWardrobeReadPathResult;

/// Shared entry point for consumers adopting the M11 wardrobe pipeline.
///
/// This delegates to the single established implementation used by Home so
/// Chat cannot accidentally create a second resolver, KB provider, precedence
/// policy, or compatibility fallback policy.
final class WardrobeProfileReadPath {
  const WardrobeProfileReadPath({
    required this.useResolvedProfiles,
    this.legacyNormalizer,
    this.itemProjector,
  });

  final bool useResolvedProfiles;
  final WardrobeProfileLegacyNormalizer? legacyNormalizer;
  final WardrobeProfileItemProjector? itemProjector;

  WardrobeProfileReadPathResult build(List<Map<String, dynamic>> rawItems) {
    return HomeWardrobeReadPath(
      useResolvedProfiles: useResolvedProfiles,
      legacyNormalizer:
          legacyNormalizer ?? HomeWardrobeNormalizer.normalizeWardrobeForHome,
      itemProjector: itemProjector,
    ).build(rawItems);
  }
}
