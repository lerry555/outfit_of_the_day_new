import 'wardrobe_item_v2.dart';
import 'wardrobe_ontology_v2.dart';

class WardrobeV2DataQualityException implements Exception {
  const WardrobeV2DataQualityException(this.itemId, this.errors);
  final String itemId;
  final List<String> errors;
  @override
  String toString() =>
      'WardrobeV2DataQualityException($itemId: ${errors.join(',')})';
}

class ResolvedWardrobeItemV2 {
  const ResolvedWardrobeItemV2({
    required this.itemId,
    required this.item,
    required this.raw,
  });
  final String itemId;
  final WardrobeItemV2 item;
  final Map<String, dynamic> raw;
}

/// The only V2 Firestore-document parser. It never infers identity from legacy
/// names/categories. Compatibility callers may catch the typed exception and
/// explicitly account for fallback use in telemetry.
class WardrobeV2Resolver {
  const WardrobeV2Resolver(this.ontology);
  final WardrobeOntologyV2 ontology;

  ResolvedWardrobeItemV2 resolve(String itemId, Map<String, dynamic> document) {
    final errors = <String>[];
    WardrobeItemV2? item;
    try {
      item = WardrobeItemV2.fromMap(document);
    } catch (_) {
      errors.add('document.decode_failed');
    }
    if (item != null) {
      errors.addAll(WardrobeItemV2Validator(ontology).validate(item));
    }
    if (itemId.trim().isEmpty) errors.add('itemId.required');
    if (errors.isNotEmpty || item == null) {
      throw WardrobeV2DataQualityException(itemId, List.unmodifiable(errors));
    }
    return ResolvedWardrobeItemV2(
      itemId: itemId,
      item: item,
      raw: Map<String, dynamic>.unmodifiable(document),
    );
  }
}

class WardrobeV2Telemetry {
  int parseSuccess = 0;
  int parseFailure = 0;
  int legacyFallbackUse = 0;
  int invalidCompositionPrevented = 0;
  final Map<String, int> missingRequiredFields = {};

  void resolved() => parseSuccess++;
  void failed(WardrobeV2DataQualityException error) {
    parseFailure++;
    for (final field in error.errors) {
      missingRequiredFields.update(field, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  Map<String, dynamic> snapshot() => {
    'v2ParseSuccess': parseSuccess,
    'v2ParseFailure': parseFailure,
    'legacyFallbackUse': legacyFallbackUse,
    'invalidCompositionPrevented': invalidCompositionPrevented,
    'missingRequiredFields': Map<String, int>.from(missingRequiredFields),
  };
}
