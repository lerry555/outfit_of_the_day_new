import 'package:flutter/material.dart';

enum WardrobeSetTypeV2 {
  suit,
  tracksuit,
  matchingSet,
  pajamaSet,
  swimSet,
  underwearSet,
  accessorySet,
  other;

  String get wireName => switch (this) {
    matchingSet => 'matching_set',
    pajamaSet => 'pajama_set',
    swimSet => 'swim_set',
    underwearSet => 'underwear_set',
    accessorySet => 'accessory_set',
    _ => name,
  };

  String get labelSk => switch (this) {
    suit => 'Oblek',
    tracksuit => 'Tepláková súprava',
    matchingSet => 'Zladený set',
    pajamaSet => 'Pyžamový set',
    swimSet => 'Plavkový set',
    underwearSet => 'Set spodnej bielizne',
    accessorySet => 'Set doplnkov',
    other => 'Iný set',
  };

  static WardrobeSetTypeV2 parse(String? value) =>
      values.firstWhere((item) => item.wireName == value, orElse: () => other);
}

enum WardrobeSetRelationshipSourceV2 {
  manufacturerMatching,
  userCurated;

  String get wireName => switch (this) {
    manufacturerMatching => 'manufacturer_matching',
    userCurated => 'user_curated',
  };

  String get labelSk => switch (this) {
    manufacturerMatching => 'Pôvodná zladená súprava',
    userCurated => 'Moja obľúbená kombinácia',
  };

  static WardrobeSetRelationshipSourceV2 parse(String? value) => values
      .firstWhere((item) => item.wireName == value, orElse: () => userCurated);
}

enum WardrobeSetLifecycleV2 { active, dissolved }

class WardrobeSetV2 {
  const WardrobeSetV2({
    required this.setId,
    required this.setType,
    required this.relationshipSource,
    required this.memberIds,
    required this.generatedLabel,
    this.userLabel,
    this.lifecycle = WardrobeSetLifecycleV2.active,
    this.authority = 'user_confirmation',
    this.schemaVersion = '1.0.0',
  });

  final String setId;
  final WardrobeSetTypeV2 setType;
  final WardrobeSetRelationshipSourceV2 relationshipSource;
  final List<String> memberIds;
  final String generatedLabel;
  final String? userLabel;
  final WardrobeSetLifecycleV2 lifecycle;
  final String authority;
  final String schemaVersion;

  String get displayName =>
      userLabel?.trim().isNotEmpty == true ? userLabel!.trim() : generatedLabel;

  Map<String, dynamic> toMap() => {
    'schemaVersion': schemaVersion,
    'setId': setId,
    'setType': setType.wireName,
    'relationshipSource': relationshipSource.wireName,
    'memberIds': memberIds,
    'generatedLabel': generatedLabel,
    if (userLabel != null) 'userLabel': userLabel,
    'lifecycle': lifecycle.name,
    'authority': authority,
  };

  factory WardrobeSetV2.fromMap(Map<String, dynamic> map) => WardrobeSetV2(
    setId: (map['setId'] ?? '').toString(),
    setType: WardrobeSetTypeV2.parse(map['setType']?.toString()),
    relationshipSource: WardrobeSetRelationshipSourceV2.parse(
      map['relationshipSource']?.toString(),
    ),
    memberIds: (map['memberIds'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false),
    generatedLabel: (map['generatedLabel'] ?? 'Set').toString(),
    userLabel: map['userLabel']?.toString(),
    lifecycle: map['lifecycle'] == 'dissolved'
        ? WardrobeSetLifecycleV2.dissolved
        : WardrobeSetLifecycleV2.active,
    authority: (map['authority'] ?? 'user_confirmation').toString(),
    schemaVersion: (map['schemaVersion'] ?? '1.0.0').toString(),
  );
}

abstract final class WardrobeSetPresentationV2 {
  static const palette = <Color>[
    Color(0xFFC8A36A),
    Color(0xFF4C78A8),
    Color(0xFFE45756),
    Color(0xFF54A24B),
    Color(0xFFB279A2),
    Color(0xFFF58518),
    Color(0xFF72B7B2),
    Color(0xFF9D755D),
  ];

  static int stableIndex(String setId) {
    var hash = 0x811c9dc5;
    for (final unit in setId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash % palette.length;
  }

  static Color borderColor(String setId) => palette[stableIndex(setId)];
  static IconData icon(String setId) =>
      stableIndex(setId).isEven ? Icons.interests_rounded : Icons.link_rounded;
}

enum WardrobeSetComponentStatusV2 {
  notStarted,
  imageReady,
  analyzing,
  analysisReady,
  saving,
  saved,
  failed,
}

class WardrobeSetDraftComponentV2 {
  const WardrobeSetDraftComponentV2({
    required this.componentId,
    required this.status,
    this.itemId,
    this.storagePath,
    this.cachedAnalyzerPayload,
    this.failureStage,
  });
  final String componentId;
  final WardrobeSetComponentStatusV2 status;
  final String? itemId, storagePath, failureStage;
  final Map<String, dynamic>? cachedAnalyzerPayload;

  Map<String, dynamic> toMap() => {
    'componentId': componentId,
    'status': status.name,
    if (itemId != null) 'itemId': itemId,
    if (storagePath != null) 'storagePath': storagePath,
    if (cachedAnalyzerPayload != null)
      'cachedAnalyzerPayload': cachedAnalyzerPayload,
    if (failureStage != null) 'failureStage': failureStage,
  };
}
