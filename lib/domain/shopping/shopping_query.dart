import 'shopping_money.dart';

enum ShoppingIntent { browseNew, gapFill, completelyNewOutfit, findSimilar }

enum ShoppingConstraintField {
  canonicalType,
  canonicalFamily,
  color,
  brand,
  fit,
  material,
  pattern,
  style,
  detail,
  maxPrice,
}

enum ShoppingConstraintOperator { equals, excludes, atMost, includes }

enum ConstraintStrength { hard, soft }

enum ConstraintSource { explicitUser, inferred }

class ShoppingConstraint {
  const ShoppingConstraint({
    required this.field,
    required this.operator,
    required this.value,
    required this.strength,
    required this.source,
    this.relaxable = true,
    this.absolute = false,
    this.userTurnId,
  }) : assert(!absolute || strength == ConstraintStrength.hard);

  final ShoppingConstraintField field;
  final ShoppingConstraintOperator operator;
  final Object value;
  final ConstraintStrength strength;
  final ConstraintSource source;
  final bool relaxable, absolute;
  final String? userTurnId;

  bool get isHard => strength == ConstraintStrength.hard;

  bool get mayRelaxOnlyAfterUserChoice =>
      source == ConstraintSource.explicitUser && (isHard || absolute);
}

class ShoppingQuery {
  const ShoppingQuery({
    required this.queryId,
    required this.sessionId,
    required this.intent,
    required this.constraints,
    this.referenceWardrobeItemIds = const {},
    this.referenceCatalogVariantIds = const {},
    this.availableNow = false,
    this.contextReferenceIds = const {},
    this.revision = 1,
  });

  final String queryId, sessionId;
  final ShoppingIntent intent;
  final List<ShoppingConstraint> constraints;
  final Set<String> referenceWardrobeItemIds,
      referenceCatalogVariantIds,
      contextReferenceIds;
  final bool availableNow;
  final int revision;

  ShoppingMoney? get maxPrice {
    for (final constraint in constraints) {
      if (constraint.field == ShoppingConstraintField.maxPrice &&
          constraint.operator == ShoppingConstraintOperator.atMost &&
          constraint.value is ShoppingMoney) {
        return constraint.value as ShoppingMoney;
      }
    }
    return null;
  }
}

class BlockingConstraintDiagnostic {
  const BlockingConstraintDiagnostic({
    required this.blockingConstraints,
    required this.exactResultCount,
  });

  final List<ShoppingConstraint> blockingConstraints;
  final int exactResultCount;

  bool get hasBlockingConstraints => blockingConstraints.isNotEmpty;
}

abstract final class ShoppingConstraintDiagnostics {
  /// Zero exact matches does not authorize relaxation. This reports only
  /// explicit hard constraints the UI may explain or ask about.
  static BlockingConstraintDiagnostic forZeroExactResults(ShoppingQuery query) {
    final blocking = query.constraints
        .where(
          (constraint) =>
              constraint.isHard &&
              constraint.source == ConstraintSource.explicitUser,
        )
        .toList(growable: false);
    return BlockingConstraintDiagnostic(
      blockingConstraints: blocking,
      exactResultCount: 0,
    );
  }
}

class ShoppingCandidate {
  const ShoppingCandidate({
    required this.variantId,
    required this.relevantOfferIds,
    required this.deterministicScore,
    this.bestOfferId,
    this.unmetConstraints = const [],
    this.suitabilityEvidence = const {},
    this.wardrobeCompatibilityEvidence = const {},
    this.setSignal = 0,
    this.futureAiRerank,
  });

  final String variantId;
  final Set<String> relevantOfferIds;
  final String? bestOfferId;
  final double deterministicScore, setSignal;
  final List<ShoppingConstraint> unmetConstraints;
  final Map<String, Object?> suitabilityEvidence, wardrobeCompatibilityEvidence;
  final double? futureAiRerank;
}

class ShoppingResultPool {
  const ShoppingResultPool({
    required this.queryRevision,
    required this.catalogRevision,
    required this.orderedCandidateIds,
    this.shownCandidateIds = const {},
    this.rejectedCandidateIds = const {},
    this.cursor = 0,
  });

  final int queryRevision;
  final String catalogRevision;
  final List<String> orderedCandidateIds;
  final Set<String> shownCandidateIds, rejectedCandidateIds;
  final int cursor;

  List<String> unseen({required int limit}) => orderedCandidateIds
      .where(
        (id) =>
            !shownCandidateIds.contains(id) &&
            !rejectedCandidateIds.contains(id),
      )
      .take(limit)
      .toList(growable: false);

  ShoppingResultPool markShown(Iterable<String> ids) => ShoppingResultPool(
    queryRevision: queryRevision,
    catalogRevision: catalogRevision,
    orderedCandidateIds: orderedCandidateIds,
    shownCandidateIds: {...shownCandidateIds, ...ids},
    rejectedCandidateIds: rejectedCandidateIds,
    cursor: cursor + ids.length,
  );

  ShoppingResultPool reject(String candidateId) => ShoppingResultPool(
    queryRevision: queryRevision,
    catalogRevision: catalogRevision,
    orderedCandidateIds: orderedCandidateIds,
    shownCandidateIds: shownCandidateIds,
    rejectedCandidateIds: {...rejectedCandidateIds, candidateId},
    cursor: cursor,
  );
}

class ShoppingSessionContext {
  const ShoppingSessionContext({
    required this.sessionId,
    required this.query,
    required this.resultPool,
    this.currentFocusVariantId,
    this.activeClarification,
    this.expiresAt,
  });

  final String sessionId;
  final ShoppingQuery query;
  final ShoppingResultPool resultPool;
  final String? currentFocusVariantId, activeClarification;
  final DateTime? expiresAt;
}

class FindSimilarRequest {
  const FindSimilarRequest({
    required this.variantId,
    required this.targetPrice,
    this.requireExactColor = true,
    this.requiredBrand,
  });

  final String variantId;
  final ShoppingMoney targetPrice;
  final bool requireExactColor;
  final String? requiredBrand;
}
