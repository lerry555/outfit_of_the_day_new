import 'outfit_composition_v2.dart';
import 'wardrobe_item_v2.dart';

class V2FlexibleOutfitItem {
  const V2FlexibleOutfitItem({
    required this.itemId,
    required this.item,
    required this.compositionRole,
    required this.compositionGroup,
    required this.requiredness,
    required this.selectionReason,
    this.display = const {},
  });

  final String itemId, compositionGroup, requiredness, selectionReason;
  final WardrobeItemV2 item;
  final CompositionRoleV2 compositionRole;
  final Map<String, dynamic> display;

  Map<String, dynamic> toMap() => {
    'itemId': itemId,
    'canonicalType': item.canonicalType,
    'canonicalFamily': item.canonicalFamily,
    'bodySlots': item.bodySlots,
    'layerPosition': item.layerPosition,
    'compositionRole': compositionRole.name,
    'compositionGroup': compositionGroup,
    'requiredness': requiredness,
    'selectionReason': selectionReason,
    'resolvedItem': item.toMap(),
    if (display.isNotEmpty) 'display': display,
  };

  factory V2FlexibleOutfitItem.fromMap(Map<String, dynamic> map) {
    final roleName = (map['compositionRole'] ?? '').toString();
    return V2FlexibleOutfitItem(
      itemId: (map['itemId'] ?? '').toString(),
      item: WardrobeItemV2.fromMap(
        Map<String, dynamic>.from(map['resolvedItem'] as Map),
      ),
      compositionRole: CompositionRoleV2.values.firstWhere(
        (value) => value.name == roleName,
        orElse: () => CompositionRoleV2.core,
      ),
      compositionGroup: (map['compositionGroup'] ?? '').toString(),
      requiredness: (map['requiredness'] ?? 'optional').toString(),
      selectionReason: (map['selectionReason'] ?? '').toString(),
      display: map['display'] is Map
          ? Map<String, dynamic>.from(map['display'] as Map)
          : const {},
    );
  }
}

/// Canonical runtime outfit result. Legacy previews may only be derived from
/// this value for display/historical compatibility.
class V2FlexibleOutfitResult {
  const V2FlexibleOutfitResult({
    required this.template,
    required this.items,
    required this.completeness,
  });

  final OutfitTemplateV2 template;
  final List<V2FlexibleOutfitItem> items;
  final OutfitCompletenessV2 completeness;

  factory V2FlexibleOutfitResult.fromComposition(
    OutfitCompositionV2 composition, {
    required bool weatherProtectionRequired,
    required int minimumFormality,
    Set<String> requiredFunctions = const {},
    Map<String, Map<String, dynamic>> displayByItemId = const {},
  }) => V2FlexibleOutfitResult(
    template: composition.template,
    items: composition.items
        .map(
          (value) => V2FlexibleOutfitItem(
            itemId: value.itemId,
            item: value.item,
            compositionRole: value.role,
            compositionGroup: value.compositionGroup,
            requiredness: value.required ? 'required' : 'optional',
            selectionReason: value.selectionReason,
            display: displayByItemId[value.itemId] ?? const {},
          ),
        )
        .toList(growable: false),
    completeness: composition.completeness(
      weatherProtectionRequired: weatherProtectionRequired,
      minimumFormality: minimumFormality,
      requiredFunctions: requiredFunctions,
    ),
  );

  OutfitCompositionV2 toComposition() => OutfitCompositionV2(
    template: template,
    items: items
        .map(
          (value) => OutfitCompositionItemV2(
            itemId: value.itemId,
            item: value.item,
            role: value.compositionRole,
            compositionGroup: value.compositionGroup,
            required: value.requiredness == 'required',
            selectionReason: value.selectionReason,
          ),
        )
        .toList(growable: false),
  );

  List<String> validate() {
    final errors = toComposition().compatibilityErrors();
    if (!completeness.coreComplete) errors.add('core_incomplete');
    if (items.map((x) => x.itemId).toSet().length != items.length) {
      errors.add('duplicate_item');
    }
    return errors;
  }

  V2FlexibleOutfitResult replaceItem({
    required String itemId,
    required String replacementId,
    required WardrobeItemV2 replacement,
    Map<String, dynamic> display = const {},
  }) {
    final next = items
        .map(
          (value) => value.itemId != itemId
              ? value
              : V2FlexibleOutfitItem(
                  itemId: replacementId,
                  item: replacement,
                  compositionRole: value.compositionRole,
                  compositionGroup: value.compositionGroup,
                  requiredness: value.requiredness,
                  selectionReason: 'composition_swap',
                  display: display,
                ),
        )
        .toList(growable: false);
    final composition = OutfitCompositionV2(
      template: template,
      items: next
          .map(
            (value) => OutfitCompositionItemV2(
              itemId: value.itemId,
              item: value.item,
              role: value.compositionRole,
              compositionGroup: value.compositionGroup,
              required: value.requiredness == 'required',
              selectionReason: value.selectionReason,
            ),
          )
          .toList(growable: false),
    );
    final result = V2FlexibleOutfitResult.fromComposition(
      composition,
      weatherProtectionRequired: !completeness.weatherComplete,
      minimumFormality: 1,
      displayByItemId: {for (final value in next) value.itemId: value.display},
    );
    if (result.validate().isNotEmpty) throw StateError('invalid_v2_swap');
    return result;
  }

  Map<String, dynamic> toMap() => {
    'contractVersion': 'v2-flexible-outfit-1',
    'ontologyVersion': '2.0.0',
    'template': template == OutfitTemplateV2.onePiece
        ? 'one_piece'
        : 'separates',
    'items': items.map((value) => value.toMap()).toList(growable: false),
    'coreComplete': completeness.coreComplete,
    'weatherComplete': completeness.weatherComplete,
    'dressCodeComplete': completeness.dressCodeComplete,
    'functionalComplete': completeness.functionalComplete,
    'enhanced': completeness.enhanced,
    'gaps': completeness.gaps,
  };

  factory V2FlexibleOutfitResult.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List? ?? const [];
    return V2FlexibleOutfitResult(
      template: map['template'] == 'one_piece'
          ? OutfitTemplateV2.onePiece
          : OutfitTemplateV2.separates,
      items: rawItems
          .whereType<Map>()
          .map(
            (value) =>
                V2FlexibleOutfitItem.fromMap(Map<String, dynamic>.from(value)),
          )
          .toList(growable: false),
      completeness: OutfitCompletenessV2(
        coreComplete: map['coreComplete'] == true,
        weatherComplete: map['weatherComplete'] == true,
        dressCodeComplete: map['dressCodeComplete'] == true,
        functionalComplete: map['functionalComplete'] == true,
        enhanced: map['enhanced'] == true,
        gaps: List<String>.from(map['gaps'] as List? ?? const []),
      ),
    );
  }
}
