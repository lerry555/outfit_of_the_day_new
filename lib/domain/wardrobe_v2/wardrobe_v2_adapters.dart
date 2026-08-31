import 'wardrobe_item_v2.dart';
import 'outfit_composition_v2.dart';
import 'wardrobe_set_v2.dart';

abstract final class WardrobeV2PersistenceMapper {
  static Map<String, dynamic> createPatch({
    required WardrobeItemV2 item,
    Map<String, dynamic> existing = const {},
  }) {
    final output = item.toMap();
    final overrides = item.userOverrideFields.toSet();
    for (final field in overrides) {
      if (existing.containsKey(field)) output[field] = existing[field];
    }
    return output;
  }

  static Map<String, dynamic> setMembershipPatch({
    required String setId,
    required String setType,
    String relationshipSource = 'manufacturer_matching',
  }) => {
    'setMembership': {
      'setId': setId,
      'setType': setType,
      'relationshipSource': relationshipSource,
      'authority': 'user_confirmation',
    },
  };
}

abstract final class StylistWardrobeV2Projection {
  static Map<String, dynamic> compact(String itemId, WardrobeItemV2 item) => {
    'itemId': itemId,
    'canonicalType': item.canonicalType,
    'canonicalFamily': item.canonicalFamily,
    'bodySlots': item.bodySlots,
    'layerPosition': item.layerPosition,
    'outfitFunctions': item.outfitFunctions,
    'colorProfile': item.colorProfile.toMap(),
    'formality': item.formality,
    'styles': item.styles,
    'occasionFit': item.occasionFit,
    'warmth': item.warmth,
    'attributes': item.attributes,
    'metalTone': item.colorProfile.metalTone,
    'hardwareTone': item.colorProfile.hardwareTone,
    'setMembership': item.setMembership?.toMap(),
  };
}

abstract final class WardrobeCapabilityQueryV2 {
  static Iterable<WardrobeItemV2> weatherProtection(
    Iterable<WardrobeItemV2> items,
  ) => items.where(
    (x) => x.layerPosition == 'outer' || x.layerPosition == 'shell',
  );

  static Iterable<WardrobeItemV2> carriedItems(
    Iterable<WardrobeItemV2> items,
  ) => items.where(
    (x) => x.bodySlots.any(
      const {'carried', 'shoulder_carried', 'back_carried'}.contains,
    ),
  );

  static Iterable<WardrobeItemV2> reusableCore(
    Iterable<WardrobeItemV2> items,
  ) => items.where(
    (x) =>
        x.bodySlots.any(
          const {'upper_body', 'lower_body', 'full_body', 'feet'}.contains,
        ) &&
        !x.userOverrideFields.contains('unavailable'),
  );
}

class FlexibleOutfitItemV2 {
  const FlexibleOutfitItemV2({
    required this.itemId,
    required this.compositionGroup,
    required this.compositionRole,
    required this.requiredness,
    required this.selectionReason,
  });
  final String itemId;
  final String compositionGroup;
  final String compositionRole;
  final String requiredness;
  final String selectionReason;
  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'compositionGroup': compositionGroup,
    'compositionRole': compositionRole,
    'requiredness': requiredness,
    'selectionReason': selectionReason,
  };
}

class CalendarOutfitV2Payload {
  const CalendarOutfitV2Payload({required this.template, required this.items});
  final String template;
  final List<FlexibleOutfitItemV2> items;
  Map<String, dynamic> toMap() => {
    'ontologyVersion': '2.0.0',
    'template': template,
    'outfitItems': items.map((x) => x.toMap()).toList(),
  };
}

abstract final class OutfitCompositionPersistenceV2 {
  static Map<String, dynamic> item(OutfitCompositionItemV2 value) => {
    'itemId': value.itemId,
    'canonicalType': value.item.canonicalType,
    'compositionRole': value.role.name,
    'compositionGroup': value.compositionGroup,
    'requiredness': value.required ? 'required' : 'optional',
    'selectionReason': value.selectionReason,
    if (value.item.setMembership case final set?) ...{
      'setId': set.setId,
      'setType': set.setType,
    },
  };

  static Map<String, dynamic> outfit(OutfitCompositionV2 value) => {
    'ontologyVersion': '2.0.0',
    'template': value.template == OutfitTemplateV2.onePiece
        ? 'one_piece'
        : 'separates',
    'outfitItems': value.items.map(item).toList(growable: false),
  };
}

abstract final class SwapCandidateSelectorV2 {
  static Iterable<WardrobeItemV2> compatible({
    required WardrobeItemV2 replaced,
    required Iterable<WardrobeItemV2> candidates,
    String? compositionGroup,
    int? minimumFormality,
    Set<String> requiredOccasions = const {},
    Set<String> requiredFunctions = const {},
    Iterable<WardrobeItemV2> remainingOutfit = const [],
    bool allowCrossFamilySameSlot = false,
  }) => candidates.where((candidate) {
    if (minimumFormality != null && candidate.formality < minimumFormality) {
      return false;
    }
    if (requiredOccasions.isNotEmpty &&
        candidate.occasionFit.toSet().intersection(requiredOccasions).isEmpty) {
      return false;
    }
    if (requiredFunctions.isNotEmpty &&
        candidate.outfitFunctions
            .toSet()
            .intersection(requiredFunctions)
            .isEmpty) {
      return false;
    }
    if (candidate.canonicalType == replaced.canonicalType) return true;
    final sharesBodySlot = candidate.bodySlots
        .toSet()
        .intersection(replaced.bodySlots.toSet())
        .isNotEmpty;
    if (!sharesBodySlot) return false;
    if (candidate.canonicalFamily != replaced.canonicalFamily &&
        !allowCrossFamilySameSlot) {
      return false;
    }
    if (candidate.accessoryGroup != replaced.accessoryGroup) return false;
    if (candidate.layerPosition != replaced.layerPosition &&
        candidate.layerPosition != 'not_applicable') {
      return false;
    }
    final group = candidate.accessoryGroup;
    if (group != null &&
        remainingOutfit.any((item) => item.accessoryGroup == group)) {
      return false;
    }
    return true;
  });
}

abstract final class WardrobeSearchProjectionV2 {
  static Set<String> tokens(WardrobeItemV2 item) => {
    item.canonicalType,
    item.canonicalFamily,
    ...item.styles,
    ...item.occasionFit,
    item.colorProfile.primary.family,
    if (item.colorProfile.secondary case final color?) color.family,
    ...item.colorProfile.accents.map((x) => x.family),
    if (item.colorProfile.metalTone != 'none') item.colorProfile.metalTone,
    if (item.colorProfile.hardwareTone != 'none')
      item.colorProfile.hardwareTone,
    ...item.attributes.values.expand(
      (value) =>
          value is List ? value.map((x) => x.toString()) : [value.toString()],
    ),
    if (item.setMembership case final set?) ...{
      set.setType,
      WardrobeSetTypeV2.parse(set.setType).labelSk,
      set.relationshipSource,
      WardrobeSetRelationshipSourceV2.parse(set.relationshipSource).labelSk,
      if (set.displayName != null) set.displayName!,
      'set',
      'súprava',
    },
  }.where((x) => x.isNotEmpty).toSet();
}
