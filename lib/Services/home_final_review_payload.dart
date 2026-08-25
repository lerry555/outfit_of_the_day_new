import 'dart:convert';

import '../domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import '../domain/wardrobe_v2/flexible_outfit_result_v2.dart';

/// Compact final-review wire contract. Omits display docs, image URLs,
/// analyzer provenance, and other fields the reviewer does not need.
abstract final class HomeFinalReviewPayload {
  static const int maxCandidates = 4;

  static List<Map<String, dynamic>> fromCandidates(
    List<V2FlexibleCandidate> candidates, {
    int limit = maxCandidates,
  }) {
    final sliced = candidates.take(limit).toList(growable: false);
    return [
      for (var i = 0; i < sliced.length; i++)
        _candidateMap(sliced[i], candidateIndex: i),
    ];
  }

  static int utf8ByteLength(Object payload) =>
      utf8.encode(jsonEncode(payload)).length;

  static bool isCompact(Map<String, dynamic> candidate) {
    if (candidate.containsKey('display')) return false;
    if (candidate.containsKey('resolvedItem')) return false;
    final items = candidate['items'];
    if (items is! List) return false;
    for (final item in items) {
      if (item is! Map) return false;
      if (item.containsKey('display') || item.containsKey('resolvedItem')) {
        return false;
      }
      final image = (item['imageUrl'] ?? '').toString();
      if (image.isNotEmpty) return false;
    }
    return true;
  }

  static Map<String, dynamic> _candidateMap(
    V2FlexibleCandidate candidate, {
    required int candidateIndex,
  }) {
    return <String, dynamic>{
      'candidateId': candidate.candidateId,
      'candidateIndex': candidateIndex,
      'template': candidate.outfit.template.name,
      'ruleScore': candidate.score,
      'scoreBreakdown': candidate.scoreBreakdown,
      'completeness': <String, dynamic>{
        'coreComplete': candidate.outfit.completeness.coreComplete,
        'weatherComplete': candidate.outfit.completeness.weatherComplete,
        'dressCodeComplete': candidate.outfit.completeness.dressCodeComplete,
        'functionalComplete': candidate.outfit.completeness.functionalComplete,
        'enhanced': candidate.outfit.completeness.enhanced,
      },
      'items': candidate.outfit.items
          .map(_itemMap)
          .toList(growable: false),
    };
  }

  static Map<String, dynamic> _itemMap(V2FlexibleOutfitItem value) {
    final item = value.item;
    final set = item.setMembership;
    return <String, dynamic>{
      'id': value.itemId,
      'itemId': value.itemId,
      'canonicalType': item.canonicalType,
      'canonicalFamily': item.canonicalFamily,
      'bodySlots': item.bodySlots,
      'layerPosition': item.layerPosition,
      'compositionRole': value.compositionRole.name,
      'compositionGroup': value.compositionGroup,
      'requiredness': value.requiredness,
      'formality': item.formality,
      'warmth': item.warmth,
      'styles': item.styles.take(4).toList(growable: false),
      'occasionFit': item.occasionFit.take(4).toList(growable: false),
      'seasons': item.seasons.take(4).toList(growable: false),
      'primaryColorFamily': item.colorProfile.primary.family,
      if (item.colorProfile.secondary != null)
        'secondaryColorFamily': item.colorProfile.secondary!.family,
      if (set != null)
        'setMembership': <String, dynamic>{
          'setId': set.setId,
          'setType': set.setType,
          'relationshipSource': set.relationshipSource,
        },
    };
  }
}
