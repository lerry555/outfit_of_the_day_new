import '../wardrobe_v2/wardrobe_item_v2.dart';
import 'shopping_money.dart';

enum CatalogLifecycleState { active, unavailable, discontinued, unknownOrStale }

enum CatalogAvailability { available, unavailable, unknown }

enum PartnerStatus { active, paused, disabled }

enum PromotionKind { publicSale, publicCoupon, memberOnly, bundle }

enum QuantityReliability { exact, partnerLowStockSignal, unknown }

enum GenerationEligibilityStatus { eligible, pendingValidImage, rejectedImage }

class CatalogPartner {
  const CatalogPartner({
    required this.partnerId,
    required this.publicStoreName,
    required this.status,
    required this.allowedDomains,
    required this.adapterKey,
    required this.adapterVersion,
    this.capabilities = const {},
  });

  final String partnerId, publicStoreName, adapterKey, adapterVersion;
  final PartnerStatus status;
  final Set<String> allowedDomains, capabilities;
}

/// Strong identifiers supplied by a manufacturer or verified partner.
///
/// Display name, visual similarity, and AI opinions are deliberately absent.
class CatalogIdentityEvidence {
  const CatalogIdentityEvidence({
    this.gtin,
    this.manufacturerModelId,
    this.manufacturerSku,
    this.reliablePartnerProductId,
    this.reliablePartnerVariantId,
  });

  final String? gtin,
      manufacturerModelId,
      manufacturerSku,
      reliablePartnerProductId,
      reliablePartnerVariantId;

  bool get hasProductStrongEvidence =>
      _filled(gtin) ||
      _filled(manufacturerModelId) ||
      _filled(manufacturerSku) ||
      _filled(reliablePartnerProductId);

  bool get hasVariantStrongEvidence =>
      _filled(gtin) ||
      _filled(manufacturerSku) ||
      _filled(reliablePartnerVariantId);

  static bool _filled(String? value) =>
      value != null && value.trim().isNotEmpty;

  bool matchesProduct(CatalogIdentityEvidence other) =>
      _sameNonEmpty(gtin, other.gtin) ||
      _sameNonEmpty(manufacturerModelId, other.manufacturerModelId) ||
      _sameNonEmpty(manufacturerSku, other.manufacturerSku) ||
      _sameNonEmpty(reliablePartnerProductId, other.reliablePartnerProductId);

  bool matchesVariant(CatalogIdentityEvidence other) =>
      _sameNonEmpty(gtin, other.gtin) ||
      _sameNonEmpty(manufacturerSku, other.manufacturerSku) ||
      _sameNonEmpty(reliablePartnerVariantId, other.reliablePartnerVariantId);

  static bool _sameNonEmpty(String? left, String? right) =>
      _filled(left) && _filled(right) && left!.trim() == right!.trim();
}

class CatalogProduct {
  const CatalogProduct({
    required this.productId,
    required this.brand,
    required this.normalizedModelIdentity,
    required this.canonicalType,
    required this.canonicalFamily,
    required this.identityEvidence,
    this.lifecycleState = CatalogLifecycleState.active,
    this.schemaVersion = 1,
  });

  final String productId,
      brand,
      normalizedModelIdentity,
      canonicalType,
      canonicalFamily;
  final CatalogIdentityEvidence identityEvidence;
  final CatalogLifecycleState lifecycleState;
  final int schemaVersion;
}

class CatalogProductVariant {
  const CatalogProductVariant({
    required this.variantId,
    required this.productId,
    required this.exactColorName,
    required this.colorProfile,
    required this.identityEvidence,
    this.exactColorCode,
    this.fit,
    this.material,
    this.pattern,
    this.styles = const {},
    this.warmth,
    this.formality,
    this.generationEligibility,
  }) : assert(warmth == null || (warmth >= 1 && warmth <= 10)),
       assert(formality == null || (formality >= 1 && formality <= 10));

  final String variantId, productId, exactColorName;
  final ColorProfileV2 colorProfile;
  final CatalogIdentityEvidence identityEvidence;
  final String? exactColorCode, fit, material, pattern;
  final Set<String> styles;
  final int? warmth, formality;
  final GenerationEligibilityContract? generationEligibility;
}

class GenerationEligibilityContract {
  const GenerationEligibilityContract({
    required this.status,
    this.reason,
    this.source,
    this.verifiedAt,
  });

  final GenerationEligibilityStatus status;
  final String? reason, source;
  final DateTime? verifiedAt;

  /// Existing Wardrobe items omit this future field and stay usable.
  static GenerationEligibilityStatus effectiveStatus(
    GenerationEligibilityContract? value,
  ) => value?.status ?? GenerationEligibilityStatus.eligible;
}

class PublicPromotion {
  const PublicPromotion.publicSale({required this.price})
    : kind = PromotionKind.publicSale,
      code = null,
      description = null;

  const PublicPromotion.publicCoupon({required this.price, required this.code})
    : kind = PromotionKind.publicCoupon,
      description = null;

  const PublicPromotion.memberOnly({required this.price})
    : kind = PromotionKind.memberOnly,
      code = null,
      description = null;

  const PublicPromotion.bundle({required this.price, required this.description})
    : kind = PromotionKind.bundle,
      code = null;

  final PromotionKind kind;
  final ShoppingMoney price;
  final String? code, description;
}

class CatalogOffer {
  const CatalogOffer({
    required this.offerId,
    required this.variantId,
    required this.partnerId,
    required this.partnerListingId,
    required this.url,
    required this.regularPrice,
    required this.overallAvailability,
    this.promotions = const [],
    this.lifecycleState = CatalogLifecycleState.active,
    this.lastVerifiedAt,
  });

  final String offerId, variantId, partnerId, partnerListingId, url;
  final ShoppingMoney regularPrice;
  final CatalogAvailability overallAvailability;
  final List<PublicPromotion> promotions;
  final CatalogLifecycleState lifecycleState;
  final DateTime? lastVerifiedAt;
}

class SizeAvailability {
  const SizeAvailability({
    required this.offerId,
    required this.normalizedSizeKey,
    required this.partnerSizeLabel,
    required this.sizeSystem,
    required this.availability,
    this.exactQuantity,
    this.quantityReliability = QuantityReliability.unknown,
    this.observedAt,
  }) : assert(exactQuantity == null || exactQuantity >= 0);

  final String offerId, normalizedSizeKey, partnerSizeLabel, sizeSystem;
  final CatalogAvailability availability;
  final int? exactQuantity;
  final QuantityReliability quantityReliability;
  final DateTime? observedAt;

  bool get canClaimExactQuantity =>
      exactQuantity != null && quantityReliability == QuantityReliability.exact;

  bool get hasInformationalStockUrgency =>
      canClaimExactQuantity ||
      quantityReliability == QuantityReliability.partnerLowStockSignal;
}

class CatalogFreshness {
  const CatalogFreshness({
    this.sourceObservedAt,
    this.receivedAt,
    this.lastSuccessfulVerificationAt,
    this.syncRunId,
    this.stale = false,
  });

  final DateTime? sourceObservedAt, receivedAt, lastSuccessfulVerificationAt;
  final String? syncRunId;
  final bool stale;

  CatalogFreshness markRefreshFailure() => CatalogFreshness(
    sourceObservedAt: sourceObservedAt,
    receivedAt: receivedAt,
    lastSuccessfulVerificationAt: lastSuccessfulVerificationAt,
    syncRunId: syncRunId,
    stale: true,
  );
}
