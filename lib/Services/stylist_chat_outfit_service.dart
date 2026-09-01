import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/outfit_intent.dart';
import '../data/stylist_opinion.dart';
import '../data/wardrobe_analysis.dart';
import '../debug/stylist_chat_outfit_debug_collector.dart';
import '../models/stylist_trip_window.dart';
import '../models/stylist_chat_progress.dart';
import '../utils/activity_outfit_identity.dart';
import '../utils/comfort_target.dart';
import '../utils/footwear_family_guidance.dart';
import '../utils/layer_harmony_guard.dart';
import '../utils/outfit_intent_builder.dart';
import '../utils/outfit_intent_scorer.dart';
import '../utils/stylist_chat_candidate_pipeline.dart';
import '../utils/stylist_chat_wardrobe_read_path.dart';
import '../utils/stylist_intent_matrix_generator.dart';
import '../utils/stylist_intent_resolver.dart';
import '../utils/stylist_occasion_guidance.dart';
import '../utils/stylist_layer_filter.dart';
import '../utils/stylist_opinion_engine.dart';
import '../utils/stylist_swap_request.dart';
import '../utils/stylist_activity_terrain.dart';
import '../utils/stylist_weather_tip.dart';
import '../utils/bottom_family_guidance.dart';
import '../utils/stylist_weather_adjustment.dart';
import '../utils/trip_weather_analyzer.dart';
import '../utils/wardrobe_gap_analysis.dart';
import '../utils/wardrobe_image_url_priority.dart';
import '../domain/wardrobe_v2/wardrobe_item_v2.dart';
import '../domain/wardrobe_v2/wardrobe_v2_adapters.dart';
import '../domain/wardrobe_v2/wardrobe_v2_resolver.dart';
import '../domain/wardrobe_v2/flexible_outfit_result_v2.dart';
import '../domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import '../domain/wardrobe_v2/native_outfit_engine_v2.dart';
import '../domain/wardrobe_v2/outfit_composition_v2.dart';
import '../domain/wardrobe_v2/outfit_suitability_policy_v2.dart';
import '../domain/wardrobe_v2/functional_suitability_v1.dart';
import '../domain/wardrobe_v2/outfit_edit_executor_v1.dart';
import '../domain/wardrobe_v2/outfit_edit_plan_v1.dart';
import '../domain/style_preferences/style_preferences_runtime.dart';
import '../Services/hourly_weather_service.dart';
import '../Services/outfit_generation_service.dart';
import 'stylist_frozen_candidate_decision_service.dart';
import 'user_location_service.dart';
import 'native_wardrobe_v2_runtime.dart';
import 'user_style_preferences_reader.dart';

class StylistChatOutfitResult {
  const StylistChatOutfitResult({
    required this.flexibleOutfit,
    required this.wardrobeAnalysis,
    this.weather,
    this.occasionProfile,
    this.wetGroundMuddy = false,
    this.outfitIntent,
    this.activityIdentity,
    this.stylistOpinion,
    this.finalExplanation,
    this.rejectAllReasonCodes = const <String>[],
    this.functionalAssessment,
  });

  final V2FlexibleOutfitResult flexibleOutfit;
  final WardrobeAnalysis wardrobeAnalysis;

  /// Kontext výberu — vyplnený pri bežnom výbere, pre debug report a AI explain.
  final OutfitWeatherSnapshot? weather;
  final StylistOccasionProfile? occasionProfile;
  final bool wetGroundMuddy;
  final OutfitIntent? outfitIntent;
  final ActivityIdentityResult? activityIdentity;
  final StylistOpinion? stylistOpinion;

  /// Immutable Claude explanation generated only after the server accepted the
  /// frozen candidate decision. It has no authority to alter this outfit.
  final String? finalExplanation;
  final List<String> rejectAllReasonCodes;
  final CandidateFunctionalAssessmentV1? functionalAssessment;
}

/// Explicit swap requests must either return their validated replacement or
/// leave the displayed outfit unchanged. They must never fall back to an
/// unrelated matrix candidate.
V2FlexibleOutfitResult requireExplicitStylistSwapReplacementV1(
  V2FlexibleOutfitResult? replacement,
) {
  if (replacement == null || replacement.validate().isNotEmpty) {
    throw const StylistFrozenDecisionRejectedExceptionV1(
      <String>['swap_replacement_unavailable'],
      explanation:
          'Nenašiel som bezpečnú a vhodnú náhradu pre požadovanú výmenu, preto pôvodný outfit nemením.',
    );
  }
  return replacement;
}

class StylistChatEventContext {
  final DateTime date;
  final int? hourLocal;
  final String locationLabel;
  final String? occasion;
  final String? performer;
  final Map<String, dynamic>? dressCode;
  final StylistTripWindow tripWindow;
  final int? durationMinutes;

  const StylistChatEventContext({
    required this.date,
    this.hourLocal,
    this.locationLabel = '',
    this.occasion,
    this.performer,
    this.dressCode,
    this.tripWindow = const StylistTripWindow(),
    this.durationMinutes,
  });

  int? get eventStartHour => tripWindow.eventStartHour ?? hourLocal;

  StylistTripWindow get effectiveTripWindow {
    if (tripWindow.eventStartHour == null && hourLocal != null) {
      return StylistTripWindow(
        tripStartHour: tripWindow.tripStartHour,
        eventStartHour: hourLocal,
        eventEndHour: tripWindow.eventEndHour,
        tripEndHour: tripWindow.tripEndHour,
        tripEndEstimated: tripWindow.tripEndEstimated,
      );
    }
    return tripWindow;
  }

  factory StylistChatEventContext.fromDynamic(
    Map<String, dynamic>? raw, {
    required DateTime now,
  }) {
    if (raw == null || raw.isEmpty) {
      return StylistChatEventContext(
        date: DateTime(now.year, now.month, now.day),
      );
    }
    final dateKey = (raw['dateKey'] ?? '').toString().trim().toLowerCase();
    DateTime date;
    if (dateKey == 'tomorrow' || dateKey == 'zajtra') {
      final today = DateTime(now.year, now.month, now.day);
      date = today.add(const Duration(days: 1));
    } else if (dateKey == 'today' || dateKey == 'dnes' || dateKey.isEmpty) {
      date = DateTime(now.year, now.month, now.day);
    } else {
      final parts = dateKey.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]) ?? now.year;
        final m = int.tryParse(parts[1]) ?? now.month;
        final d = int.tryParse(parts[2]) ?? now.day;
        date = DateTime(y, m, d);
      } else {
        date = DateTime(now.year, now.month, now.day);
      }
    }
    final hourRaw = raw['hourLocal'] ?? raw['hour'];
    final hour = hourRaw == null ? null : int.tryParse(hourRaw.toString());
    final location = (raw['locationLabel'] ?? raw['location'] ?? '')
        .toString()
        .trim();
    final occasion = (raw['occasion'] ?? '').toString().trim();
    final dressCodeRaw = raw['dressCode'];
    final dressCode = dressCodeRaw is Map
        ? Map<String, dynamic>.from(dressCodeRaw)
        : null;
    final performer = (raw['performer'] ?? raw['artist'] ?? '')
        .toString()
        .trim();
    final tripFromRaw = StylistTripWindow.fromDynamic(raw);
    return StylistChatEventContext(
      date: date,
      hourLocal: hour,
      locationLabel: location,
      occasion: occasion.isEmpty ? null : occasion,
      performer: performer.isEmpty ? null : performer,
      dressCode: dressCode,
      tripWindow: tripFromRaw,
      durationMinutes: _durationMinutes(raw, tripFromRaw),
    );
  }

  static int? _durationMinutes(
    Map<String, dynamic> raw,
    StylistTripWindow trip,
  ) {
    final direct = int.tryParse(
      (raw['durationMinutes'] ?? raw['eventDurationMinutes'] ?? '').toString(),
    );
    if (direct != null && direct > 0 && direct <= 7 * 24 * 60) return direct;
    final start = trip.eventStartHour ?? trip.tripStartHour;
    final end = trip.eventEndHour ?? trip.tripEndHour;
    if (start != null && end != null && end > start) return (end - start) * 60;
    return null;
  }
}

class StylistChatOutfitService {
  StylistChatOutfitService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    HourlyWeatherService? hourlyWeatherService,
    UserStylePreferencesReader? stylePreferencesReader,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _hourlyWeatherService = hourlyWeatherService ?? HourlyWeatherService(),
       _stylePreferencesReader =
           stylePreferencesReader ??
           UserStylePreferencesReader(firestore: firestore, auth: auth);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final HourlyWeatherService _hourlyWeatherService;
  final UserStylePreferencesReader _stylePreferencesReader;

  Future<StylistChatOutfitResult?> generateForEvent({
    required StylistChatEventContext event,
    List<String> excludeItemKeywords = const [],
    Set<String> excludedItemIds = const {},
    Set<String> previousOutfitItemIds = const {},
    bool forceDifferentOutfit = false,
    String? conversationHint,
    String? groundedActivityType,
    BottomFamily? requestedBottomFamily,
    StylistSwapRequest? requestedSwap,
    OutfitEditPlanV1? outfitEditPlan,
    bool optionalUpperLayerRequested = false,
    bool preserveCurrentOutfit = false,
    String requiredUpperLayerFamily = '',
    List<Set<String>> recentOutfitItemIdSets = const <Set<String>>[],
    String presentationMode = 'normal',
    String userRequest = '',
    StylistChatOutfitDebugCollector? debugCollector,
    StylistChatProgressCallback? onProgress,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    onProgress?.call(StylistChatProgressPhase.analyzingWardrobe);
    final wardrobe = await _loadNormalizedWardrobe(user.uid);
    if (wardrobe.isEmpty) return null;
    final stylePreferences = await _stylePreferencesReader.loadForUid(user.uid);
    final city = event.locationLabel.trim().isNotEmpty
        ? event.locationLabel
        : UserLocationService.instance.cityLabel;
    final dayWeather = await _hourlyWeatherService.getWeatherForCityAndDate(
      city: city,
      date: event.date,
    );
    final weather = _weatherSnapshotFromDay(
      dayWeather,
      event,
      conversationHint: conversationHint,
    );
    final terrain = StylistActivityTerrainClassifier.classify(
      conversationText: conversationHint,
      occasion: event.occasion,
      groundedActivityType: groundedActivityType,
    );
    // Fetch antecedent precipitation only when terrain makes it material. A
    // dry-looking start time must not erase yesterday's rain from a forest or
    // trail footwear decision, while ordinary city chats incur no extra call.
    final antecedentDay = terrain == StylistActivityTerrain.wetGround
        ? await _hourlyWeatherService.getWeatherForCityAndDate(
            city: city,
            date: event.date.subtract(const Duration(days: 1)),
          )
        : null;
    final antecedentPrecipitation =
        antecedentDay != null &&
        antecedentDay.fromOpenMeteo &&
        antecedentDay.willRain;
    if (terrain == StylistActivityTerrain.wetGround) {
      debugPrint(
        'STYLIST CHAT antecedent_weather '
        'available=${antecedentDay?.fromOpenMeteo ?? false} '
        'rain=$antecedentPrecipitation',
      );
    }
    final wetGroundMuddy =
        StylistWeatherTipBuilder.wetGroundNeedsClosedFootwear(
          snapshot: dayWeather,
          now: DateTime.now(),
          terrain: terrain,
          eventHour: event.hourLocal,
          antecedentPrecipitation: antecedentPrecipitation,
        );
    final occasionProfile = StylistOccasionGuidance.profileFor(
      occasion: event.occasion,
      conversationText: conversationHint,
      tempC: weather.tempC,
      dressCodeFromAi: event.dressCode,
      groundedActivityType: groundedActivityType,
    );
    final stylistIntent = StylistIntentResolver.resolve(
      occasion: event.occasion,
      conversationText: conversationHint,
      aiDressCode: event.dressCode,
      tempC: weather.tempC,
      groundedActivityType: groundedActivityType,
    );
    final footwearGuidance = StylistOccasionGuidance.footwearGuidanceFor(
      weather: weather,
      profile: occasionProfile,
      wetGroundMuddy: wetGroundMuddy,
    );
    final bottomGuidance = StylistOccasionGuidance.bottomGuidanceFor(
      weather: weather,
      profile: occasionProfile,
    );
    final outfitIntent = OutfitIntentBuilder.build(
      stylistIntent: stylistIntent,
      dressCode: occasionProfile.dressCode,
      bottomGuidance: bottomGuidance,
      footwearGuidance: footwearGuidance,
      wetGroundMuddy: wetGroundMuddy,
    );
    final excluded = <String>{
      ...excludedItemIds,
      ..._idsMatchingExcludeKeywords(wardrobe, excludeItemKeywords),
    };
    onProgress?.call(StylistChatProgressPhase.buildingOutfit);
    final allResolved = NativeWardrobeV2Runtime.resolveAll(wardrobe);
    final resolved = allResolved
        .where((item) => !excluded.contains(item.itemId))
        .where((item) {
          if (requestedBottomFamily == null) return true;
          if (!item.item.bodySlots.contains('lower_body')) return true;
          return _matchesRequestedBottomV2(item.item, requestedBottomFamily);
        })
        .where((item) {
          if (requiredUpperLayerFamily.trim().isEmpty) return true;
          final isOptionalUpperLayer =
              const {
                'mid',
                'outer',
                'shell',
              }.contains(item.item.layerPosition) &&
              item.item.bodySlots.contains('upper_body');
          if (!isOptionalUpperLayer) return true;
          return _matchesRequiredUpperLayerFamily(
            item.item.canonicalType,
            requiredUpperLayerFamily,
          );
        })
        .toList(growable: false);
    if (resolved.isEmpty) return null;
    final context = V2CandidateMatrixContext(
      weatherProtectionRequired:
          weather.isRainy || weather.isWindy || wetGroundMuddy,
      minimumFormality: occasionProfile.isElevated ? 5 : 1,
      requiredOccasions: {occasionProfile.dressCode.id},
      maxCandidates: 6,
      tempC: weather.tempC,
      seasonKey: weather.seasonKey,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
      activityType: outfitIntent.activityType,
      occasionId: occasionProfile.dressCode.id,
      styleTaste: StylePreferencesRuntime.effectiveTaste(stylePreferences),
      stylingPresentation: StylePreferencesRuntime.effectivePresentation(
        stylePreferences,
      ),
      activityDurationMinutes: event.durationMinutes,
      terrain: terrain.name,
      wetGroundRisk: wetGroundMuddy,
      optionalUpperLayerRequested: optionalUpperLayerRequested,
    );
    final frozenResolvedContext = <String, dynamic>{
      'activity': outfitIntent.activityType,
      'occasion': occasionProfile.label,
      'environment': event.locationLabel,
      'weather':
          '${weather.tempC}C rain=${weather.isRainy} '
          'wind=${weather.isWindy} wetGround=$wetGroundMuddy '
          'antecedentRain=$antecedentPrecipitation',
      'formality': occasionProfile.dressCode.id,
      'terrain': terrain.name,
      if ((conversationHint ?? '').trim().isNotEmpty)
        'userIntentContext': conversationHint!.trim(),
      if (outfitEditPlan != null) 'outfitEditPlan': outfitEditPlan.toMap(),
      'relevantKnownTimingFacts': <String, String>{
        'eventDate':
            '${event.date.year.toString().padLeft(4, '0')}-'
            '${event.date.month.toString().padLeft(2, '0')}-'
            '${event.date.day.toString().padLeft(2, '0')}',
        'dayRelation': _dayRelation(event.date),
        if (event.eventStartHour != null)
          'eventStartHourLocal': event.eventStartHour.toString(),
      },
    };
    if (outfitEditPlan?.intent == OutfitEditIntentV1.editCurrentOutfit) {
      if (previousOutfitItemIds.isEmpty) {
        throw const StylistFrozenDecisionRejectedExceptionV1(
          <String>['current_outfit_missing'],
          explanation:
              'Aktuálny outfit nemám spoľahlivo uložený, preto ho nechcem čiastočne meniť.',
        );
      }
      final current = OutfitEditExecutorV1.restoreCurrent(
        wardrobe: allResolved,
        currentItemIds: previousOutfitItemIds,
        context: context,
      );
      if (current == null) {
        throw const StylistFrozenDecisionRejectedExceptionV1(
          <String>['current_outfit_restore_failed'],
          explanation:
              'Aktuálny outfit sa mi nepodarilo presne obnoviť podľa kúskov, preto ho nemením.',
        );
      }
      final editCandidates = OutfitEditExecutorV1.generateCandidates(
        plan: outfitEditPlan!,
        current: current,
        wardrobe: allResolved,
        context: context,
      );
      if (editCandidates.isEmpty) {
        throw const StylistFrozenDecisionRejectedExceptionV1(
          <String>['atomic_outfit_edit_unavailable'],
          explanation:
              'Všetky požadované zmeny naraz sa mi nepodarilo bezpečne splniť, takže pôvodný outfit nechávam bez zmeny.',
        );
      }
      onProgress?.call(StylistChatProgressPhase.finalizing);
      final decision = await const StylistFrozenCandidateDecisionServiceV1()
          .resolve(
            candidates: editCandidates,
            resolvedContext: frozenResolvedContext,
            presentationMode: outfitEditPlan.presentation,
            userRequest: userRequest,
          );
      final selectedId = decision.selectedCandidateId;
      final accepted = selectedId == null
          ? null
          : editCandidates
                .where((candidate) => candidate.candidateId == selectedId)
                .firstOrNull;
      if (!decision.selected || accepted == null) {
        throw StylistFrozenDecisionRejectedExceptionV1(
          decision.reasonCodes.isEmpty
              ? const <String>['atomic_outfit_edit_rejected']
              : decision.reasonCodes,
          explanation: decision.explanation,
        );
      }
      return StylistChatOutfitResult(
        flexibleOutfit: accepted.outfit,
        wardrobeAnalysis: _wardrobeGapAnalysisV2(
          accepted.outfit,
          accepted.functionalAssessment,
        ),
        weather: weather,
        occasionProfile: occasionProfile,
        wetGroundMuddy: wetGroundMuddy,
        outfitIntent: outfitIntent,
        activityIdentity: ActivityOutfitIdentity.evaluateFlexible(
          outfit: accepted.outfit,
          intent: outfitIntent,
          wetGroundMuddy: wetGroundMuddy,
        ),
        finalExplanation: decision.explanation.trim().isEmpty
            ? null
            : decision.explanation.trim(),
        rejectAllReasonCodes: decision.reasonCodes,
        functionalAssessment: accepted.functionalAssessment,
      );
    }
    var generated = V2FlexibleCandidateMatrix.generate(
      wardrobe: resolved,
      context: context,
    );
    if (generated.isEmpty) {
      generated = V2FlexibleCandidateMatrix.generate(
        wardrobe: resolved,
        context: V2CandidateMatrixContext(
          weatherProtectionRequired: context.weatherProtectionRequired,
          minimumFormality: 1,
          maxCandidates: context.maxCandidates,
          tempC: context.tempC,
          seasonKey: context.seasonKey,
          isRainy: context.isRainy,
          isWindy: context.isWindy,
          activityType: context.activityType,
          occasionId: context.occasionId,
          styleTaste: context.styleTaste,
          stylingPresentation: context.stylingPresentation,
          activityDurationMinutes: context.activityDurationMinutes,
          terrain: context.terrain,
          wetGroundRisk: context.wetGroundRisk,
          optionalUpperLayerRequested: context.optionalUpperLayerRequested,
        ),
      );
    }
    if (generated.isEmpty) return null;
    final matrix =
        generated
            .map((candidate) {
              final warmthValues = candidate.outfit.items
                  .map((item) => item.item.warmth)
                  .toList(growable: false);
              final warmth = warmthValues.isEmpty
                  ? 0.0
                  : warmthValues.reduce((a, b) => a + b) / warmthValues.length;
              final targetWarmth = OutfitSuitabilityPolicyV2.targetMeanWarmth(weather.tempC);
              final comfort = (5 - (warmth - targetWarmth).abs())
                  .clamp(0, 5)
                  .toDouble();
              final intent = OutfitIntentScorer.evaluateFlexible(
                outfit: candidate.outfit,
                intent: outfitIntent,
                baseScore: comfort,
              );
              final activity = ActivityOutfitIdentity.evaluateFlexible(
                outfit: candidate.outfit,
                intent: outfitIntent,
                wetGroundMuddy: wetGroundMuddy,
              );
              return V2FlexibleCandidate(
                candidateId: candidate.candidateId,
                outfit: candidate.outfit,
                score: candidate.score + intent.finalScore + activity.score,
                scoreBreakdown: <String, double>{
                  ...candidate.scoreBreakdown,
                  'comfort': comfort,
                  'intent': intent.finalScore,
                  'activity': activity.score,
                },
                functionalAssessment: candidate.functionalAssessment,
              );
            })
            .where((candidate) => candidate.score > -900)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    if (matrix.isEmpty) return null;
    final matrixWithRequiredLayer = requiredUpperLayerFamily.trim().isEmpty
        ? matrix
        : matrix
              .where(
                (candidate) => candidate.outfit.items.any(
                  (item) =>
                      const {
                        'mid',
                        'outer',
                        'shell',
                      }.contains(item.item.layerPosition) &&
                      item.item.bodySlots.contains('upper_body') &&
                      _matchesRequiredUpperLayerFamily(
                        item.item.canonicalType,
                        requiredUpperLayerFamily,
                      ),
                ),
              )
              .toList(growable: false);
    if (requiredUpperLayerFamily.trim().isNotEmpty &&
        matrixWithRequiredLayer.isEmpty &&
        !preserveCurrentOutfit) {
      throw const StylistFrozenDecisionRejectedExceptionV1(
        <String>['required_user_layer_unavailable'],
        explanation:
            'V šatníku som nenašiel vhodnú požadovanú vrstvu, takže ju nechcem potichu vynechať.',
      );
    }

    onProgress?.call(StylistChatProgressPhase.finalizing);
    V2FlexibleOutfitResult? selected;
    String? finalExplanation;
    List<String> rejectAllReasonCodes = const <String>[];
    if (preserveCurrentOutfit &&
        requiredUpperLayerFamily.trim().isNotEmpty &&
        previousOutfitItemIds.isNotEmpty) {
      final current = _reconstructFrozenCurrentOutfit(
        wardrobe: wardrobe,
        previousOutfitItemIds: previousOutfitItemIds,
        context: context,
      );
      if (current == null) {
        throw const StylistFrozenDecisionRejectedExceptionV1(
          <String>['current_outfit_restore_failed'],
          explanation:
              'Aktuálny outfit sa mi nepodarilo bezpečne obnoviť, preto ti ho nechcem potichu prehádzať.',
        );
      }
      selected = _addRequiredUpperLayerToFrozenCurrent(
        current: current,
        wardrobe: resolved,
        context: context,
        requiredFamily: requiredUpperLayerFamily,
      );
      if (selected == null) {
        throw const StylistFrozenDecisionRejectedExceptionV1(
          <String>['required_user_layer_unavailable'],
          explanation:
              'K tomuto outfitu som v šatníku nenašiel vhodnú požadovanú vrstvu. Zvyšok outfitu som preto nezmenil.',
        );
      }
      final lockedCandidate = V2FlexibleCandidate(
        candidateId: 'locked_additive_layer',
        outfit: selected,
        score: 0,
        scoreBreakdown: const <String, double>{},
      );
      final lockedExplanation =
          await const StylistFrozenCandidateDecisionServiceV1().resolve(
            candidates: <V2FlexibleCandidate>[lockedCandidate],
            resolvedContext: frozenResolvedContext,
            lockedSelection: true,
            presentationMode: 'concise_full',
            userRequest: userRequest,
          );
      if (!lockedExplanation.selected) {
        throw StylistFrozenDecisionRejectedExceptionV1(
          lockedExplanation.reasonCodes,
          explanation: lockedExplanation.explanation,
        );
      }
      finalExplanation = lockedExplanation.explanation.trim().isEmpty
          ? null
          : lockedExplanation.explanation.trim();
    } else if (requestedSwap != null && previousOutfitItemIds.isNotEmpty) {
      final currentDocs = wardrobe.where((raw) {
        final id = OutfitGenerationService.wardrobeItemId(raw);
        return previousOutfitItemIds.contains(id);
      });
      final current = NativeWardrobeV2Runtime.recommend(
        documents: currentDocs,
        request: NativeOutfitRequestV2(
          weatherProtectionRequired: context.weatherProtectionRequired,
          minimumFormality: context.minimumFormality,
          tempC: context.tempC,
          feelsLikeC: context.feelsLikeC,
          eveningTempC: context.eveningTempC,
          seasonKey: context.seasonKey,
          activityType: context.activityType,
          optionalUpperLayerRequested: context.optionalUpperLayerRequested,
        ),
      );
      final target = current == null
          ? null
          : _swapTargetForV2(current, requestedSwap);
      if (current == null || target == null) {
        selected = requireExplicitStylistSwapReplacementV1(null);
      } else {
        selected = requireExplicitStylistSwapReplacementV1(
          V2FlexibleSwapOrchestrator.replace(
            current: current,
            itemId: target.itemId,
            wardrobe: resolved,
            context: context,
            // Any explicit one-slot swap may consider another compatible
            // family in the same body slot. This is a global swap invariant,
            // not a bottom/shorts exception; every other displayed item stays
            // frozen and the normal suitability guards still apply.
            allowCrossFamilySameSlot: true,
            requireCoolerReplacement:
                requestedSwap.thermalPreference ==
                StylistSwapThermalPreference.cooler,
            requireWarmerReplacement:
                requestedSwap.thermalPreference ==
                StylistSwapThermalPreference.warmer,
          ),
        );
        final lockedCandidate = V2FlexibleCandidate(
          candidateId: 'locked_swap',
          outfit: selected,
          score: 0,
          scoreBreakdown: const <String, double>{},
        );
        final lockedExplanation =
            await const StylistFrozenCandidateDecisionServiceV1().resolve(
              candidates: <V2FlexibleCandidate>[lockedCandidate],
              resolvedContext: frozenResolvedContext,
              lockedSelection: true,
              presentationMode: 'focused_item',
              focusSlot: requestedSwap.slot.name,
              userRequest: userRequest,
            );
        if (lockedExplanation.selected &&
            lockedExplanation.explanation.trim().isNotEmpty) {
          finalExplanation = lockedExplanation.explanation.trim();
        }
      }
    } else {
      final decisionPool = _preferNovelFullOutfitCandidates(
        requiredUpperLayerFamily.trim().isEmpty
            ? matrix
            : matrixWithRequiredLayer,
        recentOutfitItemIdSets,
      );
      final decision = await const StylistFrozenCandidateDecisionServiceV1()
          .resolve(
            candidates: decisionPool,
            resolvedContext: frozenResolvedContext,
            presentationMode: presentationMode,
            userRequest: userRequest,
          );
      final selectedId = decision.selectedCandidateId;
      if (!decision.selected || selectedId == null) {
        // Fail closed: no transport/malformed/provider path selects candidate 0.
        throw StylistFrozenDecisionRejectedExceptionV1(
          decision.reasonCodes,
          explanation: decision.explanation,
        );
      }
      final accepted = decisionPool
          .where((candidate) => candidate.candidateId == selectedId)
          .firstOrNull;
      if (accepted == null) return null;
      selected = accepted.outfit;
      finalExplanation = decision.explanation.isEmpty
          ? null
          : decision.explanation;
      rejectAllReasonCodes = decision.reasonCodes;
    }
    if (selected.validate().isNotEmpty) return null;
    final selectedAssessment = matrix
        .where((candidate) => candidate.outfit == selected)
        .firstOrNull
        ?.functionalAssessment;
    return StylistChatOutfitResult(
      flexibleOutfit: selected,
      wardrobeAnalysis: _wardrobeGapAnalysisV2(selected, selectedAssessment),
      weather: weather,
      occasionProfile: occasionProfile,
      wetGroundMuddy: wetGroundMuddy,
      outfitIntent: outfitIntent,
      activityIdentity: ActivityOutfitIdentity.evaluateFlexible(
        outfit: selected,
        intent: outfitIntent,
        wetGroundMuddy: wetGroundMuddy,
      ),
      finalExplanation: finalExplanation,
      rejectAllReasonCodes: rejectAllReasonCodes,
      functionalAssessment: selectedAssessment,
    );
  }

  static List<V2FlexibleCandidate> _preferNovelFullOutfitCandidates(
    List<V2FlexibleCandidate> candidates,
    List<Set<String>> recentSets,
  ) {
    if (candidates.length <= 1 || recentSets.isEmpty) return candidates;
    bool repeated(V2FlexibleCandidate candidate) {
      final ids = candidate.outfit.items.map((item) => item.itemId).toSet();
      return recentSets.any(
        (recent) => recent.length == ids.length && recent.containsAll(ids),
      );
    }

    final novel = candidates
        .where((candidate) => !repeated(candidate))
        .toList();
    return novel.isEmpty
        ? candidates
        : List<V2FlexibleCandidate>.unmodifiable(novel);
  }

  static bool _matchesRequiredUpperLayerFamily(
    String canonicalType,
    String family,
  ) {
    final type = canonicalType.trim().toLowerCase();
    return switch (family.trim().toLowerCase()) {
      'hoodie' => const {'hoodie', 'zip_hoodie', 'sweatshirt'}.contains(type),
      'sweater' => type.contains('sweater') || type.contains('pullover'),
      'cardigan' => type.contains('cardigan'),
      'blazer' => type.contains('blazer') || type.contains('suit_jacket'),
      'coat' => type.contains('coat') || type.contains('trench'),
      'jacket' =>
        type.contains('jacket') ||
            type.contains('parka') ||
            type.contains('windbreaker'),
      _ => true,
    };
  }

  static V2FlexibleOutfitResult? _reconstructFrozenCurrentOutfit({
    required List<Map<String, dynamic>> wardrobe,
    required Set<String> previousOutfitItemIds,
    required V2CandidateMatrixContext context,
  }) {
    final resolved = NativeWardrobeV2Runtime.resolveAll(wardrobe)
        .where((item) => previousOutfitItemIds.contains(item.itemId))
        .toList(growable: false);
    if (resolved.length != previousOutfitItemIds.length) return null;
    final hasOnePiece = resolved.any(
      (item) => item.item.bodySlots.contains('full_body'),
    );
    final compositionItems = <OutfitCompositionItemV2>[];
    for (final value in resolved) {
      final item = value.item;
      final String group;
      final CompositionRoleV2 role;
      final bool required;
      if (item.bodySlots.contains('feet')) {
        group = 'footwear';
        role = CompositionRoleV2.core;
        required = true;
      } else if (item.bodySlots.contains('full_body')) {
        group = 'full_body_core';
        role = CompositionRoleV2.core;
        required = true;
      } else if (item.bodySlots.contains('lower_body') &&
          !item.bodySlots.contains('upper_body')) {
        group = 'lower_body_core';
        role = CompositionRoleV2.core;
        required = true;
      } else if (const {'mid', 'outer', 'shell'}.contains(item.layerPosition)) {
        group = 'layer_${item.layerPosition}';
        role = CompositionRoleV2.conditional;
        required = false;
      } else if (item.bodySlots.contains('upper_body')) {
        group = 'upper_body_core';
        role = CompositionRoleV2.core;
        required = true;
      } else {
        group = item.accessoryGroup ?? 'finishing';
        role = CompositionRoleV2.finishing;
        required = false;
      }
      compositionItems.add(
        OutfitCompositionItemV2(
          itemId: value.itemId,
          item: item,
          role: role,
          compositionGroup: group,
          required: required,
          selectionReason: 'restore_frozen_current',
        ),
      );
    }
    final composition = OutfitCompositionV2(
      template: hasOnePiece
          ? OutfitTemplateV2.onePiece
          : OutfitTemplateV2.separates,
      items: compositionItems,
    );
    if (composition.compatibilityErrors().isNotEmpty) return null;
    final result = V2FlexibleOutfitResult.fromComposition(
      composition,
      weatherProtectionRequired: context.weatherProtectionRequired,
      minimumFormality: context.minimumFormality,
      requiredFunctions: context.requiredFunctions,
      displayByItemId: {for (final value in resolved) value.itemId: value.raw},
    );
    return result.validate().isEmpty ? result : null;
  }

  static V2FlexibleOutfitResult? _addRequiredUpperLayerToFrozenCurrent({
    required V2FlexibleOutfitResult current,
    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required V2CandidateMatrixContext context,
    required String requiredFamily,
  }) {
    final currentIds = current.items.map((item) => item.itemId).toSet();
    V2FlexibleOutfitResult? best;
    var bestScore = double.negativeInfinity;
    for (final candidate in wardrobe) {
      if (currentIds.contains(candidate.itemId)) continue;
      final item = candidate.item;
      if (!item.bodySlots.contains('upper_body') ||
          !const {'mid', 'outer', 'shell'}.contains(item.layerPosition) ||
          !_matchesRequiredUpperLayerFamily(
            item.canonicalType,
            requiredFamily,
          )) {
        continue;
      }
      if (OutfitSuitabilityPolicyV2.isPhysicallyUnsuitable(
        item,
        tempC: OutfitSuitabilityPolicyV2.effectiveTempC(
          tempC: context.tempC,
          feelsLikeC: context.feelsLikeC,
        ),
        seasonKey: context.seasonKey,
        isRainy: context.isRainy || context.weatherProtectionRequired,
        activityType: context.activityType,
      )) {
        continue;
      }
      final composition = OutfitCompositionV2(
        template: current.template,
        items: <OutfitCompositionItemV2>[
          ...current.toComposition().items,
          OutfitCompositionItemV2(
            itemId: candidate.itemId,
            item: item,
            role: CompositionRoleV2.conditional,
            compositionGroup: 'layer_user_required',
            required: true,
            selectionReason: 'user_required_additive_layer',
          ),
        ],
      );
      if (composition.compatibilityErrors().isNotEmpty) continue;
      final next = V2FlexibleOutfitResult.fromComposition(
        composition,
        weatherProtectionRequired: context.weatherProtectionRequired,
        minimumFormality: context.minimumFormality,
        requiredFunctions: context.requiredFunctions,
        displayByItemId: <String, Map<String, dynamic>>{
          for (final existing in current.items)
            existing.itemId: existing.display,
          candidate.itemId: candidate.raw,
        },
      );
      if (next.validate().isNotEmpty) continue;
      final breakdown = V2FlexibleOutfitScorer.score(next, context);
      final score = breakdown.values.fold(0.0, (a, b) => a + b);
      if (score > bestScore) {
        bestScore = score;
        best = next;
      }
    }
    return best;
  }

  @visibleForTesting
  static bool requiredLayerFamilyMatchesForTest(
    String canonicalType,
    String family,
  ) => _matchesRequiredUpperLayerFamily(canonicalType, family);

  static bool _matchesRequestedBottomV2(
    WardrobeItemV2 item,
    BottomFamily? family,
  ) {
    final type = item.canonicalType;
    return switch (family) {
      BottomFamily.shorts => type.contains('shorts'),
      BottomFamily.jeans => type == 'jeans',
      BottomFamily.pants =>
        type == 'trousers' || type == 'suit_trousers' || type == 'chinos',
      BottomFamily.joggers => type == 'sweatpants' || type == 'joggers',
      BottomFamily.other || null => true,
    };
  }

  static String _dayRelation(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final days = target.difference(today).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'future_date';
  }

  static V2FlexibleOutfitItem? _swapTargetForV2(
    V2FlexibleOutfitResult outfit,
    StylistSwapRequest request,
  ) {
    bool matches(V2FlexibleOutfitItem item) => switch (request.slot) {
      StylistSwapSlot.top =>
        item.item.bodySlots.contains('upper_body') &&
            item.compositionRole == CompositionRoleV2.core,
      StylistSwapSlot.bottom =>
        item.item.bodySlots.contains('lower_body') &&
            item.compositionRole == CompositionRoleV2.core,
      StylistSwapSlot.shoes => item.item.bodySlots.contains('feet'),
      StylistSwapSlot.outerwear =>
        item.item.layerPosition == 'outer' ||
            item.item.layerPosition == 'shell',
    };
    return outfit.items.where(matches).firstOrNull;
  }

  static WardrobeAnalysis _wardrobeGapAnalysisV2(
    V2FlexibleOutfitResult outfit,
    CandidateFunctionalAssessmentV1? functional,
  ) {
    final gaps = <WardrobeGap>[];
    if (!outfit.completeness.coreComplete) {
      gaps.add(
        const WardrobeGap(
          category: 'core_composition',
          reason: 'v2_core_incomplete',
          blocksIdealOutfit: true,
          explanationSk: 'Chýba povinný základ outfitu.',
        ),
      );
    }
    if (!outfit.completeness.weatherComplete) {
      gaps.add(
        const WardrobeGap(
          category: 'weather_protection',
          reason: 'v2_weather_gap',
          blocksIdealOutfit: false,
          explanationSk: 'Hodila by sa vhodná ochranná vrstva.',
        ),
      );
    }
    if (functional != null) {
      final capabilityGaps =
          <({String capability, ItemFunctionalAssessmentV1 item})>[
            for (final item in functional.items)
              for (final capability in item.missingCapabilities)
                (capability: capability, item: item),
          ]..sort((left, right) {
            final severity = right.item.tier.severity.compareTo(
              left.item.tier.severity,
            );
            if (severity != 0) return severity;
            return _gapPriority(
              left.capability,
            ).compareTo(_gapPriority(right.capability));
          });
      final seenCapabilities = <String>{};
      for (final entry in capabilityGaps) {
        if (!seenCapabilities.add(entry.capability)) continue;
        final capability = entry.capability;
        final item = entry.item;
        gaps.add(
          WardrobeGap(
            category: capability,
            reason: item.reasonCodes.isEmpty
                ? 'functional_capability_gap'
                : item.reasonCodes.first,
            blocksIdealOutfit:
                item.tier.severity >=
                FunctionalSuitabilityTierV1.strongCompromise.severity,
            explanationSk: item.idealReplacementDescription == null
                ? 'Ideálny outfit by potreboval lepšie pokryť: $capability.'
                : 'Časom by sa hodilo doplniť: '
                      '${item.idealReplacementDescription}.',
          ),
        );
      }
    }
    return WardrobeAnalysis(
      usedCompromise:
          functional != null &&
          functional.tier.severity >=
              FunctionalSuitabilityTierV1.acceptableCompromise.severity,
      missingItems: gaps,
      compromiseItems:
          functional?.items
              .where(
                (item) =>
                    item.tier.severity >=
                    FunctionalSuitabilityTierV1.acceptableCompromise.severity,
              )
              .map((item) => item.itemId)
              .toList(growable: false) ??
          const <String>[],
    );
  }

  static int _gapPriority(String capability) => switch (capability) {
    'hiking_footwear' => 0,
    'wet_terrain_footwear' => 1,
    'traction' || 'walking_stability' => 2,
    'rain_shell' || 'rain_protection' => 3,
    'hiking_bottom' || 'mobility' => 4,
    'activity_top' || 'breathability' || 'moisture_handling' => 5,
    _ => 20,
  };

  @visibleForTesting
  static WardrobeAnalysis wardrobeGapAnalysisForTest(
    V2FlexibleOutfitResult outfit,
    CandidateFunctionalAssessmentV1? functional,
  ) => _wardrobeGapAnalysisV2(outfit, functional);

  // Historical rollback implementation. It is unreachable from the active
  // Stylist entrypoint and may be deleted after owner-device E2E.
  // ignore: unused_element
  Future<StylistChatOutfitResult?> _legacyGenerateForEvent({
    required StylistChatEventContext event,
    List<String> excludeItemKeywords = const [],
    Set<String> excludedItemIds = const {},
    Set<String> previousOutfitItemIds = const {},
    bool forceDifferentOutfit = false,
    String? conversationHint,
    BottomFamily? requestedBottomFamily,
    StylistSwapRequest? requestedSwap,
    StylistChatOutfitDebugCollector? debugCollector,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final wardrobe = await _loadNormalizedWardrobe(user.uid);
    if (wardrobe.isEmpty) return null;

    final city = event.locationLabel.trim().isNotEmpty
        ? event.locationLabel
        : UserLocationService.instance.cityLabel;
    final dayWeather = await _hourlyWeatherService.getWeatherForCityAndDate(
      city: city,
      date: event.date,
    );
    final weather = _weatherSnapshotFromDay(
      dayWeather,
      event,
      conversationHint: conversationHint,
    );
    final terrain = StylistActivityTerrainClassifier.classify(
      conversationText: conversationHint,
      occasion: event.occasion,
    );
    final wetGroundMuddy =
        StylistWeatherTipBuilder.wetGroundNeedsClosedFootwear(
          snapshot: dayWeather,
          now: DateTime.now(),
          terrain: terrain,
          eventHour: event.hourLocal,
        );
    final occasionProfile = StylistOccasionGuidance.profileFor(
      occasion: event.occasion,
      conversationText: conversationHint,
      tempC: weather.tempC,
      dressCodeFromAi: event.dressCode,
    );
    final stylistIntent = StylistIntentResolver.resolve(
      occasion: event.occasion,
      conversationText: conversationHint,
      aiDressCode: event.dressCode,
      tempC: weather.tempC,
    );
    debugPrint(stylistIntent.toLogLine());
    debugCollector?.recordStylistIntent(stylistIntent);
    final keywordExcluded = _idsMatchingExcludeKeywords(
      wardrobe,
      excludeItemKeywords,
    );
    // Výslovná požiadavka „chcem šortky“ má prednosť pred dress-code vylúčením
    // šortiek, inak by sme používateľovi sľúbili šortky a ukázali nohavice.
    final userWantsShorts = requestedBottomFamily == BottomFamily.shorts;
    final occasionShortsExcluded =
        (occasionProfile.excludeShorts && !userWantsShorts)
        ? StylistOccasionGuidance.shortsItemIds(wardrobe)
        : const <String>{};
    final effectiveExcluded = <String>{
      ...excludedItemIds,
      ...keywordExcluded,
      ...occasionShortsExcluded,
    };
    // Keď si používateľ pýta konkrétnu rodinu spodku, nesmieme ju vylúčiť
    // (napr. AI omylom dá šortky do excludeItemKeywords).
    if (requestedBottomFamily != null) {
      final requestedIds = <String>{
        for (final item in wardrobe)
          if (classifyBottomFamily(item) == requestedBottomFamily)
            OutfitGenerationService.wardrobeItemId(item),
      }..removeWhere((id) => id.isEmpty);
      effectiveExcluded.removeAll(requestedIds);
    }

    final footwearGuidance = StylistOccasionGuidance.footwearGuidanceFor(
      weather: weather,
      profile: occasionProfile,
      wetGroundMuddy: wetGroundMuddy,
    );
    final footwearInventory = footwearFamilyInventoryFromWardrobe(wardrobe);
    final preferredFootwearExists = footwearInventory.hasPreferred(
      footwearGuidance,
    );
    final usablePreferredFootwearExists = hasUsablePreferredFootwear(
      wardrobe: wardrobe,
      guidance: footwearGuidance,
      excludedItemIds: effectiveExcluded,
    );
    final excludedDiscouragedFootwearIds = usablePreferredFootwearExists
        ? footwearInventory.idsForDiscouragedFamilies(footwearGuidance).toSet()
        : <String>{};

    final bottomGuidance = requestedBottomFamily != null
        ? forceBottomFamilyGuidance(
            family: requestedBottomFamily,
            base: StylistOccasionGuidance.bottomGuidanceFor(
              weather: weather,
              profile: occasionProfile,
            ),
          )
        : StylistOccasionGuidance.bottomGuidanceFor(
            weather: weather,
            profile: occasionProfile,
          );
    final outfitIntent = OutfitIntentBuilder.build(
      stylistIntent: stylistIntent,
      dressCode: occasionProfile.dressCode,
      bottomGuidance: bottomGuidance,
      footwearGuidance: footwearGuidance,
      wetGroundMuddy: wetGroundMuddy,
    );
    debugPrint(outfitIntent.toLogLine());
    debugCollector?.recordOutfitIntent(outfitIntent);
    var intentCandidateLogIndex = 0;
    double intentCombinationBonus(OutfitPreview preview) {
      final intentBonus = OutfitIntentScorer.combinationBonus(
        preview: preview,
        intent: outfitIntent,
      );
      final identity = ActivityOutfitIdentity.evaluate(
        preview: preview,
        intent: outfitIntent,
        wetGroundMuddy: wetGroundMuddy,
      );
      return intentBonus + identity.score;
    }

    void logIntentCandidate({
      required OutfitPreview preview,
      required OutfitIntentScoreBreakdown breakdown,
    }) {
      OutfitIntentScorer.logCandidate(
        candidateIndex: intentCandidateLogIndex++,
        preview: preview,
        breakdown: breakdown,
      );
      debugCollector?.recordCandidate(preview: preview, breakdown: breakdown);
    }

    final bottomInventory = bottomFamilyInventoryFromWardrobe(wardrobe);
    final preferredBottomExists = bottomInventory.hasPreferred(bottomGuidance);
    final usablePreferredBottomExists = hasUsablePreferredBottom(
      wardrobe: wardrobe,
      guidance: bottomGuidance,
      excludedItemIds: effectiveExcluded,
    );
    // ID-čka spodkov preferovanej rodiny (napr. v lete kraťasy). Použijeme ich
    // na VYNÚTENÉ vygenerovanie outfitu s preferovaným spodkom, ak by sa cez
    // bežné comfort-skórovanie nedostal medzi kandidátov (kraťasy pri 19 °C
    // inak prehrajú s nohavicami).
    final preferredBottomIds = preferredBottomExists
        ? bottomInventory.idsForPreferred(bottomGuidance).toSet()
        : <String>{};
    // Znevýhodnené spodky vylúčime len keď máme lepšiu preferovanú alternatívu
    // (napr. na túre rifle len ak v šatníku nie sú nohavice/joggers).
    final excludedDiscouragedBottomIds = usablePreferredBottomExists
        ? bottomInventory.idsForDiscouraged(bottomGuidance).toSet()
        : <String>{};

    final batchExcluded = <String>{
      ...effectiveExcluded,
      ...excludedDiscouragedFootwearIds,
      ...excludedDiscouragedBottomIds,
    };

    final comfortInput = ComfortWeatherInput.fromOutfitWeatherSnapshot(weather);
    final comfortTarget = ComfortTarget.fromWeather(comfortInput);

    StylistChatOutfitResult completeOutfitPick({
      required OutfitPreview preview,
      required String mode,
    }) {
      debugCollector?.markPickMode(mode);
      final identity = ActivityOutfitIdentity.evaluate(
        preview: preview,
        intent: outfitIntent,
        wetGroundMuddy: wetGroundMuddy,
      );
      ActivityOutfitIdentity.log(
        activityType: outfitIntent.activityType,
        preview: preview,
        result: identity,
      );
      final finalized = _finalizeOutfitPick(
        preview: preview,
        occasionProfile: occasionProfile,
        bottomGuidance: bottomGuidance,
        footwearGuidance: footwearGuidance,
      );
      final wardrobeAnalysis = WardrobeGapAnalysis.analyze(
        wardrobe: wardrobe,
        intent: outfitIntent,
        preview: finalized,
        weather: weather,
        wetGroundMuddy: wetGroundMuddy,
      );
      final finalizedIdentity = ActivityOutfitIdentity.evaluate(
        preview: finalized,
        intent: outfitIntent,
        wetGroundMuddy: wetGroundMuddy,
      );
      final stylistOpinion = StylistOpinionEngine.evaluate(
        preview: finalized,
        intent: outfitIntent,
        weather: weather,
        wardrobeAnalysis: wardrobeAnalysis,
        occasionProfile: occasionProfile,
        activityIdentity: finalizedIdentity,
        wetGroundMuddy: wetGroundMuddy,
      );
      final finalizedDocuments = <Map<String, dynamic>>[
        finalized.top.item,
        finalized.bottom.item,
        finalized.shoes.item,
        if (finalized.outerwear != null) finalized.outerwear!.item,
      ];
      final flexibleOutfit = NativeWardrobeV2Runtime.recommend(
        documents: finalizedDocuments,
        request: NativeOutfitRequestV2(
          weatherProtectionRequired: weather.isRainy || weather.isWindy,
          tempC: weather.tempC,
          activityType: outfitIntent.activityType,
        ),
      );
      if (flexibleOutfit == null || flexibleOutfit.validate().isNotEmpty) {
        throw StateError('stylist_invalid_v2_composition');
      }
      return StylistChatOutfitResult(
        flexibleOutfit: flexibleOutfit,
        wardrobeAnalysis: wardrobeAnalysis,
        weather: weather,
        occasionProfile: occasionProfile,
        wetGroundMuddy: wetGroundMuddy,
        outfitIntent: outfitIntent,
        activityIdentity: finalizedIdentity,
        stylistOpinion: stylistOpinion,
      );
    }

    // Univerzálna skratka „vymeň len tento kus“: keď máme predošlý outfit a
    // používateľ chce iný vrch/spodok/obuv/vrstvu, vymeníme IBA daný slot a zvyšok
    // zachováme. Platí rovnako pre všetky kúsky — žiadne zbytočné prehadzovanie.
    if (requestedSwap != null && previousOutfitItemIds.isNotEmpty) {
      final swapped = _swapSingleSlot(
        wardrobe: wardrobe,
        previousOutfitItemIds: previousOutfitItemIds,
        comfortTarget: comfortTarget,
        excludedIds: effectiveExcluded,
        request: requestedSwap,
      );
      if (swapped != null &&
          previewPassesLayerHarmonyGuard(
            preview: swapped,
            tempC: weather.tempC,
            log: false,
          )) {
        debugPrint(
          'STYLIST CHAT outfit_pick mode=swap_${requestedSwap.slot.name}_only '
          'ids=${_previewItemIds(swapped).join(",")}',
        );
        return completeOutfitPick(
          preview: swapped,
          mode: 'swap_${requestedSwap.slot.name}_only',
        );
      }
    }

    // Vygeneruje najlepší outfit pri DANOM vylúčení. Vraciame aj comfort skóre,
    // aby sme vedeli porovnať kvalitu medzi rôznymi top-variantmi.
    ({OutfitPreview preview, double comfort, double finalScore})?
    bestPreviewExcluding(Set<String> extraExcluded) {
      final excluded = <String>{...batchExcluded, ...extraExcluded};
      final candidates = OutfitGenerationService.generateCandidatePreviews(
        wardrobeItems: wardrobe,
        weather: weather,
        excludedItemIds: excluded,
        previousItemIds: previousOutfitItemIds,
        forceDifferentOutfit: forceDifferentOutfit,
        limit: 4,
        preferredBottomExists: preferredBottomExists,
        preferredFootwearExists: preferredFootwearExists,
        isPreferredBottom: preferredBottomExists
            ? (p) => !previewHasDiscouragedBottom(
                preview: p,
                guidance: bottomGuidance,
              )
            : null,
        isPreferredFootwear: preferredFootwearExists
            ? (p) => !previewHasDiscouragedFootwear(
                preview: p,
                guidance: footwearGuidance,
              )
            : null,
        isDiscouragedBottom: (p) =>
            previewHasDiscouragedBottom(preview: p, guidance: bottomGuidance),
        isDiscouragedFootwear: (p) => previewHasDiscouragedFootwear(
          preview: p,
          guidance: footwearGuidance,
        ),
        passesLayerHarmony: (p) => previewPassesLayerHarmonyGuard(
          preview: p,
          tempC: weather.tempC,
          log: false,
        ),
        comfortBonusScorer: intentCombinationBonus,
      );

      var filtered = candidates;
      if (preferredFootwearExists) {
        filtered = filtered
            .where(
              (p) => !previewHasDiscouragedFootwear(
                preview: p,
                guidance: footwearGuidance,
              ),
            )
            .toList();
      }
      if (preferredBottomExists) {
        filtered = filtered
            .where(
              (p) => !previewHasDiscouragedBottom(
                preview: p,
                guidance: bottomGuidance,
              ),
            )
            .toList();
      }
      filtered = filtered
          .where(
            (p) => previewPassesLayerHarmonyGuard(
              preview: p,
              tempC: weather.tempC,
              log: false,
            ),
          )
          .toList(growable: false);

      // Keď je nejaká rodina spodku PREFEROVANÁ pre dané počasie/sezónu (napr.
      // v lete kraťasy), nech ju výber naozaj uprednostní namiesto toho, aby
      // o všetkom rozhodlo len comfort skóre (to by pri 19 °C zvolilo nohavice).
      if (preferredBottomExists) {
        var preferredOnly = filtered
            .where(
              (p) => previewHasPreferredBottom(
                preview: p,
                guidance: bottomGuidance,
              ),
            )
            .toList(growable: false);
        // Ak comfort-skórovanie nevygenerovalo ŽIADNY outfit s preferovaným
        // spodkom (typicky kraťasy v lete vs. nohavice), vynútime ho priamo cez
        // allowedBottomItemIds, aby sme ho reálne ponúkli.
        if (preferredOnly.isEmpty && preferredBottomIds.isNotEmpty) {
          final forced = OutfitGenerationService.generatePreview(
            wardrobeItems: wardrobe,
            weather: weather,
            excludedItemIds: excluded,
            previousItemIds: previousOutfitItemIds,
            forceDifferentOutfit: forceDifferentOutfit,
            allowedBottomItemIds: preferredBottomIds,
            comfortBonusScorer: intentCombinationBonus,
          );
          if (forced != null &&
              previewPassesLayerHarmonyGuard(
                preview: forced,
                tempC: weather.tempC,
                log: false,
              )) {
            preferredOnly = [forced];
          }
        }
        if (preferredOnly.isNotEmpty) filtered = preferredOnly;
      }

      if (filtered.isEmpty) {
        debugCollector?.markFallback();
        final fallback = OutfitGenerationService.generatePreview(
          wardrobeItems: wardrobe,
          weather: weather,
          excludedItemIds: excluded,
          previousItemIds: previousOutfitItemIds,
          forceDifferentOutfit: forceDifferentOutfit,
          comfortBonusScorer: intentCombinationBonus,
        );
        if (fallback == null) return null;
        final warmth = calculateEffectiveOutfitWarmthForPreview(
          fallback,
          target: comfortTarget,
        );
        final breakdown = OutfitIntentScorer.evaluate(
          preview: fallback,
          intent: outfitIntent,
          baseScore: warmth.comfortScore,
        );
        logIntentCandidate(preview: fallback, breakdown: breakdown);
        if (breakdown.isExcluded) return null;
        return (
          preview: fallback,
          comfort: warmth.comfortScore,
          finalScore: breakdown.finalScore,
        );
      }

      var bestIdx = -1;
      var bestFinalScore = -1.0;
      var bestComfort = -1.0;
      for (var i = 0; i < filtered.length; i++) {
        final warmth = calculateEffectiveOutfitWarmthForPreview(
          filtered[i],
          target: comfortTarget,
        );
        final breakdown = OutfitIntentScorer.evaluate(
          preview: filtered[i],
          intent: outfitIntent,
          baseScore: warmth.comfortScore,
        );
        logIntentCandidate(preview: filtered[i], breakdown: breakdown);
        if (breakdown.isExcluded) continue;
        if (breakdown.finalScore > bestFinalScore) {
          bestFinalScore = breakdown.finalScore;
          bestComfort = warmth.comfortScore;
          bestIdx = i;
        }
      }
      if (bestIdx < 0) return null;
      return (
        preview: filtered[bestIdx],
        comfort: bestComfort,
        finalScore: bestFinalScore,
      );
    }

    // M3 — intent-first matrix: vlny preferred → fallback → compromise,
    // diverzita medzi kandidátmi, compromise len keď chýba preferred šatník.
    const maxVariants = 6;
    final matrixPreviews = StylistIntentMatrixGenerator.generateCandidates(
      wardrobe: wardrobe,
      weather: weather,
      outfitIntent: outfitIntent,
      bottomGuidance: bottomGuidance,
      footwearGuidance: footwearGuidance,
      excludedItemIds: effectiveExcluded,
      previousItemIds: previousOutfitItemIds,
      forceDifferentOutfit: forceDifferentOutfit,
      targetCount: maxVariants,
      preferredBottomExists: preferredBottomExists,
      preferredFootwearExists: preferredFootwearExists,
      isPreferredBottom: preferredBottomExists
          ? (p) => !previewHasDiscouragedBottom(
              preview: p,
              guidance: bottomGuidance,
            )
          : null,
      isPreferredFootwear: preferredFootwearExists
          ? (p) => !previewHasDiscouragedFootwear(
              preview: p,
              guidance: footwearGuidance,
            )
          : null,
      isDiscouragedBottom: (p) =>
          previewHasDiscouragedBottom(preview: p, guidance: bottomGuidance),
      isDiscouragedFootwear: (p) =>
          previewHasDiscouragedFootwear(preview: p, guidance: footwearGuidance),
      passesLayerHarmony: (p) => previewPassesLayerHarmonyGuard(
        preview: p,
        tempC: weather.tempC,
        log: false,
      ),
      comfortBonusScorer: intentCombinationBonus,
    );

    final scoredCandidates = <ScoredOutfitCandidate>[];
    for (var i = 0; i < matrixPreviews.length; i++) {
      final scored = StylistChatCandidatePipeline.scoreCandidate(
        preview: matrixPreviews[i],
        outfitIntent: outfitIntent,
        comfortTarget: comfortTarget,
        matrixIndex: i,
        wetGroundMuddy: wetGroundMuddy,
        logIntentCandidate: logIntentCandidate,
      );
      if (scored != null) scoredCandidates.add(scored);
    }

    if (scoredCandidates.isEmpty) {
      debugPrint(
        'STYLIST CHAT matrix_generation { '
        'wave=fallback_legacy, '
        'reason=no_matrix_candidates, '
        'generatedCandidates=0 '
        '}',
      );
      debugCollector?.markFallback();
      final fallback = bestPreviewExcluding({});
      if (fallback == null) return null;
      scoredCandidates.add(
        ScoredOutfitCandidate(
          preview: fallback.preview,
          comfort: fallback.comfort,
          finalScore: fallback.finalScore,
          intentBonus: 0,
          intentPenalty: 0,
          baseScore: fallback.comfort,
          ids: _previewItemIds(fallback.preview),
          signature: OutfitGenerationService.combinationSignature(
            fallback.preview.top.item,
            fallback.preview.bottom.item,
            fallback.preview.shoes.item,
            fallback.preview.outerwear?.item,
          ),
          matrixIndex: -1,
        ),
      );
    }

    final CandidatePipelineResult pipelineResult;
    try {
      pipelineResult = StylistChatCandidatePipeline.selectForFinalReview(
        matrixPreviews: matrixPreviews,
        scoredCandidates: scoredCandidates,
        previousOutfitItemIds: previousOutfitItemIds,
      );
    } on StateError {
      return null;
    }

    final pick = pipelineResult.topPick;
    debugPrint(
      'STYLIST CHAT outfit_pick ranked=${scoredCandidates.length} '
      'forReview=${pipelineResult.forFinalReview.length} '
      'comfort=${pick.comfort.toStringAsFixed(2)} '
      'intentFinal=${pick.finalScore.toStringAsFixed(2)} '
      'requestedBottom=${requestedBottomFamily?.wireName ?? "none"} '
      'ids=${pick.ids.join(",")}',
    );

    // Minimálna zmena má prednosť: keď si používateľ pýta iný spodok a vieme
    // zachovať pôvodný (už schválený) vrch + obuv, vymeníme LEN spodok a outfit
    // vrátime priamo. Tým sa nestane, že kvôli kraťasom appka prehodí aj tričko.
    // Vrch + obuv už boli zladené, takže nový spodok žiadanej rodiny (vybraný
    // tak, aby farebne sadol) drží harmóniu; krajné prípady chytí layer guard.
    if (requestedBottomFamily != null && previousOutfitItemIds.isNotEmpty) {
      final swap = _swapBottomOnlyPreview(
        wardrobe: wardrobe,
        previousOutfitItemIds: previousOutfitItemIds,
        requestedFamily: requestedBottomFamily,
        comfortTarget: comfortTarget,
        excludedIds: effectiveExcluded,
      );
      if (swap != null &&
          previewPassesLayerHarmonyGuard(
            preview: swap.preview,
            tempC: weather.tempC,
            log: false,
          )) {
        debugPrint(
          'STYLIST CHAT outfit_pick mode=swap_bottom_only '
          'ids=${_previewItemIds(swap.preview).join(",")}',
        );
        return completeOutfitPick(
          preview: swap.preview,
          mode: 'swap_bottom_only',
        );
      }
    }

    // Kandidáti na AI final review – top N podľa intent+comfort skóre (bez comfort pásma).
    final forReview = <OutfitPreview>[
      for (final candidate in pipelineResult.forFinalReview) candidate.preview,
    ];

    if (forReview.isEmpty) {
      pipelineResult.logSummary(finalWinner: 1);
      return completeOutfitPick(
        preview: pick.preview,
        mode: 'intent_pick_direct',
      );
    }

    if (forReview.length == 1) {
      pipelineResult.logSummary(finalWinner: 1);
      return completeOutfitPick(
        preview: forReview.first,
        mode: 'intent_pick_direct',
      );
    }

    final flexibleReviewCandidates = <V2FlexibleCandidate>[];
    for (var i = 0; i < forReview.length; i++) {
      final preview = forReview[i];
      final flexible = NativeWardrobeV2Runtime.recommend(
        documents: <Map<String, dynamic>>[
          preview.top.item,
          preview.bottom.item,
          preview.shoes.item,
          if (preview.outerwear != null) preview.outerwear!.item,
        ],
        request: NativeOutfitRequestV2(
          weatherProtectionRequired: weather.isRainy || weather.isWindy,
          tempC: weather.tempC,
        ),
      );
      if (flexible == null || flexible.validate().isNotEmpty) continue;
      final context = V2CandidateMatrixContext(
        weatherProtectionRequired: weather.isRainy || weather.isWindy,
        tempC: weather.tempC,
        isRainy: weather.isRainy,
        isWindy: weather.isWindy,
      );
      final score = V2FlexibleOutfitScorer.score(flexible, context);
      flexibleReviewCandidates.add(
        V2FlexibleCandidate(
          candidateId: 'stylist_$i',
          outfit: flexible,
          score: score.values.fold(0, (a, b) => a + b),
          scoreBreakdown: score,
        ),
      );
    }
    if (flexibleReviewCandidates.isEmpty) {
      return completeOutfitPick(
        preview: pick.preview,
        mode: 'v2_review_no_valid_candidate',
      );
    }
    final decision = await const StylistFrozenCandidateDecisionServiceV1().resolve(
      candidates: flexibleReviewCandidates,
      resolvedContext: <String, dynamic>{
        'activity': 'stylist_chat',
        'weather':
            '${weather.tempC}C rain=${weather.isRainy} wind=${weather.isWindy}',
      },
    );
    final reviewedFlexible = flexibleReviewCandidates
        .where(
          (candidate) => candidate.candidateId == decision.selectedCandidateId,
        )
        .firstOrNull;
    if (!decision.selected || reviewedFlexible == null) {
      // The new Stylist authority is intentionally unable to select candidate
      // zero after a timeout, malformed output or provider failure.
      throw StylistFrozenDecisionRejectedExceptionV1(
        decision.reasonCodes,
        explanation: decision.explanation,
      );
    }
    final reviewedIds = reviewedFlexible.outfit.items
        .map((item) => item.itemId)
        .toSet();
    final reviewed = forReview.firstWhere(
      (preview) =>
          _previewItemIds(preview).difference(reviewedIds).isEmpty &&
          reviewedIds.difference(_previewItemIds(preview)).isEmpty,
      orElse: () => pick.preview,
    );
    pipelineResult.logSummary(finalWinner: 1);
    debugPrint(
      'STYLIST CHAT outfit_pick mode=ai_final_review '
      'candidates=${forReview.length} '
      'ids=${_previewItemIds(reviewed).join(",")}',
    );
    return completeOutfitPick(preview: reviewed, mode: 'ai_final_review');
  }

  OutfitPreview _finalizeOutfitPick({
    required OutfitPreview preview,
    required StylistOccasionProfile occasionProfile,
    required BottomFamilyGuidance bottomGuidance,
    required FootwearFamilyGuidance footwearGuidance,
  }) {
    for (final note in StylistOccasionGuidance.outfitCompromiseNotes(
      preview: preview,
      bottomGuidance: bottomGuidance,
      footwearGuidance: footwearGuidance,
      profile: occasionProfile,
    )) {
      debugPrint('STYLIST CHAT outfit_compromise $note');
    }
    return preview;
  }

  Set<String> _previewItemIds(OutfitPreview preview) {
    return <String>{
      OutfitGenerationService.wardrobeItemId(preview.top.item),
      OutfitGenerationService.wardrobeItemId(preview.bottom.item),
      OutfitGenerationService.wardrobeItemId(preview.shoes.item),
      if (preview.outerwear != null)
        OutfitGenerationService.wardrobeItemId(preview.outerwear!.item),
    }..removeWhere((id) => id.isEmpty);
  }

  /// Vymení iba spodok v predošlom outfite za najvhodnejší kúsok žiadanej
  /// rodiny (kraťasy/nohavice/…), pričom vrch, obuv a prípadnú vrstvu zachová.
  /// Vráti `null`, keď sa to nedá (chýba predošlý vrch/obuv alebo nemáme kúsok
  /// danej rodiny) – vtedy sa použije bežné generovanie celého outfitu.
  ({OutfitPreview preview, double comfort})? _swapBottomOnlyPreview({
    required List<Map<String, dynamic>> wardrobe,
    required Set<String> previousOutfitItemIds,
    required BottomFamily requestedFamily,
    required ComfortTarget comfortTarget,
    required Set<String> excludedIds,
  }) {
    final byId = <String, Map<String, dynamic>>{};
    for (final it in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(it);
      if (id.isNotEmpty) byId[id] = it;
    }

    Map<String, dynamic>? prevTop;
    Map<String, dynamic>? prevShoes;
    Map<String, dynamic>? prevOuter;
    for (final id in previousOutfitItemIds) {
      final it = byId[id];
      if (it == null) continue;
      if (prevShoes == null &&
          classifyFootwearFamily(it) != FootwearFamily.other) {
        prevShoes = it;
        continue;
      }
      if (classifyBottomFamily(it) != BottomFamily.other) {
        // Predošlý spodok zahadzujeme – práve ten meníme.
        continue;
      }
      if (prevTop == null) {
        prevTop = it;
      } else {
        prevOuter ??= it;
      }
    }
    // Bez zachovateľného vrchu a obuvi nemá zmysel „len vymeniť spodok“.
    if (prevTop == null || prevShoes == null) return null;

    final candidates = <Map<String, dynamic>>[];
    for (final it in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(it);
      if (id.isEmpty || excludedIds.contains(id)) continue;
      if (classifyBottomFamily(it) == requestedFamily) candidates.add(it);
    }
    if (candidates.isEmpty) return null;

    OutfitPreview buildWith(Map<String, dynamic> bottom) => OutfitPreview(
      top: _previewItemFor(OutfitWearType.top, prevTop!, 'Vrchný diel'),
      bottom: _previewItemFor(OutfitWearType.bottom, bottom, 'Spodný diel'),
      shoes: _previewItemFor(OutfitWearType.shoes, prevShoes!, 'Obuv'),
      outerwear: prevOuter == null
          ? null
          : _previewItemFor(OutfitWearType.outerwear, prevOuter, 'Vrstva'),
    );

    // Vrch zostáva, takže spodok vyberáme tak, aby k nemu farebne sadol:
    // zhoda farby s vrchom alebo neutrálna farba má prednosť, comfort dolaďuje.
    final topColors = _baseColorsOf(prevTop);
    OutfitPreview? best;
    var bestScore = -1.0;
    var bestComfort = 0.0;
    for (final bottom in candidates) {
      final preview = buildWith(bottom);
      final warmth = calculateEffectiveOutfitWarmthForPreview(
        preview,
        target: comfortTarget,
      );
      final colorScore = _bottomColorHarmonyScore(topColors, bottom);
      final total = colorScore + warmth.comfortScore;
      if (total > bestScore) {
        bestScore = total;
        bestComfort = warmth.comfortScore;
        best = preview;
      }
    }
    if (best == null) return null;
    return (preview: best, comfort: bestComfort);
  }

  /// Univerzálna výmena JEDNÉHO slotu (vrch / spodok / obuv / vrstva) v predošlom
  /// outfite, pričom všetky ostatné kúsky zachová. Nový kúsok vyberie tak, aby
  /// farebne ladil so zvyškom (zhoda farby alebo neutrál) a bol pohodlný do
  /// počasia. Vráti `null`, keď výmena nedáva zmysel (chýbajú ostatné kúsky alebo
  /// nemáme vhodný náhradný kus) — vtedy sa použije bežné generovanie.
  OutfitPreview? _swapSingleSlot({
    required List<Map<String, dynamic>> wardrobe,
    required Set<String> previousOutfitItemIds,
    required ComfortTarget comfortTarget,
    required Set<String> excludedIds,
    required StylistSwapRequest request,
  }) {
    final byId = <String, Map<String, dynamic>>{};
    for (final it in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(it);
      if (id.isNotEmpty) byId[id] = it;
    }

    final resolved = NativeWardrobeV2Runtime.resolveAll(wardrobe);
    final resolvedById = {
      for (final value in resolved) value.itemId: value.item,
    };
    bool matchesSlot(WardrobeItemV2 item) => switch (request.slot) {
      StylistSwapSlot.top =>
        item.bodySlots.contains('upper_body') &&
            !const {'mid', 'outer', 'shell'}.contains(item.layerPosition),
      StylistSwapSlot.bottom =>
        item.bodySlots.contains('lower_body') &&
            item.layerPosition != 'skin_base',
      StylistSwapSlot.shoes => item.bodySlots.contains('feet'),
      StylistSwapSlot.outerwear => const {
        'mid',
        'outer',
        'shell',
      }.contains(item.layerPosition),
    };
    WardrobeItemV2? replacedV2;
    for (final id in previousOutfitItemIds) {
      final value = resolvedById[id];
      if (value != null && matchesSlot(value)) {
        replacedV2 = value;
        break;
      }
    }
    if (replacedV2 == null) return null;
    final compatibleIds = <String>{
      for (final entry in resolvedById.entries)
        if (!previousOutfitItemIds.contains(entry.key) &&
            !excludedIds.contains(entry.key) &&
            SwapCandidateSelectorV2.compatible(
              replaced: replacedV2,
              candidates: [entry.value],
            ).isNotEmpty)
          entry.key,
    };

    Map<String, dynamic>? prevTop;
    Map<String, dynamic>? prevBottom;
    Map<String, dynamic>? prevShoes;
    Map<String, dynamic>? prevOuter;
    for (final id in previousOutfitItemIds) {
      final it = byId[id];
      if (it == null) continue;
      final v2 = resolvedById[id];
      if (v2 == null) continue;
      if (prevShoes == null && v2.bodySlots.contains('feet')) {
        prevShoes = it;
        continue;
      }
      if (prevBottom == null &&
          v2.bodySlots.contains('lower_body') &&
          v2.layerPosition != 'skin_base') {
        prevBottom = it;
        continue;
      }
      if (prevTop == null &&
          v2.bodySlots.contains('upper_body') &&
          !const {'mid', 'outer', 'shell'}.contains(v2.layerPosition)) {
        prevTop = it;
      } else if (const {'mid', 'outer', 'shell'}.contains(v2.layerPosition)) {
        prevOuter ??= it;
      }
    }

    // Zostav kandidátov pre cieľový slot + over, že ostatné (fixné) kúsky máme.
    final candidates = <Map<String, dynamic>>[];
    String? keepTopId;
    switch (request.slot) {
      case StylistSwapSlot.top:
        if (prevTop == null || prevBottom == null || prevShoes == null) {
          return null;
        }
        final prevTopId = OutfitGenerationService.wardrobeItemId(prevTop);
        for (final it in wardrobe) {
          final id = OutfitGenerationService.wardrobeItemId(it);
          if (!compatibleIds.contains(id)) continue;
          if (id.isEmpty || id == prevTopId || excludedIds.contains(id)) {
            continue;
          }
          candidates.add(it);
        }
        break;
      case StylistSwapSlot.bottom:
        if (prevTop == null || prevShoes == null) return null;
        final prevBottomId = prevBottom == null
            ? ''
            : OutfitGenerationService.wardrobeItemId(prevBottom);
        for (final it in wardrobe) {
          final id = OutfitGenerationService.wardrobeItemId(it);
          if (!compatibleIds.contains(id)) continue;
          if (id.isEmpty || excludedIds.contains(id)) continue;
          if (id == prevBottomId) continue;
          final fam = classifyBottomFamily(it);
          if (fam == BottomFamily.other) continue;
          // Ak chce konkrétnu rodinu (kraťasy), drž sa jej; inak iný spodok.
          if (request.bottomFamily != null && fam != request.bottomFamily) {
            continue;
          }
          candidates.add(it);
        }
        break;
      case StylistSwapSlot.shoes:
        if (prevTop == null || prevBottom == null) return null;
        final prevShoesId = prevShoes == null
            ? ''
            : OutfitGenerationService.wardrobeItemId(prevShoes);
        for (final it in wardrobe) {
          final id = OutfitGenerationService.wardrobeItemId(it);
          if (!compatibleIds.contains(id)) continue;
          if (id.isEmpty || excludedIds.contains(id)) continue;
          if (id == prevShoesId) continue;
          final fam = classifyFootwearFamily(it);
          if (fam == FootwearFamily.other) continue;
          if (request.shoeFamily != null && fam != request.shoeFamily) continue;
          candidates.add(it);
        }
        break;
      case StylistSwapSlot.outerwear:
        if (prevTop == null || prevBottom == null || prevShoes == null) {
          return null;
        }
        keepTopId = OutfitGenerationService.wardrobeItemId(prevTop);
        final prevOuterId = prevOuter == null
            ? ''
            : OutfitGenerationService.wardrobeItemId(prevOuter);
        for (final it in wardrobe) {
          final id = OutfitGenerationService.wardrobeItemId(it);
          if (!compatibleIds.contains(id)) continue;
          if (id.isEmpty || excludedIds.contains(id)) continue;
          if (id == prevOuterId || id == keepTopId) continue;
          if (!_isOuterLayer(it)) continue;
          candidates.add(it);
        }
        break;
    }
    if (candidates.isEmpty) return null;

    OutfitPreview buildWith(Map<String, dynamic> swapItem) {
      switch (request.slot) {
        case StylistSwapSlot.top:
          return OutfitPreview(
            top: _previewItemFor(OutfitWearType.top, swapItem, 'Vrchný diel'),
            bottom: _previewItemFor(
              OutfitWearType.bottom,
              prevBottom!,
              'Spodný diel',
            ),
            shoes: _previewItemFor(OutfitWearType.shoes, prevShoes!, 'Obuv'),
            outerwear: prevOuter == null
                ? null
                : _previewItemFor(
                    OutfitWearType.outerwear,
                    prevOuter,
                    'Vrstva',
                  ),
          );
        case StylistSwapSlot.bottom:
          return OutfitPreview(
            top: _previewItemFor(OutfitWearType.top, prevTop!, 'Vrchný diel'),
            bottom: _previewItemFor(
              OutfitWearType.bottom,
              swapItem,
              'Spodný diel',
            ),
            shoes: _previewItemFor(OutfitWearType.shoes, prevShoes!, 'Obuv'),
            outerwear: prevOuter == null
                ? null
                : _previewItemFor(
                    OutfitWearType.outerwear,
                    prevOuter,
                    'Vrstva',
                  ),
          );
        case StylistSwapSlot.shoes:
          return OutfitPreview(
            top: _previewItemFor(OutfitWearType.top, prevTop!, 'Vrchný diel'),
            bottom: _previewItemFor(
              OutfitWearType.bottom,
              prevBottom!,
              'Spodný diel',
            ),
            shoes: _previewItemFor(OutfitWearType.shoes, swapItem, 'Obuv'),
            outerwear: prevOuter == null
                ? null
                : _previewItemFor(
                    OutfitWearType.outerwear,
                    prevOuter,
                    'Vrstva',
                  ),
          );
        case StylistSwapSlot.outerwear:
          return OutfitPreview(
            top: _previewItemFor(OutfitWearType.top, prevTop!, 'Vrchný diel'),
            bottom: _previewItemFor(
              OutfitWearType.bottom,
              prevBottom!,
              'Spodný diel',
            ),
            shoes: _previewItemFor(OutfitWearType.shoes, prevShoes!, 'Obuv'),
            outerwear: _previewItemFor(
              OutfitWearType.outerwear,
              swapItem,
              'Vrstva',
            ),
          );
      }
    }

    // Nový kúsok vyberáme tak, aby farebne ladil so zvyškom outfitu (zhoda alebo
    // neutrál) a bol pohodlný do počasia.
    final fixedColors = <String>{
      if (request.slot != StylistSwapSlot.top) ..._baseColorsOf(prevTop),
      if (request.slot != StylistSwapSlot.bottom && prevBottom != null)
        ..._baseColorsOf(prevBottom),
      if (request.slot != StylistSwapSlot.shoes && prevShoes != null)
        ..._baseColorsOf(prevShoes),
    };

    OutfitPreview? best;
    var bestScore = -1.0;
    for (final cand in candidates) {
      final preview = buildWith(cand);
      final warmth = calculateEffectiveOutfitWarmthForPreview(
        preview,
        target: comfortTarget,
      );
      final colorScore = _colorHarmonyScore(fixedColors, cand);
      final total = colorScore + warmth.comfortScore;
      if (total > bestScore) {
        bestScore = total;
        best = preview;
      }
    }
    return best;
  }

  /// True, keď je kus vrchná vrstva (bunda/kabát/sako…), nie základný vrch.
  bool _isOuterLayer(Map<String, dynamic> item) {
    final layer = (item['layer_role'] ?? item['layerRole'] ?? '')
        .toString()
        .trim();
    if (layer == 'outer_layer' || layer == 'mid_layer') return true;
    final blob = _normColor(
      [
        item['name'],
        item['canonical_type'] ?? item['canonicalType'],
        item['subCategoryKey'] ?? item['subCategory'],
        item['categoryKey'] ?? item['category'],
      ].whereType<Object>().join(' '),
    );
    return blob.contains('bund') ||
        blob.contains('kabat') ||
        blob.contains('sako') ||
        blob.contains('blazer') ||
        blob.contains('vetrovk') ||
        blob.contains('parka') ||
        blob.contains('kardigan');
  }

  static const Set<String> _neutralColorKeys = {
    'cierna',
    'biela',
    'siva',
    'sivá',
    'tmavomodra',
    'navy',
    'bezova',
    'bez',
    'hneda',
    'khaki',
    'denim',
    'riflova',
  };

  Set<String> _baseColorsOf(Map<String, dynamic> item) {
    final raw = item['baseColors'] ?? item['colors'];
    final out = <String>{};
    if (raw is List) {
      for (final c in raw) {
        final s = _normColor(c.toString());
        if (s.isNotEmpty) out.add(s);
      }
    } else if (raw != null) {
      final s = _normColor(raw.toString());
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }

  double _bottomColorHarmonyScore(
    Set<String> topColors,
    Map<String, dynamic> bottom,
  ) => _colorHarmonyScore(topColors, bottom);

  /// Skóre farebného ladenia náhradného kusu so zvyškom outfitu: zhoda farby = 1,
  /// neutrálna farba = 0.5, inak 0. Slúži na výber kusu, ktorý sadne.
  double _colorHarmonyScore(
    Set<String> fixedColors,
    Map<String, dynamic> candidate,
  ) {
    final candColors = _baseColorsOf(candidate);
    if (candColors.any(fixedColors.contains)) return 1.0;
    if (candColors.any(_neutralColorKeys.contains)) return 0.5;
    return 0.0;
  }

  String _normColor(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll('á', 'a')
        .replaceAll('í', 'i')
        .replaceAll('é', 'e')
        .replaceAll('ý', 'y')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('č', 'c')
        .replaceAll('š', 's')
        .replaceAll('ž', 'z');
  }

  OutfitPreviewItem _previewItemFor(
    OutfitWearType type,
    Map<String, dynamic> item,
    String fallbackLabel,
  ) {
    final name = (item['name'] ?? '').toString().trim();
    final url = resolveWardrobeImageUrl(item)?.trim();
    return OutfitPreviewItem(
      type: type,
      item: item,
      label: name.isNotEmpty ? name : fallbackLabel,
      imageUrl: (url != null && url.isNotEmpty) ? url : null,
    );
  }

  Future<List<Map<String, dynamic>>> suggestedItemsFromPreview(
    OutfitPreview preview,
  ) async {
    final items = <Map<String, dynamic>>[];
    void add(OutfitPreviewItem? part) {
      if (part == null) return;
      final raw = Map<String, dynamic>.from(part.item);
      final id = OutfitGenerationService.wardrobeItemId(raw);
      if (id.isNotEmpty) raw['id'] = id;
      if ((raw['name'] ?? '').toString().trim().isEmpty) {
        raw['name'] = part.label;
      }
      items.add(raw);
    }

    add(preview.top);
    if (preview.outerwear != null) add(preview.outerwear);
    add(preview.bottom);
    add(preview.shoes);
    return items;
  }

  Future<List<Map<String, dynamic>>> suggestedItemsFromFlexibleOutfit(
    V2FlexibleOutfitResult outfit,
  ) async => outfit.items
      .map((part) {
        final raw = <String, dynamic>{...part.display};
        raw['id'] = part.itemId;
        raw['canonicalType'] = part.item.canonicalType;
        raw['canonicalFamily'] = part.item.canonicalFamily;
        raw['bodySlots'] = part.item.bodySlots;
        raw['layerPosition'] = part.item.layerPosition;
        raw['compositionRole'] = part.compositionRole.name;
        raw['compositionGroup'] = part.compositionGroup;
        raw['selectionReason'] = part.selectionReason;
        if (part.item.setMembership case final set?) {
          raw['setMembership'] = set.toMap();
          raw['setReasoningSignal'] = set.relationshipSource == 'user_curated'
              ? 'known_user_preference'
              : 'matching_set_partner';
        }
        return raw;
      })
      .toList(growable: false);

  Future<List<Map<String, dynamic>>> _loadNormalizedWardrobe(String uid) async {
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('wardrobe')
        .limit(120)
        .get();
    final raw = snap.docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList(growable: false);
    return const StylistChatWardrobeReadPath().build(raw).items;
  }

  OutfitWeatherSnapshot _weatherSnapshotFromDay(
    OutfitWeatherDaySnapshot day,
    StylistChatEventContext event, {
    String? conversationHint,
  }) {
    final window = event.effectiveTripWindow;
    final tripWeather = TripWeatherAnalyzer.analyze(
      day: day,
      window: window,
      timeKnown: window.hasExplicitTime,
    );
    var tempC = tripWeather.outfitTempC;
    if (event.hourLocal != null) {
      final atHour = TripWeatherAnalyzer.tempAtHour(day, event.hourLocal!);
      if (atHour != null) tempC = atHour;
    }
    final terrain = StylistActivityTerrainClassifier.classify(
      conversationText: conversationHint ?? event.occasion,
      occasion: event.occasion,
    );
    final rawTempC = tempC;
    tempC = StylistWeatherAdjustment.adjustActivityTempC(
      rawTempC: tempC,
      terrain: terrain,
      hourLocal: event.hourLocal,
    );
    if (rawTempC != tempC) {
      debugPrint(
        '[STYLIST_WEATHER_ADJ] raw=$rawTempC adjusted=$tempC '
        'terrain=${terrain.name} hour=${event.hourLocal}',
      );
    }
    return OutfitWeatherSnapshot(
      tempC: tempC,
      isRainy: tripWeather.rainDuringTrip,
      isWindy: day.isWindy,
      seasonKey: _seasonKeyFromDate(event.date),
    );
  }

  Future<TripWeatherSummary> tripWeatherForEvent(
    StylistChatEventContext event,
  ) async {
    final city = event.locationLabel.trim().isNotEmpty
        ? event.locationLabel
        : UserLocationService.instance.cityLabel;
    final day = await _hourlyWeatherService.getWeatherForCityAndDate(
      city: city,
      date: event.date,
    );
    return TripWeatherAnalyzer.analyze(
      day: day,
      window: event.effectiveTripWindow,
      timeKnown: event.effectiveTripWindow.hasExplicitTime,
    );
  }

  String _seasonKeyFromDate(DateTime date) {
    final m = date.month;
    if (m >= 3 && m <= 5) return 'jar';
    if (m >= 6 && m <= 8) return 'let';
    if (m >= 9 && m <= 11) return 'jese';
    return 'zim';
  }

  Set<String> _idsMatchingExcludeKeywords(
    List<Map<String, dynamic>> wardrobe,
    List<String> keywords,
  ) {
    if (keywords.isEmpty) return const {};
    final ids = <String>{};
    for (final item in wardrobe) {
      final id = OutfitGenerationService.wardrobeItemId(item);
      if (id.isEmpty) continue;
      final blob = [
        item['name'],
        item['category'],
        item['categoryKey'],
        item['subCategory'],
        item['subCategoryKey'],
        item['canonical_type'],
        item['canonicalType'],
      ].whereType<String>().join(' ').toLowerCase();
      for (final keyword in keywords) {
        final k = keyword.trim().toLowerCase();
        if (k.isEmpty) continue;
        if (k.contains('tielko') && StylistLayerFilter.isTankTopItem(item)) {
          ids.add(id);
          break;
        }
        if (blob.contains(k)) {
          ids.add(id);
          break;
        }
      }
    }
    return ids;
  }
}
