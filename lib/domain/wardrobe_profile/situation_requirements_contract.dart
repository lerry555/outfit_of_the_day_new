import 'wardrobe_profile_contract.dart';

enum RequirementCriticality {
  preference,
  softRequirement,
  hardRequirement,
  safetyCritical;

  String get wireName => switch (this) {
    RequirementCriticality.preference => 'preference',
    RequirementCriticality.softRequirement => 'soft_requirement',
    RequirementCriticality.hardRequirement => 'hard_requirement',
    RequirementCriticality.safetyCritical => 'safety_critical',
  };

  static RequirementCriticality fromWireName(String value) =>
      RequirementCriticality.values.firstWhere(
        (criticality) => criticality.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown requirement criticality',
        ),
      );
}

class SituationRequirement<T> {
  const SituationRequirement({
    required this.value,
    this.criticality = RequirementCriticality.softRequirement,
  });

  final T value;
  final RequirementCriticality criticality;

  Map<String, Object?> toMap(Object? Function(T value) encodeValue) =>
      <String, Object?>{
        'value': encodeValue(value),
        'criticality': criticality.wireName,
      };

  factory SituationRequirement.fromMap(
    Map<String, dynamic> map, {
    required T Function(Object? value) decodeValue,
  }) {
    if (!map.containsKey('value')) {
      throw const FormatException('Situation requirement value is missing');
    }
    return SituationRequirement<T>(
      value: decodeValue(map['value']),
      criticality: RequirementCriticality.fromWireName(
        map['criticality']?.toString() ?? '',
      ),
    );
  }
}

class FormalityRange {
  const FormalityRange({required this.minimum, required this.maximum})
    : assert(minimum >= 1 && minimum <= 10),
      assert(maximum >= 1 && maximum <= 10),
      assert(minimum <= maximum);

  final int minimum;
  final int maximum;

  Map<String, Object?> toMap() => <String, Object?>{
    'minimum': minimum,
    'maximum': maximum,
  };

  factory FormalityRange.fromMap(Map<String, dynamic> map) {
    final minimum = map['minimum'];
    final maximum = map['maximum'];
    if (minimum is! int ||
        maximum is! int ||
        minimum < 1 ||
        maximum > 10 ||
        minimum > maximum) {
      throw const FormatException('Invalid formality range');
    }
    return FormalityRange(minimum: minimum, maximum: maximum);
  }
}

/// Runtime-only language between future Situation Intelligence and matcher.
///
/// A null field means that the situation makes no requirement on that axis.
/// This contract intentionally contains no activity-specific fields.
class SituationRequirements {
  const SituationRequirements({
    this.thermal,
    this.breathability,
    this.mobility,
    this.windProtection,
    this.rainProtection,
    this.formality,
    this.layerRoles,
    this.walkingDemand,
    this.tractionDemand,
    this.coverageDemand,
  });

  final SituationRequirement<CapabilityLevel>? thermal;
  final SituationRequirement<CapabilityLevel>? breathability;
  final SituationRequirement<CapabilityLevel>? mobility;
  final SituationRequirement<CapabilityLevel>? windProtection;
  final SituationRequirement<CapabilityLevel>? rainProtection;
  final SituationRequirement<FormalityRange>? formality;
  final SituationRequirement<Set<WardrobeLayerRole>>? layerRoles;
  final SituationRequirement<CapabilityLevel>? walkingDemand;
  final SituationRequirement<CapabilityLevel>? tractionDemand;
  final SituationRequirement<GarmentCoverage>? coverageDemand;

  Map<String, Object?> toMap() => <String, Object?>{
    'contractVersion': WardrobeProfileVersions.situationRequirementsContract,
    if (thermal != null) 'thermal': thermal!.toMap((value) => value.wireName),
    if (breathability != null)
      'breathability': breathability!.toMap((value) => value.wireName),
    if (mobility != null)
      'mobility': mobility!.toMap((value) => value.wireName),
    if (windProtection != null)
      'windProtection': windProtection!.toMap((value) => value.wireName),
    if (rainProtection != null)
      'rainProtection': rainProtection!.toMap((value) => value.wireName),
    if (formality != null)
      'formality': formality!.toMap((value) => value.toMap()),
    if (layerRoles != null)
      'layerRoles': layerRoles!.toMap(
        (value) => (value.map((role) => role.wireName).toList()..sort()),
      ),
    if (walkingDemand != null)
      'walkingDemand': walkingDemand!.toMap((value) => value.wireName),
    if (tractionDemand != null)
      'tractionDemand': tractionDemand!.toMap((value) => value.wireName),
    if (coverageDemand != null)
      'coverageDemand': coverageDemand!.toMap((value) => value.wireName),
  };

  factory SituationRequirements.fromMap(Map<String, dynamic> map) =>
      SituationRequirements(
        thermal: _levelRequirement(map['thermal']),
        breathability: _levelRequirement(map['breathability']),
        mobility: _levelRequirement(map['mobility']),
        windProtection: _levelRequirement(map['windProtection']),
        rainProtection: _levelRequirement(map['rainProtection']),
        formality: _requirement<FormalityRange>(
          map['formality'],
          (value) => FormalityRange.fromMap(_map(value)),
        ),
        layerRoles: _requirement<Set<WardrobeLayerRole>>(map['layerRoles'], (
          value,
        ) {
          if (value is! List) {
            throw const FormatException('Invalid layer roles');
          }
          final roles = value
              .map((item) => WardrobeLayerRole.fromWireName(item.toString()))
              .toSet();
          if (roles.isEmpty || roles.contains(WardrobeLayerRole.unknown)) {
            throw const FormatException('Invalid layer roles');
          }
          return Set<WardrobeLayerRole>.unmodifiable(roles);
        }),
        walkingDemand: _levelRequirement(map['walkingDemand']),
        tractionDemand: _levelRequirement(map['tractionDemand']),
        coverageDemand: _requirement<GarmentCoverage>(
          map['coverageDemand'],
          (value) => GarmentCoverage.fromWireName(value.toString()),
        ),
      );

  static SituationRequirement<CapabilityLevel>? _levelRequirement(
    Object? value,
  ) => _requirement<CapabilityLevel>(
    value,
    (raw) => CapabilityLevel.fromWireName(raw.toString()),
  );

  static SituationRequirement<T>? _requirement<T>(
    Object? value,
    T Function(Object? value) decodeValue,
  ) {
    if (value == null) return null;
    return SituationRequirement<T>.fromMap(
      _map(value),
      decodeValue: decodeValue,
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) throw const FormatException('Expected a map');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}
