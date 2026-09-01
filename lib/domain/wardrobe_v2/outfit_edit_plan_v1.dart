enum OutfitEditIntentV1 { none, createOutfit, editCurrentOutfit }

enum OutfitEditActionV1 { preserve, replace, add, remove }

enum OutfitEditSlotV1 {
  top,
  bottom,
  shoes,
  layers,
  outerwear,
  fullBody,
  accessories,
}

enum OutfitEditThermalV1 { warmer, cooler }

class OutfitEditConstraintsV1 {
  const OutfitEditConstraintsV1({
    this.family,
    this.type,
    this.color,
    this.excludedColor,
    this.thermal,
  });

  final String? family;
  final String? type;
  final String? color;
  final String? excludedColor;
  final OutfitEditThermalV1? thermal;

  bool get isEmpty =>
      family == null &&
      type == null &&
      color == null &&
      excludedColor == null &&
      thermal == null;

  Map<String, dynamic> toMap() => <String, dynamic>{
    if (family != null) 'family': family,
    if (type != null) 'type': type,
    if (color != null) 'color': color,
    if (excludedColor != null) 'excludedColor': excludedColor,
    if (thermal != null) 'thermal': thermal!.name,
  };

  static OutfitEditConstraintsV1? tryParse(Object? raw) {
    if (raw == null) return const OutfitEditConstraintsV1();
    if (raw is! Map) return null;
    const allowedKeys = <String>{
      'family',
      'type',
      'color',
      'excludedColor',
      'thermal',
    };
    if (raw.keys.any((key) => !allowedKeys.contains(key.toString()))) {
      return null;
    }
    ({String? value, bool valid}) token(String key) {
      final value = (raw[key] ?? '').toString().trim().toLowerCase();
      if (value.isEmpty || value == 'none') {
        return (value: null, valid: true);
      }
      final valid = value.codeUnits.every(
        (code) =>
            (code >= 97 && code <= 122) ||
            (code >= 48 && code <= 57) ||
            code == 45 ||
            code == 95,
      );
      return (value: valid ? value : null, valid: valid);
    }

    final family = token('family');
    final type = token('type');
    final color = token('color');
    final excludedColor = token('excludedColor');
    final thermalToken = token('thermal');
    if (![
      family,
      type,
      color,
      excludedColor,
      thermalToken,
    ].every((token) => token.valid)) {
      return null;
    }
    final thermal = switch (thermalToken.value) {
      'warmer' => OutfitEditThermalV1.warmer,
      'cooler' => OutfitEditThermalV1.cooler,
      null => null,
      _ => null,
    };
    if (thermalToken.value != null && thermal == null) return null;
    return OutfitEditConstraintsV1(
      family: family.value,
      type: type.value,
      color: color.value,
      excludedColor: excludedColor.value,
      thermal: thermal,
    );
  }
}

class OutfitEditOperationV1 {
  const OutfitEditOperationV1({
    required this.slot,
    required this.action,
    this.constraints = const OutfitEditConstraintsV1(),
  });

  final OutfitEditSlotV1 slot;
  final OutfitEditActionV1 action;
  final OutfitEditConstraintsV1 constraints;

  bool get mutates => action != OutfitEditActionV1.preserve;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'slot': _slotWireName(slot),
    'action': action.name,
    'constraints': constraints.toMap(),
  };

  static OutfitEditOperationV1? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final slot = _parseSlot((raw['slot'] ?? '').toString());
    final action = switch ((raw['action'] ?? '')
        .toString()
        .trim()
        .toLowerCase()) {
      'preserve' => OutfitEditActionV1.preserve,
      'replace' => OutfitEditActionV1.replace,
      'add' => OutfitEditActionV1.add,
      'remove' => OutfitEditActionV1.remove,
      _ => null,
    };
    final constraints = OutfitEditConstraintsV1.tryParse(raw['constraints']);
    if (slot == null || action == null || constraints == null) return null;
    if ((action == OutfitEditActionV1.preserve ||
            action == OutfitEditActionV1.remove) &&
        !constraints.isEmpty) {
      return null;
    }
    if (action == OutfitEditActionV1.add &&
        const <OutfitEditSlotV1>{
          OutfitEditSlotV1.top,
          OutfitEditSlotV1.bottom,
          OutfitEditSlotV1.shoes,
          OutfitEditSlotV1.fullBody,
        }.contains(slot)) {
      return null;
    }
    return OutfitEditOperationV1(
      slot: slot,
      action: action,
      constraints: constraints,
    );
  }
}

class OutfitEditPlanV1 {
  const OutfitEditPlanV1._({
    required this.intent,
    required this.operations,
    required this.presentation,
  });

  static const contractVersion = 'outfit_edit_plan_v1';
  static const _defaultPreservedSlots = <OutfitEditSlotV1>[
    OutfitEditSlotV1.top,
    OutfitEditSlotV1.bottom,
    OutfitEditSlotV1.shoes,
    OutfitEditSlotV1.layers,
    OutfitEditSlotV1.outerwear,
    OutfitEditSlotV1.fullBody,
    OutfitEditSlotV1.accessories,
  ];

  final OutfitEditIntentV1 intent;
  final List<OutfitEditOperationV1> operations;
  final String presentation;

  bool get mutatesCurrentOutfit =>
      intent == OutfitEditIntentV1.editCurrentOutfit &&
      operations.any((operation) => operation.mutates);

  OutfitEditOperationV1 operationFor(OutfitEditSlotV1 slot) =>
      operations.firstWhere((operation) => operation.slot == slot);

  Map<String, dynamic> toMap() => <String, dynamic>{
    'contractVersion': contractVersion,
    'intent': switch (intent) {
      OutfitEditIntentV1.none => 'none',
      OutfitEditIntentV1.createOutfit => 'create_outfit',
      OutfitEditIntentV1.editCurrentOutfit => 'edit_current_outfit',
    },
    'operations': operations
        .map((operation) => operation.toMap())
        .toList(growable: false),
    'presentation': presentation,
  };

  static OutfitEditPlanV1? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final version = (raw['contractVersion'] ?? '').toString().trim();
    if (version != contractVersion) return null;
    final intent = switch ((raw['intent'] ?? '')
        .toString()
        .trim()
        .toLowerCase()) {
      'none' => OutfitEditIntentV1.none,
      'create_outfit' => OutfitEditIntentV1.createOutfit,
      'edit_current_outfit' => OutfitEditIntentV1.editCurrentOutfit,
      _ => null,
    };
    if (intent == null) return null;
    final presentationRaw = (raw['presentation'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final presentation =
        const <String>{
          'normal',
          'concise_full',
          'focused_item',
        }.contains(presentationRaw)
        ? presentationRaw
        : intent == OutfitEditIntentV1.editCurrentOutfit
        ? 'concise_full'
        : 'normal';
    final rawOperations = raw['operations'];
    if (rawOperations is! List) return null;
    final parsed = <OutfitEditOperationV1>[];
    for (final rawOperation in rawOperations) {
      final operation = OutfitEditOperationV1.tryParse(rawOperation);
      if (operation == null ||
          parsed.any((existing) => existing.slot == operation.slot)) {
        return null;
      }
      parsed.add(operation);
    }
    if (intent != OutfitEditIntentV1.editCurrentOutfit) {
      if (parsed.isNotEmpty) return null;
      return OutfitEditPlanV1._(
        intent: intent,
        operations: const <OutfitEditOperationV1>[],
        presentation: presentation,
      );
    }
    for (final slot in _defaultPreservedSlots) {
      if (parsed.any((operation) => operation.slot == slot)) continue;
      parsed.add(
        OutfitEditOperationV1(slot: slot, action: OutfitEditActionV1.preserve),
      );
    }
    if (!parsed.any((operation) => operation.mutates)) return null;
    return OutfitEditPlanV1._(
      intent: intent,
      operations: List<OutfitEditOperationV1>.unmodifiable(parsed),
      presentation: presentation,
    );
  }
}

OutfitEditSlotV1? _parseSlot(String raw) => switch (raw.trim().toLowerCase()) {
  'top' => OutfitEditSlotV1.top,
  'bottom' => OutfitEditSlotV1.bottom,
  'shoes' => OutfitEditSlotV1.shoes,
  'layers' => OutfitEditSlotV1.layers,
  'outerwear' => OutfitEditSlotV1.outerwear,
  'full_body' => OutfitEditSlotV1.fullBody,
  'accessories' => OutfitEditSlotV1.accessories,
  _ => null,
};

String _slotWireName(OutfitEditSlotV1 slot) => switch (slot) {
  OutfitEditSlotV1.top => 'top',
  OutfitEditSlotV1.bottom => 'bottom',
  OutfitEditSlotV1.shoes => 'shoes',
  OutfitEditSlotV1.layers => 'layers',
  OutfitEditSlotV1.outerwear => 'outerwear',
  OutfitEditSlotV1.fullBody => 'full_body',
  OutfitEditSlotV1.accessories => 'accessories',
};
