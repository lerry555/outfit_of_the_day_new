import '../data/stylist_intent.dart';
import 'dress_code_resolver.dart';
import 'stylist_semantic_activity.dart';

/// Určí [StylistIntent] z kanonickej aktivity alebo dress-code archetypu.
/// Slovenské tvary/parafrázy rieši zdieľaný [StylistSemanticActivity], aby sa
/// jazykové zoznamy nerozchádzali medzi groundingom, intentom a terénom.
class StylistIntentResolver {
  const StylistIntentResolver._();

  static StylistIntent resolve({
    String? occasion,
    String? conversationText,
    Map<String, dynamic>? aiDressCode,
    int? tempC,
    String? groundedActivityType,
  }) {
    final grounded = _resolveGroundedActivityType(groundedActivityType);
    if (grounded != null) return _intentForCanonical(grounded);

    final activityType = _resolveActivityType(
      occasion: occasion,
      conversationText: conversationText,
      aiDressCode: aiDressCode,
      tempC: tempC,
    );
    return StylistIntentCatalog.intentFor(activityType);
  }

  static StylistIntent _intentForCanonical(String canonical) {
    final effective = canonical == 'zoo' ? 'city_walk' : canonical;
    final profile = StylistIntentCatalog.intentFor(effective);
    if (profile.activityType == effective) return profile;
    return StylistIntent(
      activityType: effective,
      primaryImpressions: profile.primaryImpressions,
      secondaryImpressions: profile.secondaryImpressions,
      avoidImpressions: profile.avoidImpressions,
      impressionSummarySk: profile.impressionSummarySk,
    );
  }

  static String? _resolveGroundedActivityType(String? value) {
    final canonical = StylistSemanticActivity.canonicalize(value);
    if (canonical != null) return canonical;
    return StylistSemanticActivity.resolveExplicit(value ?? '');
  }

  static String _resolveActivityType({
    String? occasion,
    String? conversationText,
    Map<String, dynamic>? aiDressCode,
    int? tempC,
  }) {
    final blob = '${occasion ?? ''} ${conversationText ?? ''}'.trim();
    if (blob.isEmpty) return 'casual';

    final semantic = StylistSemanticActivity.resolveExplicit(blob);
    if (semantic != null) return semantic == 'zoo' ? 'city_walk' : semantic;

    final dressCode = DressCodeResolver.resolve(
      occasion: occasion,
      conversationText: conversationText,
      aiDressCode: aiDressCode,
      tempC: tempC,
    );

    if (StylistIntentCatalog.byActivityType.containsKey(dressCode.id)) {
      return dressCode.id;
    }
    return 'casual';
  }
}
