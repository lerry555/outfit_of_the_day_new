import 'catalog_models.dart';

abstract final class CatalogIdentityPolicy {
  /// Merge only when both records independently carry matching strong evidence.
  ///
  /// Titles, brand names, image similarity, and AI conclusions do not occur in
  /// this API and therefore can never authorize a merge.
  static bool mayMergeProducts(CatalogProduct left, CatalogProduct right) =>
      left.identityEvidence.hasProductStrongEvidence &&
      right.identityEvidence.hasProductStrongEvidence &&
      left.identityEvidence.matchesProduct(right.identityEvidence);

  /// Variants require variant-level evidence. Product-model identity alone is
  /// deliberately insufficient because colour/style variants must stay exact.
  static bool mayMergeVariants(
    CatalogProductVariant left,
    CatalogProductVariant right,
  ) =>
      left.identityEvidence.hasVariantStrongEvidence &&
      right.identityEvidence.hasVariantStrongEvidence &&
      left.identityEvidence.matchesVariant(right.identityEvidence);

  static CatalogLifecycleState variantLifecycle(Iterable<CatalogOffer> offers) {
    final allOffers = offers.toList(growable: false);
    if (allOffers.isEmpty) return CatalogLifecycleState.unknownOrStale;
    final activeOffers = allOffers
        .where(
          (offer) => offer.lifecycleState != CatalogLifecycleState.discontinued,
        )
        .toList(growable: false);
    if (activeOffers.isEmpty) return CatalogLifecycleState.discontinued;
    if (activeOffers.any(
      (offer) => offer.overallAvailability == CatalogAvailability.available,
    )) {
      return CatalogLifecycleState.active;
    }
    if (activeOffers.every(
      (offer) => offer.overallAvailability == CatalogAvailability.unavailable,
    )) {
      return CatalogLifecycleState.unavailable;
    }
    return CatalogLifecycleState.unknownOrStale;
  }
}
