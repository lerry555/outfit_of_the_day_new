import '../domain/wardrobe_v2/native_outfit_engine_v2.dart';
import '../domain/wardrobe_v2/outfit_composition_v2.dart';
import '../domain/wardrobe_v2/flexible_outfit_result_v2.dart';
import '../domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import '../domain/wardrobe_v2/wardrobe_v2_resolver.dart';

/// Strict production boundary shared by downstream wardrobe consumers.
/// Decisions are made exclusively from validated V2 documents.
abstract final class NativeWardrobeV2Runtime {
  static List<ResolvedWardrobeItemV2> resolveAll(
    Iterable<Map<String, dynamic>> documents, {
    WardrobeV2Telemetry? telemetry,
    WardrobeOntologyV2? ontology,
  }) {
    final activeOntology = ontology ?? WardrobeOntologyV2.cached;
    if (activeOntology == null) throw StateError('wardrobe_v2_not_preloaded');
    final resolver = WardrobeV2Resolver(activeOntology);
    final resolved = <ResolvedWardrobeItemV2>[];
    for (final document in documents) {
      final id = (document['id'] ?? document['documentId'] ?? '')
          .toString()
          .trim();
      try {
        resolved.add(resolver.resolve(id, document));
        telemetry?.resolved();
      } on WardrobeV2DataQualityException catch (error) {
        telemetry?.failed(error);
      }
    }
    return List.unmodifiable(resolved);
  }

  static OutfitCompositionV2? compose({
    required Iterable<Map<String, dynamic>> documents,
    required NativeOutfitRequestV2 request,
    WardrobeV2Telemetry? telemetry,
    WardrobeOntologyV2? ontology,
  }) {
    final result = NativeOutfitEngineV2.compose(
      resolveAll(documents, telemetry: telemetry, ontology: ontology),
      request,
    );
    if (result == null) telemetry?.invalidCompositionPrevented++;
    return result;
  }

  static V2FlexibleOutfitResult? recommend({
    required Iterable<Map<String, dynamic>> documents,
    required NativeOutfitRequestV2 request,
    WardrobeV2Telemetry? telemetry,
    WardrobeOntologyV2? ontology,
  }) {
    final resolved = resolveAll(
      documents,
      telemetry: telemetry,
      ontology: ontology,
    );
    final composition = NativeOutfitEngineV2.compose(resolved, request);
    if (composition == null) {
      telemetry?.invalidCompositionPrevented++;
      return null;
    }
    final byId = {for (final value in resolved) value.itemId: value.raw};
    return V2FlexibleOutfitResult.fromComposition(
      composition,
      weatherProtectionRequired: request.weatherProtectionRequired,
      minimumFormality: request.minimumFormality,
      requiredFunctions: request.requiredFunctions,
      displayByItemId: byId,
    );
  }
}
