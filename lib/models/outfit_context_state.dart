import '../utils/stylist_day_parser.dart';
import '../utils/stylist_destination_parser.dart';
import '../utils/stylist_trip_parser.dart';

/// Známy kontext pre outfit — z konverzácie, GPS a dát appky.
///
/// AI dostane tento stav + fieldCatalog a sama rozhodne o chýbajúcich poliach.
class OutfitContextState {
  final String? gpsDefaultCity;
  final String? activityLocationLabel;
  final bool activityLocationKnown;
  final bool routineLocalOutfit;
  final bool remoteActivityPlanned;
  final int? hourLocal;
  final bool hourExplicit;
  final String? dateKey;
  final String? activityHint;
  final String? occasion;
  final bool clarifyRoundUsed;
  final List<String> clarifiedMaterialFields;
  final double? lastConfidence;
  final String? lastDecisionRisk;
  final List<String> lastAssumptions;
  final String? lastClarifyReason;
  final List<String> lastImpactFields;

  const OutfitContextState({
    this.gpsDefaultCity,
    this.activityLocationLabel,
    this.activityLocationKnown = false,
    this.routineLocalOutfit = false,
    this.remoteActivityPlanned = false,
    this.hourLocal,
    this.hourExplicit = false,
    this.dateKey,
    this.activityHint,
    this.occasion,
    this.clarifyRoundUsed = false,
    this.clarifiedMaterialFields = const [],
    this.lastConfidence,
    this.lastDecisionRisk,
    this.lastAssumptions = const [],
    this.lastClarifyReason,
    this.lastImpactFields = const [],
  });

  static const _remoteActivityHints = [
    'hory',
    'hore',
    'horach',
    'turist',
    'vylet',
    'výlet',
    'les',
    'lese',
    'hub',
    'hrib',
    'dovolen',
    'služobn',
    'sluzobn',
    'cest',
    'svadb',
    'tatry',
    'kopce',
    'kopcoch',
  ];

  static const _routineLocalHints = [
    'čo si mám',
    'co si mam',
    'čo na seba',
    'co na seba',
    'čo dnes',
    'co dnes',
    'na dnes',
    'dneska',
    'teraz',
    'hned',
    'ihned',
  ];

  /// Zostaví stav z konverzácie a dát appky (deterministické, bez AI).
  static OutfitContextState buildFrom({
    required String conversation,
    required String gpsCityLabel,
    OutfitContextState? previous,
  }) {
    final blob = conversation.toLowerCase();
    final gps = gpsCityLabel.split(',').first.trim();
    final inferred = StylistDestinationParser.inferFromConversation(conversation);
    final inferredOk = inferred != null &&
        inferred.trim().isNotEmpty &&
        StylistDestinationParser.isPlausibleDestination(inferred);

    final remote = _remoteActivityHints.any(blob.contains);
    final routine = _routineLocalHints.any(blob.contains) &&
        !remote &&
        !blob.contains('zajtra') &&
        !blob.contains('pozajtra');

    final trip = StylistTripParser.parseFromConversation(conversation);
    final hourFromText = trip.eventStartHour ?? _extractHour(blob);
    final hourExplicit = hourFromText != null ||
        blob.contains('teraz') ||
        blob.contains('hned') ||
        blob.contains('ihned');

    final date = StylistDayParser.resolveDate(conversation);
    String? dateKey;
    if (date != null) {
      dateKey = '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
    } else if (blob.contains('zajtra')) {
      dateKey = 'tomorrow';
    } else if (blob.contains('dnes')) {
      dateKey = 'today';
    }

    final activityLocationKnown = inferredOk || (routine && gps.isNotEmpty);
    final activityHint = _extractActivityHint(blob);

    return OutfitContextState(
      gpsDefaultCity: gps.isNotEmpty ? gps : null,
      activityLocationLabel: inferredOk ? inferred : null,
      activityLocationKnown: activityLocationKnown,
      routineLocalOutfit: routine,
      remoteActivityPlanned: remote,
      hourLocal: hourFromText,
      hourExplicit: hourExplicit,
      dateKey: dateKey,
      activityHint: activityHint,
      occasion: previous?.occasion,
      clarifyRoundUsed: previous?.clarifyRoundUsed ?? false,
      clarifiedMaterialFields: previous?.clarifiedMaterialFields ?? const [],
      lastConfidence: previous?.lastConfidence,
      lastDecisionRisk: previous?.lastDecisionRisk,
      lastAssumptions: previous?.lastAssumptions ?? const [],
      lastClarifyReason: previous?.lastClarifyReason,
      lastImpactFields: previous?.lastImpactFields ?? const [],
    );
  }

  OutfitContextState withClarifyRoundUsed(bool value) {
    return OutfitContextState(
      gpsDefaultCity: gpsDefaultCity,
      activityLocationLabel: activityLocationLabel,
      activityLocationKnown: activityLocationKnown,
      routineLocalOutfit: routineLocalOutfit,
      remoteActivityPlanned: remoteActivityPlanned,
      hourLocal: hourLocal,
      hourExplicit: hourExplicit,
      dateKey: dateKey,
      activityHint: activityHint,
      occasion: occasion,
      clarifyRoundUsed: value,
      clarifiedMaterialFields: value ? clarifiedMaterialFields : const [],
      lastConfidence: lastConfidence,
      lastDecisionRisk: lastDecisionRisk,
      lastAssumptions: lastAssumptions,
      lastClarifyReason: lastClarifyReason,
      lastImpactFields: lastImpactFields,
    );
  }

  /// Records a material question without imposing a global question count.
  /// A later, distinct outfit-changing uncertainty may still be clarified.
  OutfitContextState withClarificationAsked(Iterable<String> fields) {
    final merged = <String>{
      ...clarifiedMaterialFields.map((value) => value.trim().toLowerCase()),
      ...fields.map((value) => value.trim().toLowerCase()),
    }..removeWhere((value) => value.isEmpty);
    return OutfitContextState(
      gpsDefaultCity: gpsDefaultCity,
      activityLocationLabel: activityLocationLabel,
      activityLocationKnown: activityLocationKnown,
      routineLocalOutfit: routineLocalOutfit,
      remoteActivityPlanned: remoteActivityPlanned,
      hourLocal: hourLocal,
      hourExplicit: hourExplicit,
      dateKey: dateKey,
      activityHint: activityHint,
      occasion: occasion,
      clarifyRoundUsed: true,
      clarifiedMaterialFields: merged.toList(growable: false),
      lastConfidence: lastConfidence,
      lastDecisionRisk: lastDecisionRisk,
      lastAssumptions: lastAssumptions,
      lastClarifyReason: lastClarifyReason,
      lastImpactFields: lastImpactFields,
    );
  }

  OutfitContextState mergeFromAiResponse({
    Map<String, dynamic>? eventContext,
    double? confidence,
    String? decisionRisk,
    List<String>? assumptions,
    String? clarifyReason,
    List<String>? impactFields,
  }) {
    final raw = eventContext ?? const <String, dynamic>{};
    final loc = (raw['locationLabel'] ?? '').toString().trim();
    final locOk = loc.isNotEmpty &&
        StylistDestinationParser.isPlausibleDestination(loc);
    final hour = raw['hourLocal'];
    final parsedHour = hour is int
        ? hour
        : int.tryParse(hour?.toString() ?? '');

    return OutfitContextState(
      gpsDefaultCity: gpsDefaultCity,
      activityLocationLabel: locOk ? loc : activityLocationLabel,
      activityLocationKnown: locOk || activityLocationKnown,
      routineLocalOutfit: routineLocalOutfit,
      remoteActivityPlanned: remoteActivityPlanned,
      hourLocal: parsedHour ?? hourLocal,
      hourExplicit: hourExplicit || parsedHour != null,
      dateKey: (raw['dateKey'] ?? dateKey)?.toString(),
      activityHint: (raw['occasion'] ?? activityHint)?.toString(),
      occasion: (raw['occasion'] ?? occasion)?.toString(),
      clarifyRoundUsed: clarifyRoundUsed,
      clarifiedMaterialFields: clarifiedMaterialFields,
      lastConfidence: confidence ?? lastConfidence,
      lastDecisionRisk: decisionRisk ?? lastDecisionRisk,
      lastAssumptions: assumptions ?? lastAssumptions,
      lastClarifyReason: clarifyReason ?? lastClarifyReason,
      lastImpactFields: impactFields ?? lastImpactFields,
    );
  }

  Map<String, dynamic> toApiPayload() {
    return <String, dynamic>{
      if (gpsDefaultCity != null) 'gpsDefaultCity': gpsDefaultCity,
      if (activityLocationLabel != null)
        'activityLocationLabel': activityLocationLabel,
      'activityLocationKnown': activityLocationKnown,
      'routineLocalOutfit': routineLocalOutfit,
      'remoteActivityPlanned': remoteActivityPlanned,
      if (hourLocal != null) 'hourLocal': hourLocal,
      'hourExplicit': hourExplicit,
      if (dateKey != null) 'dateKey': dateKey,
      if (activityHint != null) 'activityHint': activityHint,
      if (occasion != null) 'occasion': occasion,
      'clarifyRoundUsed': clarifyRoundUsed,
      if (clarifiedMaterialFields.isNotEmpty)
        'clarifiedMaterialFields': clarifiedMaterialFields,
      if (lastConfidence != null) 'lastConfidence': lastConfidence,
      if (lastDecisionRisk != null) 'lastDecisionRisk': lastDecisionRisk,
      if (lastAssumptions.isNotEmpty) 'lastAssumptions': lastAssumptions,
      if (lastClarifyReason != null) 'lastClarifyReason': lastClarifyReason,
      if (lastImpactFields.isNotEmpty) 'lastImpactFields': lastImpactFields,
    };
  }

  static int? _extractHour(String blob) {
    final m = RegExp(
      r'(?:\b(o|okolo)\s*(\d{1,2})(?::\d{2})?|\b(\d{1,2}):\d{2}\b)',
      caseSensitive: false,
    ).firstMatch(blob);
    if (m == null) return null;
    final h = int.tryParse(m.group(2) ?? m.group(3) ?? '');
    if (h == null || h < 0 || h > 23) return null;
    return h;
  }

  static String? _extractActivityHint(String blob) {
    for (final hint in _remoteActivityHints) {
      if (blob.contains(hint)) return hint;
    }
    if (blob.contains('mest')) return 'mesto';
    if (blob.contains('rande')) return 'rande';
    if (blob.contains('koncert')) return 'koncert';
    if (blob.contains('reštaur') || blob.contains('restaur')) {
      return 'reštaurácia';
    }
    return null;
  }
}
