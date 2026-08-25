import '../data/stylist_intent.dart';
import 'dress_code_resolver.dart';

/// Určí [StylistIntent] z konverzácie a dress-code archetypov — log-only v M1a.
class StylistIntentResolver {
  const StylistIntentResolver._();

  static StylistIntent resolve({
    String? occasion,
    String? conversationText,
    Map<String, dynamic>? aiDressCode,
    int? tempC,
  }) {
    final activityType = _resolveActivityType(
      occasion: occasion,
      conversationText: conversationText,
      aiDressCode: aiDressCode,
      tempC: tempC,
    );
    return StylistIntentCatalog.intentFor(activityType);
  }

  static String _resolveActivityType({
    String? occasion,
    String? conversationText,
    Map<String, dynamic>? aiDressCode,
    int? tempC,
  }) {
    final blob = '${occasion ?? ''} ${conversationText ?? ''}'.toLowerCase();

    if (blob.trim().isEmpty) return 'casual';

    // Špecifickejšie aktivity pred všeobecným dress-code matchom.
    if (_matchesMushroom(blob)) return 'mushroom';
    if (_matchesBarbecue(blob)) return 'barbecue';
    if (_matchesDate(blob)) return 'date';
    if (_matchesCinema(blob)) return 'cinema';
    if (_matchesDinner(blob)) return 'dinner';

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

  static bool _matchesMushroom(String blob) {
    return _matchesAny(blob, [
      'hubovan',
      'huby',
      'hub ',
      'hub,',
      'hub.',
      'hrib',
      'hriby',
      'hribov',
    ]);
  }

  static bool _matchesBarbecue(String blob) {
    return _matchesAny(blob, [
      'grilov',
      'gril ',
      'grill',
      'bbq',
      'barbecue',
      'opekac',
      'opekač',
    ]);
  }

  static bool _matchesDate(String blob) {
    return blob.contains('rande') ||
        blob.contains('date night') ||
        RegExp(r'\bdate\b').hasMatch(blob);
  }

  static bool _matchesCinema(String blob) {
    return blob.contains('kino') ||
        blob.contains('kina') ||
        blob.contains('kine') ||
        blob.contains('cinema') ||
        blob.contains('movie');
  }

  // Pozn.: zámerne matchujeme „večeru"/„večeri" (akuzatív/lokál), nie „večer",
  // aby sme nezachytili „Večer idem na svadbu.".
  static bool _matchesDinner(String blob) {
    return blob.contains('večeru') ||
        blob.contains('veceru') ||
        blob.contains('večeri') ||
        blob.contains('veceri') ||
        blob.contains('dinner') ||
        blob.contains('reštaurác') ||
        blob.contains('restaurac');
  }

  static bool _matchesAny(String blob, List<String> needles) {
    for (final needle in needles) {
      if (blob.contains(needle)) return true;
    }
    return false;
  }
}
