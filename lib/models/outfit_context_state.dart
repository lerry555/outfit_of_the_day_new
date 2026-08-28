import '../models/stylist_resolved_location.dart';
import '../utils/stylist_day_parser.dart';
import '../utils/stylist_destination_parser.dart';
import '../utils/stylist_semantic_activity.dart';
import '../utils/stylist_travel_context.dart';
import '../utils/stylist_trip_parser.dart';

/// Deterministic known context for one Stylist outfit request.
///
/// Activity/travel meaning comes from generic semantics. When
/// [providerLocationAuthorityEnabled] is true, geographic truth comes only
/// from a provider-verified [StylistResolvedLocation], never from a named-place
/// whitelist or an unchecked model field.
class OutfitContextState {
  final String? gpsDefaultCity;
  final String? activityLocationLabel;
  final bool activityLocationKnown;
  final bool providerLocationAuthorityEnabled;
  final bool locationProviderVerified;
  final String? locationGranularity;
  final bool locationNeedsSpecificity;
  final String? resolvedLocationDisplayName;
  final bool routineLocalOutfit;
  final bool remoteActivityPlanned;
  final int? hourLocal;
  final bool hourExplicit;
  final String? dateKey;
  final String? activityHint;
  final String? occasion;
  final String travelScope;
  final String transportMode;
  final bool transitOutfitExplicit;
  final bool arrivalWeatherUseful;
  final int? departureHourLocal;
  final int? arrivalHourLocal;
  final bool clarifyRoundUsed;
  final List<String> clarifiedMaterialFields;
  final double? lastConfidence;
  final String? lastDecisionRisk;
  final List<String> lastAssumptions;
  final String? lastClarifyReason;
  final List<String> lastImpactFields;
  final List<String> unresolvedMaterialFields;
  final String groundingStatus;
  final bool userCorrectionDetected;
  final List<String> semanticEvidenceTexts;

  const OutfitContextState({
    this.gpsDefaultCity,
    this.activityLocationLabel,
    this.activityLocationKnown = false,
    this.providerLocationAuthorityEnabled = false,
    this.locationProviderVerified = false,
    this.locationGranularity,
    this.locationNeedsSpecificity = false,
    this.resolvedLocationDisplayName,
    this.routineLocalOutfit = false,
    this.remoteActivityPlanned = false,
    this.hourLocal,
    this.hourExplicit = false,
    this.dateKey,
    this.activityHint,
    this.occasion,
    this.travelScope = 'none',
    this.transportMode = 'unknown',
    this.transitOutfitExplicit = false,
    this.arrivalWeatherUseful = false,
    this.departureHourLocal,
    this.arrivalHourLocal,
    this.clarifyRoundUsed = false,
    this.clarifiedMaterialFields = const [],
    this.lastConfidence,
    this.lastDecisionRisk,
    this.lastAssumptions = const [],
    this.lastClarifyReason,
    this.lastImpactFields = const [],
    this.unresolvedMaterialFields = const [],
    this.groundingStatus = 'sufficient',
    this.userCorrectionDetected = false,
    this.semanticEvidenceTexts = const [],
  });

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

  static OutfitContextState buildFrom({
    required String conversation,
    required String gpsCityLabel,
    OutfitContextState? previous,
    String latestUserText = '',
    StylistResolvedLocation? resolvedLocation,
    bool preferProviderLocation = false,
  }) {
    final blob = conversation.toLowerCase();
    final latest = latestUserText.trim().isEmpty ? conversation : latestUserText;
    final correction = _isCorrectionOrChallenge(latest);
    final correctionChangesPlaceOrActivity =
        correction && _changesPlaceOrActivity(latest);
    final gps = gpsCityLabel.split(',').first.trim();

    final travel = StylistTravelContextResolver.resolve(conversation);
    final latestTravel = StylistTravelContextResolver.resolve(latest);

    final providerSpecific = resolvedLocation?.weatherSpecific == true;
    final providerBroad = resolvedLocation?.needsMoreSpecificity == true;
    final latestInferred = preferProviderLocation
        ? null
        : StylistDestinationParser.inferFromConversation(latest);
    final legacyInferred = correctionChangesPlaceOrActivity
        ? null
        : latestInferred ??
              previous?.activityLocationLabel ??
              (preferProviderLocation
                  ? null
                  : StylistDestinationParser.inferFromConversation(conversation));
    final legacyInferredOk =
        legacyInferred != null &&
        legacyInferred.trim().isNotEmpty &&
        StylistDestinationParser.isPlausibleDestination(legacyInferred);
    final locationLabel = providerSpecific
        ? resolvedLocation!.weatherLabel.trim()
        : legacyInferredOk
            ? legacyInferred
            : null;
    final locationKnown = providerSpecific || legacyInferredOk;

    final remote =
        travel.travelMentioned ||
        StylistSemanticActivity.looksRemotePlan(blob) ||
        _isMultiDay(blob) ||
        resolvedLocation != null ||
        (locationKnown &&
            gps.isNotEmpty &&
            locationLabel!.toLowerCase() != gps.toLowerCase());
    final routine =
        _routineLocalHints.any(blob.contains) &&
        !remote &&
        !blob.contains('zajtra') &&
        !blob.contains('pozajtra');

    final trip = StylistTripParser.parseFromConversation(conversation);
    final hourFromText = trip.eventStartHour ?? _extractHour(blob);
    final hourExplicit =
        hourFromText != null ||
        blob.contains('teraz') ||
        blob.contains('hned') ||
        blob.contains('ihned');

    final date =
        StylistDayParser.resolveDate(latest) ??
        StylistDayParser.resolveDate(conversation);
    String? dateKey;
    if (date != null) {
      dateKey =
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
    } else if (blob.contains('zajtra')) {
      dateKey = 'tomorrow';
    } else if (blob.contains('dnes')) {
      dateKey = 'today';
    }

    final activityLocationKnown = locationKnown || (routine && gps.isNotEmpty);
    final latestActivityHint = StylistSemanticActivity.resolveExplicit(latest);
    final activityHint = correctionChangesPlaceOrActivity
        ? latestActivityHint ??
              (latestTravel.transitOutfitExplicit ? 'travel' : null)
        : latestActivityHint ??
              (latestTravel.transitOutfitExplicit ? 'travel' : null) ??
              previous?.activityHint ??
              StylistSemanticActivity.resolveExplicit(conversation) ??
              (travel.transitOutfitExplicit ? 'travel' : null);

    final unresolved = _materialUnknowns(
      remote: remote,
      routine: routine,
      locationKnown: locationKnown,
      providerBroad: providerBroad,
      activityHint: activityHint,
      dateKnown: dateKey != null,
      conversation: conversation,
      latest: latest,
      travel: travel,
    );

    return OutfitContextState(
      gpsDefaultCity: gps.isNotEmpty ? gps : null,
      activityLocationLabel: locationLabel,
      activityLocationKnown: activityLocationKnown,
      providerLocationAuthorityEnabled: preferProviderLocation,
      locationProviderVerified: resolvedLocation?.providerVerified == true,
      locationGranularity: resolvedLocation?.granularity.name,
      locationNeedsSpecificity: providerBroad,
      resolvedLocationDisplayName: resolvedLocation?.displayName,
      routineLocalOutfit: routine,
      remoteActivityPlanned: remote,
      hourLocal: hourFromText,
      hourExplicit: hourExplicit,
      dateKey: dateKey,
      activityHint: activityHint,
      occasion: previous?.occasion,
      travelScope: travel.scope.wireName,
      transportMode: travel.transportMode.wireName,
      transitOutfitExplicit: travel.transitOutfitExplicit,
      arrivalWeatherUseful: travel.arrivalWeatherCouldHelp,
      departureHourLocal: travel.departureHourLocal,
      arrivalHourLocal: travel.arrivalHourLocal,
      clarifyRoundUsed: previous?.clarifyRoundUsed ?? false,
      clarifiedMaterialFields: previous?.clarifiedMaterialFields ?? const [],
      lastConfidence: previous?.lastConfidence,
      lastDecisionRisk: previous?.lastDecisionRisk,
      lastAssumptions: previous?.lastAssumptions ?? const [],
      lastClarifyReason: previous?.lastClarifyReason,
      lastImpactFields: previous?.lastImpactFields ?? const [],
      unresolvedMaterialFields: unresolved,
      groundingStatus: unresolved.isEmpty ? 'sufficient' : 'needs_grounding',
      userCorrectionDetected: correction,
      semanticEvidenceTexts: _mergeEvidenceTexts(previous, latestUserText),
    );
  }

  OutfitContextState withClarifyRoundUsed(bool value) => _copy(
    clarifyRoundUsed: value,
    clarifiedMaterialFields: value ? clarifiedMaterialFields : const [],
  );

  OutfitContextState withClarificationAsked(Iterable<String> fields) {
    final merged = <String>{
      ...clarifiedMaterialFields.map((value) => value.trim().toLowerCase()),
      ...fields.map((value) => value.trim().toLowerCase()),
    }..removeWhere((value) => value.isEmpty);
    return _copy(
      clarifyRoundUsed: true,
      clarifiedMaterialFields: merged.toList(growable: false),
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
    final legacyLocOk =
        !providerLocationAuthorityEnabled &&
        loc.isNotEmpty &&
        StylistDestinationParser.isPlausibleDestination(loc);
    final hour = raw['hourLocal'];
    final parsedHour = hour is int ? hour : int.tryParse(hour?.toString() ?? '');
    final incomingActivity = StylistSemanticActivity.canonicalize(
      raw['occasion']?.toString(),
    );

    final unresolved = unresolvedMaterialFields.toSet();
    if (legacyLocOk || activityLocationKnown) unresolved.remove('destination');
    if ((raw['dateKey'] ?? '').toString().trim().isNotEmpty) {
      unresolved.remove('date');
    }
    if (incomingActivity != null) unresolved.remove('activity');

    final nextUnresolved = unresolved.toList(growable: false);
    return OutfitContextState(
      gpsDefaultCity: gpsDefaultCity,
      activityLocationLabel: legacyLocOk ? loc : activityLocationLabel,
      activityLocationKnown: legacyLocOk || activityLocationKnown,
      providerLocationAuthorityEnabled: providerLocationAuthorityEnabled,
      locationProviderVerified: locationProviderVerified,
      locationGranularity: locationGranularity,
      locationNeedsSpecificity: locationNeedsSpecificity,
      resolvedLocationDisplayName: resolvedLocationDisplayName,
      routineLocalOutfit: routineLocalOutfit,
      remoteActivityPlanned: remoteActivityPlanned,
      hourLocal: parsedHour ?? hourLocal,
      hourExplicit: hourExplicit || parsedHour != null,
      dateKey: (raw['dateKey'] ?? dateKey)?.toString(),
      activityHint: incomingActivity ?? activityHint,
      occasion: (raw['occasion'] ?? occasion)?.toString(),
      travelScope: travelScope,
      transportMode: transportMode,
      transitOutfitExplicit: transitOutfitExplicit,
      arrivalWeatherUseful: arrivalWeatherUseful,
      departureHourLocal: departureHourLocal,
      arrivalHourLocal: arrivalHourLocal,
      clarifyRoundUsed: clarifyRoundUsed,
      clarifiedMaterialFields: clarifiedMaterialFields,
      lastConfidence: confidence ?? lastConfidence,
      lastDecisionRisk: decisionRisk ?? lastDecisionRisk,
      lastAssumptions: assumptions ?? lastAssumptions,
      lastClarifyReason: clarifyReason ?? lastClarifyReason,
      lastImpactFields: impactFields ?? lastImpactFields,
      unresolvedMaterialFields: nextUnresolved,
      groundingStatus: nextUnresolved.isEmpty ? 'sufficient' : 'needs_grounding',
      userCorrectionDetected: userCorrectionDetected,
      semanticEvidenceTexts: semanticEvidenceTexts,
    );
  }

  Map<String, dynamic> toApiPayload() => <String, dynamic>{
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
    'locationContext': <String, dynamic>{
      'providerAuthorityEnabled': providerLocationAuthorityEnabled,
      'providerVerified': locationProviderVerified,
      if (activityLocationLabel != null) 'weatherLabel': activityLocationLabel,
      if (resolvedLocationDisplayName != null)
        'displayName': resolvedLocationDisplayName,
      if (locationGranularity != null) 'granularity': locationGranularity,
      'needsMoreSpecificity': locationNeedsSpecificity,
    },
    'travelContext': <String, dynamic>{
      'scope': travelScope,
      'transportMode': transportMode,
      'transitOutfitExplicit': transitOutfitExplicit,
      'destinationRequiredForPrimaryOutfit': !transitOutfitExplicit,
      'arrivalWeatherCouldHelp': arrivalWeatherUseful,
      if (departureHourLocal != null) 'departureHourLocal': departureHourLocal,
      if (arrivalHourLocal != null) 'arrivalHourLocal': arrivalHourLocal,
    },
    'clarifyRoundUsed': clarifyRoundUsed,
    if (clarifiedMaterialFields.isNotEmpty)
      'clarifiedMaterialFields': clarifiedMaterialFields,
    if (lastConfidence != null) 'lastConfidence': lastConfidence,
    if (lastDecisionRisk != null) 'lastDecisionRisk': lastDecisionRisk,
    if (lastAssumptions.isNotEmpty) 'lastAssumptions': lastAssumptions,
    if (lastClarifyReason != null) 'lastClarifyReason': lastClarifyReason,
    if (lastImpactFields.isNotEmpty)
      'lastImpactFields': lastImpactFields,
    if (unresolvedMaterialFields.isNotEmpty)
      'unresolvedMaterialFields': unresolvedMaterialFields,
    'groundingStatus': groundingStatus,
    if (userCorrectionDetected) 'userCorrectionDetected': true,
    if (semanticEvidenceTexts.isNotEmpty)
      'semanticEvidenceTexts': semanticEvidenceTexts,
  };

  OutfitContextState _copy({
    bool? clarifyRoundUsed,
    List<String>? clarifiedMaterialFields,
  }) => OutfitContextState(
    gpsDefaultCity: gpsDefaultCity,
    activityLocationLabel: activityLocationLabel,
    activityLocationKnown: activityLocationKnown,
    providerLocationAuthorityEnabled: providerLocationAuthorityEnabled,
    locationProviderVerified: locationProviderVerified,
    locationGranularity: locationGranularity,
    locationNeedsSpecificity: locationNeedsSpecificity,
    resolvedLocationDisplayName: resolvedLocationDisplayName,
    routineLocalOutfit: routineLocalOutfit,
    remoteActivityPlanned: remoteActivityPlanned,
    hourLocal: hourLocal,
    hourExplicit: hourExplicit,
    dateKey: dateKey,
    activityHint: activityHint,
    occasion: occasion,
    travelScope: travelScope,
    transportMode: transportMode,
    transitOutfitExplicit: transitOutfitExplicit,
    arrivalWeatherUseful: arrivalWeatherUseful,
    departureHourLocal: departureHourLocal,
    arrivalHourLocal: arrivalHourLocal,
    clarifyRoundUsed: clarifyRoundUsed ?? this.clarifyRoundUsed,
    clarifiedMaterialFields:
        clarifiedMaterialFields ?? this.clarifiedMaterialFields,
    lastConfidence: lastConfidence,
    lastDecisionRisk: lastDecisionRisk,
    lastAssumptions: lastAssumptions,
    lastClarifyReason: lastClarifyReason,
    lastImpactFields: lastImpactFields,
    unresolvedMaterialFields: unresolvedMaterialFields,
    groundingStatus: groundingStatus,
    userCorrectionDetected: userCorrectionDetected,
    semanticEvidenceTexts: semanticEvidenceTexts,
  );

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

  static List<String> _materialUnknowns({
    required bool remote,
    required bool routine,
    required bool locationKnown,
    required bool providerBroad,
    required String? activityHint,
    required bool dateKnown,
    required String conversation,
    required String latest,
    required StylistTravelContext travel,
  }) {
    if (routine && !remote) return const [];
    final result = <String>[];
    final genericActivity =
        activityHint == null ||
        (activityHint == 'travel' && !travel.transitOutfitExplicit);

    if (remote &&
        (providerBroad || !locationKnown) &&
        travel.destinationRequiredForPrimaryOutfit) {
      result.add('destination');
    }
    if (remote && genericActivity) result.add('activity');
    if (remote &&
        !dateKnown &&
        (_isMultiDay(conversation) ||
            RegExp(
              r'\b(?:víkend|vikend|weekend)\b',
              caseSensitive: false,
            ).hasMatch(conversation))) {
      result.add('date');
    }
    if (_isMultiDay(conversation) &&
        remote &&
        !travel.transitOutfitExplicit &&
        !_tripScopeResolved(conversation)) {
      result.add('trip_scope');
    }
    if (_isCorrectionOrChallenge(latest) &&
        result.isEmpty &&
        !locationKnown &&
        travel.destinationRequiredForPrimaryOutfit) {
      result.addAll(const ['destination', 'activity']);
    }
    return result.toSet().toList(growable: false);
  }

  static bool _isMultiDay(String value) => RegExp(
    r'\b(?:\d+|jeden|jedna|dva|dve|tri|štyri|styri|päť|pat)\s+dni?\b',
    caseSensitive: false,
  ).hasMatch(value);

  static bool _tripScopeResolved(String value) => RegExp(
    r'\b(?:zobrat|zobrať|zbalit|zbaliť|balen|packing|jeden\s+outfit|konkrétny\s+outfit|outfit\s+na\s+(?:cestu|večeru|veceru|deň|den))\b',
    caseSensitive: false,
  ).hasMatch(value);

  static bool isMultiDayPackingRequest(String value) {
    if (!_isMultiDay(value)) return false;
    final explicitSingleOutfit = RegExp(
      r'\b(?:jeden|konkrétny|konkretny)\s+outfit\b|\boutfit\s+na\s+(?:jeden\s+)?(?:deň|den|večeru|veceru|cestu)\b',
      caseSensitive: false,
    ).hasMatch(value);
    if (explicitSingleOutfit) return false;
    return RegExp(
      r'(?:zobrat|zobrať|zbalit|zbaliť|balen|packing)',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static bool _isCorrectionOrChallenge(String value) {
    final text = value.toLowerCase().trim();
    return text.contains('kde som tvrdil') ||
        text.contains('to som nepoved') ||
        text.contains('to som nehovor') ||
        text.contains('ja nejdem') ||
        text.contains('nejdeme ') ||
        text.contains('nie zajtra') ||
        text.contains('nie dnes') ||
        text.startsWith('pardon nie') ||
        text.startsWith('nie,') ||
        text.startsWith('nie ');
  }

  static bool _changesPlaceOrActivity(String value) {
    final normalized = StylistSemanticActivity.normalize(value);
    return _isCorrectionOrChallenge(value) &&
        (StylistSemanticActivity.resolveExplicit(value) != null ||
            StylistTravelContextResolver.resolve(value).travelMentioned ||
            RegExp(
              r'\b(?:mesto\w*|centrum\w*|les\w*|hor\w*|prirod\w*|park\w*|plaz\w*|letisk\w*|hotel\w*|restaur\w*|lokalit\w*|destin\w*)\b',
            ).hasMatch(normalized));
  }

  static List<String> _mergeEvidenceTexts(
    OutfitContextState? previous,
    String latestUserText,
  ) {
    final latest = latestUserText.trim();
    final values = <String>[
      ...?previous?.semanticEvidenceTexts,
      if (latest.isNotEmpty) latest,
    ];
    final deduped = <String>[];
    for (final value in values) {
      if (!deduped.contains(value)) deduped.add(value);
    }
    if (deduped.length <= 6) return deduped;
    return deduped.sublist(deduped.length - 6);
  }
}
