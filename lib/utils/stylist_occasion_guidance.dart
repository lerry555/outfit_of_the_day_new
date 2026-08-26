import '../data/stylist_opinion.dart';
import '../data/wardrobe_analysis.dart';
import '../Services/outfit_generation_service.dart';
import '../data/event_dress_code.dart';
import 'bottom_family_guidance.dart';
import 'dress_code_resolver.dart';
import 'footwear_family_guidance.dart';

/// Dress-code profil pre generovanie outfitu v stylist chate.
class StylistOccasionProfile {
  final EventDressCodeSpec dressCode;
  final int? tempC;

  const StylistOccasionProfile({
    this.dressCode = EventDressCodeSpec.casual,
    this.tempC,
  });

  String get label => dressCode.labelSk;

  bool get excludeShorts {
    final temp = tempC ?? 20;
    return !dressCode.allowShorts(temp);
  }

  bool get preferJeans => dressCode.preferJeans;

  bool get isElevated => dressCode.isElevated;

  bool get isSmartCasual => isElevated;

  String get smartCasualPhrase => dressCode.explainPhrase();
}

class StylistOccasionGuidance {
  const StylistOccasionGuidance._();

  static const String activityClarificationMessage =
      'Aké rande to bude? Skôr zmrzlina a prechádzka, alebo pekná večera v reštaurácii? '
      'Podľa toho zložím outfit — pri zmrzline môžu byť šortky, do luxusnej reštaurácie radšej rifle.';

  static String get concertClarificationMessage =>
      EventDressCodeCatalog.concertClarificationMessage;

  static String clarificationMessageFor(String? conversationText) {
    if (DressCodeResolver.needsVenueClarification(conversationText)) {
      return concertClarificationMessage;
    }
    return activityClarificationMessage;
  }

  static bool needsActivityClarification(String? conversationText) {
    return DressCodeResolver.needsDateActivityClarification(conversationText) ||
        DressCodeResolver.needsVenueClarification(conversationText);
  }

  static StylistOccasionProfile profileFor({
    String? occasion,
    String? conversationText,
    int? tempC,
    Map<String, dynamic>? dressCodeFromAi,
    String? groundedActivityType,
  }) {
    final dressCode = DressCodeResolver.resolveGroundedActivity(
          groundedActivityType,
        ) ??
        DressCodeResolver.resolve(
      occasion: occasion,
      conversationText: conversationText,
      aiDressCode: dressCodeFromAi,
      tempC: tempC,
    );
    return StylistOccasionProfile(dressCode: dressCode, tempC: tempC);
  }

  /// Počasie určuje vrstvy a komfort; príležitosť má prednosť pri spodku.
  static BottomFamilyGuidance bottomGuidanceFor({
    required OutfitWeatherSnapshot weather,
    required StylistOccasionProfile profile,
  }) {
    final base = computeBottomFamilyGuidance(weather: weather);
    return _applyOccasionBottomOverlay(base, profile);
  }

  /// Počasie určuje komfort; príležitosť má prednosť pri obuvi.
  static FootwearFamilyGuidance footwearGuidanceFor({
    required OutfitWeatherSnapshot weather,
    required StylistOccasionProfile profile,
    bool wetGroundMuddy = false,
  }) {
    final base = computeFootwearFamilyGuidance(
      weather: weather,
      wetGroundMuddy: wetGroundMuddy,
    );
    return _applyOccasionFootwearOverlay(base, profile);
  }

  /// Kompromisy, keď šatník nemá lepšiu alternatívu (napr. rifle na túre).
  static List<String> outfitCompromiseNotes({
    required OutfitPreview preview,
    required BottomFamilyGuidance bottomGuidance,
    required FootwearFamilyGuidance footwearGuidance,
    required StylistOccasionProfile profile,
  }) {
    final notes = <String>[];
    final bottom = classifyBottomFamily(preview.bottom.item);
    if (profile.dressCode.id == 'hike' &&
        bottom == BottomFamily.jeans &&
        bottomGuidance.isDiscouraged(BottomFamily.jeans)) {
      notes.add('hike_jeans_compromise');
    }
    final shoes = classifyFootwearFamily(preview.shoes.item);
    if (profile.dressCode.formalityTarget >= 7 &&
        shoes == FootwearFamily.sandals &&
        footwearGuidance.isDiscouraged(FootwearFamily.sandals)) {
      notes.add('formal_sandals_compromise');
    }
    return notes;
  }

  /// Kontext príležitosti pre AI final review (stylist chat).
  static Map<String, dynamic> finalReviewOccasionPayload({
    required StylistOccasionProfile profile,
    List<String> compromiseNotes = const [],
  }) {
    return <String, dynamic>{
      'occasionLabel': profile.label,
      'activityType': profile.dressCode.id,
      'formalityTarget': profile.dressCode.formalityTarget,
      'venueType': profile.dressCode.venue.wireName,
      if (compromiseNotes.isNotEmpty)
        'compromiseNotes': List<String>.from(compromiseNotes),
    };
  }

  /// Kontext pre explain_outfit — occasion + guidance + kompromisy + wardrobe gap.
  static Map<String, dynamic> explainOutfitPayloadFor({
    required StylistOccasionProfile profile,
    required OutfitPreview preview,
    required OutfitWeatherSnapshot weather,
    bool wetGroundMuddy = false,
    WardrobeAnalysis? wardrobeAnalysis,
    StylistOpinion? stylistOpinion,
  }) {
    final bottomGuidance = bottomGuidanceFor(weather: weather, profile: profile);
    final footwearGuidance = footwearGuidanceFor(
      weather: weather,
      profile: profile,
      wetGroundMuddy: wetGroundMuddy,
    );
    final compromiseNotes = outfitCompromiseNotes(
      preview: preview,
      bottomGuidance: bottomGuidance,
      footwearGuidance: footwearGuidance,
      profile: profile,
    );
    return <String, dynamic>{
      'occasionContext': finalReviewOccasionPayload(
        profile: profile,
        compromiseNotes: compromiseNotes,
      ),
      'bottomGuidance': bottomGuidance.toPayload(),
      'footwearGuidance': footwearGuidance.toPayload(),
      if (wardrobeAnalysis != null)
        'wardrobeAnalysis': wardrobeAnalysis.toPayload(),
      if (stylistOpinion != null)
        'stylistOpinion': stylistOpinion.toPayload(),
    };
  }

  static BottomFamilyGuidance _applyOccasionBottomOverlay(
    BottomFamilyGuidance base,
    StylistOccasionProfile profile,
  ) {
    final dressCode = profile.dressCode;
    final formality = dressCode.formalityTarget;
    final dressId = dressCode.id;
    const formalIds = {'wedding', 'interview', 'funeral'};
    final shorts = BottomFamily.shorts.wireName;
    final jeans = BottomFamily.jeans.wireName;
    final pants = BottomFamily.pants.wireName;
    final joggers = BottomFamily.joggers.wireName;

    var preferred = List<String>.from(base.preferredFamilies);
    var allowed = List<String>.from(base.allowedFamilies);
    var discouraged = List<String>.from(base.discouragedFamilies);
    var reason = base.reason;
    var overlayApplied = false;

    if (formality >= 5) {
      preferred.remove(shorts);
      _ensureDiscouraged(discouraged, shorts);
      if (formality >= 7) {
        allowed.remove(shorts);
      }
      overlayApplied = true;
    }

    if (profile.excludeShorts) {
      preferred.remove(shorts);
      allowed.remove(shorts);
      _ensureDiscouraged(discouraged, shorts);
      overlayApplied = true;
    }

    if (formalIds.contains(dressId) || formality >= 7) {
      _bumpPreferred(preferred, pants);
      if (!dressCode.preferJeans) {
        preferred.remove(jeans);
        _ensureDiscouraged(discouraged, jeans);
      }
      overlayApplied = true;
    }

    if (dressId == 'work') {
      if (dressCode.preferJeans) {
        _bumpPreferred(preferred, jeans);
      }
      _bumpPreferred(preferred, pants);
      overlayApplied = true;
    }

    if (dressId == 'hike') {
      preferred.remove(jeans);
      _bumpPreferred(preferred, joggers);
      _bumpPreferred(preferred, pants);
      _ensureDiscouraged(discouraged, jeans);
      overlayApplied = true;
    }

    if (overlayApplied) {
      reason =
          '$reason Dress code (${profile.label}, formálnosť ~$formality): '
          'príležitosť má prednosť pred teplotou pri spodku.';
    }

    return BottomFamilyGuidance(
      preferredFamilies: preferred,
      allowedFamilies: allowed,
      discouragedFamilies: discouraged,
      reason: reason,
    );
  }

  static FootwearFamilyGuidance _applyOccasionFootwearOverlay(
    FootwearFamilyGuidance base,
    StylistOccasionProfile profile,
  ) {
    final dressCode = profile.dressCode;
    final formality = dressCode.formalityTarget;
    final dressId = dressCode.id;
    const formalIds = {'wedding', 'interview', 'funeral'};
    final sandals = FootwearFamily.sandals.wireName;
    final formal = FootwearFamily.formalShoes.wireName;
    final sneakers = FootwearFamily.sneakers.wireName;

    var preferred = List<String>.from(base.preferredFamilies);
    var allowed = List<String>.from(base.allowedFamilies);
    var discouraged = List<String>.from(base.discouragedFamilies);
    var reason = base.reason;

    if (formalIds.contains(dressId) || formality >= 7) {
      preferred.remove(sandals);
      allowed.remove(sandals);
      _ensureDiscouraged(discouraged, sandals);
      _bumpPreferred(preferred, formal);
      reason =
          '$reason Dress code (${profile.label}): uzavretá/elegantnejšia obuv.';
    } else if (formality >= 5 && dressCode.venue != EventVenueType.outdoor) {
      preferred.remove(sandals);
      allowed.remove(sandals);
      _ensureDiscouraged(discouraged, sandals);
      reason = '$reason Dress code (${profile.label}): v práci radšej uzavretá obuv.';
    }

    if (dressId == 'hike') {
      _bumpPreferred(preferred, sneakers);
      preferred.remove(sandals);
      allowed.remove(sandals);
      _ensureDiscouraged(discouraged, sandals);
      reason = '$reason Turistika: uzavretá obuv, nie sandále.';
    }

    for (final p in preferred) {
      if (!allowed.contains(p)) allowed.add(p);
    }

    return FootwearFamilyGuidance(
      preferredFamilies: preferred,
      allowedFamilies: allowed,
      discouragedFamilies: discouraged,
      reason: reason,
    );
  }

  static void _bumpPreferred(List<String> preferred, String family) {
    preferred.remove(family);
    preferred.insert(0, family);
  }

  static void _ensureDiscouraged(List<String> discouraged, String family) {
    if (!discouraged.contains(family)) discouraged.add(family);
  }

  static Set<String> shortsItemIds(List<Map<String, dynamic>> wardrobe) {
    final ids = <String>{};
    for (final item in wardrobe) {
      if (classifyBottomFamily(item) != BottomFamily.shorts) continue;
      final id = OutfitGenerationService.wardrobeItemId(item);
      if (id.isNotEmpty) ids.add(id);
    }
    return ids;
  }
}
