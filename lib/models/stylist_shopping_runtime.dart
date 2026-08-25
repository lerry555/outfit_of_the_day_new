class StylistShoppingAttachment {
  const StylistShoppingAttachment({required this.kind, required this.payload});

  final String kind;
  final Map<String, dynamic> payload;

  factory StylistShoppingAttachment.fromMap(Map<String, dynamic> map) {
    final kind = (map['kind'] ?? '').toString();
    const allowed = {
      'shopping_candidate',
      'shopping_result_group',
      'shopping_clarification',
      'wishlist_offer',
      'wishlist_editor',
      'shopping_session_recovery',
      'shopping_relaxations',
    };
    if (!allowed.contains(kind)) {
      throw const FormatException('Unsupported Shopping attachment.');
    }
    return StylistShoppingAttachment(
      kind: kind,
      payload: Map<String, dynamic>.unmodifiable(map),
    );
  }

  Map<String, dynamic> toMap() => Map<String, dynamic>.from(payload);
}

class StylistShoppingSessionState {
  const StylistShoppingSessionState({
    this.sessionId,
    this.queryRevision,
    this.sessionVersion,
    this.catalogRevision,
    this.query,
    this.presentedVariantIds = const [],
    this.presentedCandidates = const [],
    this.focusedVariantId,
    this.activeClarification,
    this.pendingSourceText,
    this.pendingNeedText,
    this.pendingWishlistOfferVariantId,
  });

  final String? sessionId;
  final int? queryRevision;
  final int? sessionVersion;
  final String? catalogRevision;
  final Map<String, dynamic>? query;
  final List<String> presentedVariantIds;
  final List<Map<String, dynamic>> presentedCandidates;
  final String? focusedVariantId;
  final String? activeClarification;
  final String? pendingSourceText;
  final String? pendingNeedText;
  final String? pendingWishlistOfferVariantId;

  bool get isActive =>
      sessionId != null ||
      activeClarification != null ||
      pendingSourceText != null;

  Map<String, dynamic> toApiPayload() => <String, dynamic>{
    if (sessionId != null) 'sessionId': sessionId,
    if (queryRevision != null) 'queryRevision': queryRevision,
    if (sessionVersion != null) 'sessionVersion': sessionVersion,
    if (catalogRevision != null) 'catalogRevision': catalogRevision,
    if (query != null) 'query': query,
    'presentedVariantIds': presentedVariantIds,
    'presentedCandidates': presentedCandidates,
    if (focusedVariantId != null) 'focusedVariantId': focusedVariantId,
    if (activeClarification != null) 'activeClarification': activeClarification,
    if (pendingSourceText != null) 'pendingSourceText': pendingSourceText,
    if (pendingNeedText != null) 'pendingNeedText': pendingNeedText,
    if (pendingWishlistOfferVariantId != null)
      'pendingWishlistOfferVariantId': pendingWishlistOfferVariantId,
  };

  StylistShoppingSessionState applyPatch(Map<String, dynamic> patch) {
    List<String> ids(dynamic value) => value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : presentedVariantIds;
    List<Map<String, dynamic>> candidates(dynamic value) => value is List
        ? value
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : presentedCandidates;

    return StylistShoppingSessionState(
      sessionId: _nullableText(patch['sessionId']) ?? sessionId,
      queryRevision: patch['queryRevision'] is num
          ? (patch['queryRevision'] as num).toInt()
          : queryRevision,
      sessionVersion: patch['sessionVersion'] is num
          ? (patch['sessionVersion'] as num).toInt()
          : sessionVersion,
      catalogRevision:
          _nullableText(patch['catalogRevision']) ?? catalogRevision,
      query: patch['query'] is Map
          ? Map<String, dynamic>.from(patch['query'] as Map)
          : query,
      presentedVariantIds: ids(patch['presentedVariantIds']),
      presentedCandidates: candidates(patch['presentedCandidates']),
      focusedVariantId: patch.containsKey('focusedVariantId')
          ? _nullableText(patch['focusedVariantId'])
          : focusedVariantId,
      activeClarification: patch.containsKey('activeClarification')
          ? _nullableText(patch['activeClarification'])
          : activeClarification,
      pendingSourceText: patch.containsKey('pendingSourceText')
          ? _nullableText(patch['pendingSourceText'])
          : pendingSourceText,
      pendingNeedText: patch.containsKey('pendingNeedText')
          ? _nullableText(patch['pendingNeedText'])
          : pendingNeedText,
      pendingWishlistOfferVariantId:
          patch.containsKey('pendingWishlistOfferVariantId')
          ? _nullableText(patch['pendingWishlistOfferVariantId'])
          : pendingWishlistOfferVariantId,
    );
  }

  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

abstract final class StylistShoppingClientRouting {
  static bool shouldUseShoppingTransport(
    String text,
    StylistShoppingSessionState state,
  ) {
    final lower = text.toLowerCase();
    return state.isActive ||
        RegExp(
          r'chcem si kúpiť|chcem kupit|niečo nové|nieco nove|z obchodov|'
          r'ukáž mi niečo k|ukaz mi nieco k|úplne nový outfit|uplne novy outfit',
        ).hasMatch(lower);
  }

  static bool isNormalOutfitTopic(String text) => RegExp(
    r'(čo si mám|co si mam).*(obliecť|obliect)|'
    r'outfit.*(prác|prac|pohreb|hory|turistik)',
  ).hasMatch(text.toLowerCase());
}
