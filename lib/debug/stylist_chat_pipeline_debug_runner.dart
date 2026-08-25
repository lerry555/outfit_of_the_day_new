import 'package:flutter/foundation.dart';

import '../Services/stylist_chat_outfit_service.dart';
import '../Services/stylist_chat_service.dart';
import '../data/stylist_opinion.dart';
import '../data/wardrobe_analysis.dart';
import '../utils/stylist_occasion_guidance.dart';
import '../utils/stylist_outfit_explain_builder.dart';
import 'stylist_chat_event_from_prompt.dart';
import 'stylist_chat_outfit_debug_collector.dart';

/// Zdroj odpovede pre scenár v debug reporte.
enum StylistChatReplySource { ai, local, none }

extension StylistChatReplySourceLabel on StylistChatReplySource {
  String get label {
    switch (this) {
      case StylistChatReplySource.ai:
        return 'AI';
      case StylistChatReplySource.local:
        return 'LOCAL';
      case StylistChatReplySource.none:
        return '—';
    }
  }
}

/// Jeden scenár pre kompletný Stylist Chat debug test.
class StylistChatDebugScenario {
  const StylistChatDebugScenario({required this.label, required this.prompt});

  final String label;
  final String prompt;
}

/// Výsledok jedného scenára — všetko potrebné pre pekný report.
class StylistChatScenarioReport {
  const StylistChatScenarioReport({
    required this.label,
    required this.prompt,
    required this.ok,
    this.outfitItems = const [],
    this.explain = '',
    this.usedCompromise = false,
    this.missingItems = const [],
    this.compromiseItems = const [],
    this.identityScore,
    this.identityReasons = const [],
    this.replySource = StylistChatReplySource.none,
    this.stylistOpinion,
    this.error,
  });

  final String label;
  final String prompt;
  final bool ok;
  final List<String> outfitItems;
  final String explain;
  final bool usedCompromise;
  final List<WardrobeGap> missingItems;
  final List<String> compromiseItems;
  final double? identityScore;
  final List<String> identityReasons;
  final StylistChatReplySource replySource;
  final StylistOpinion? stylistOpinion;
  final String? error;

  static const String _divider =
      '==================================================';

  /// Kategórie chýbajúcich kúskov (bez detailného textu) — pre QA report.
  List<String> get missingCategories =>
      missingItems.map((gap) => gap.category).toList(growable: false);

  /// Kompaktný QA blok jedného scenára (čitateľný, kopírovateľný do chatu).
  ///
  /// Interné technické logy (top_eligibility, matrix_*, intent_score,
  /// candidate_eliminated, final_review, identity reasons, ...) do tohto
  /// reportu zámerne nepatria — ostávajú iba v Logcate.
  String formatBlock({int? index}) {
    final b = StringBuffer();
    final heading = index != null ? 'SCENÁR $index' : 'SCENÁR';
    b.writeln(_divider);
    b.writeln('$heading: ${label.toUpperCase()}${ok ? '' : ' ❌ ZLYHAL'}');
    b.writeln(_divider);
    b.writeln('');

    b.writeln('Prompt:');
    b.writeln(prompt);
    b.writeln('');

    if (!ok) {
      b.writeln('Chyba:');
      b.writeln(error ?? 'Neznáma chyba — outfit sa nevygeneroval.');
      b.writeln('');
      b.writeln(_divider);
      return b.toString();
    }

    b.writeln('Outfit:');
    if (outfitItems.isEmpty) {
      b.writeln('- (žiadne kúsky)');
    } else {
      for (final item in outfitItems) {
        b.writeln('- $item');
      }
    }
    b.writeln('');

    b.writeln('Explain:');
    b.writeln(explain.isEmpty ? '(prázdny)' : explain);
    b.writeln('');

    b.writeln('WardrobeAnalysis:');
    b.writeln('- compromise: ${usedCompromise ? 'áno' : 'nie'}');
    b.writeln(
      '- compromiseItems: '
      '${compromiseItems.isEmpty ? '—' : compromiseItems.join(', ')}',
    );
    b.writeln(
      '- missingItems: '
      '${missingCategories.isEmpty ? '—' : missingCategories.join(', ')}',
    );
    b.writeln('');

    b.writeln(formatStylistOpinionBlock(stylistOpinion));
    b.writeln('');

    b.writeln('Reply source:');
    b.writeln(replySource.label);
    b.writeln('');

    b.writeln(_divider);
    return b.toString();
  }

  /// Kompaktný StylistOpinion blok — iba confidence, level, opinion a
  /// biggestMissingPiece (bez strengths/compromises/factors, tie sú interné).
  static String formatStylistOpinionBlock(StylistOpinion? opinion) {
    final b = StringBuffer();
    b.writeln('StylistOpinion:');
    if (opinion == null) {
      b.writeln('- —');
      return b.toString().trimRight();
    }

    b.writeln('- confidence: ${opinion.overallConfidence} %');
    b.writeln('- level: ${opinion.opinionLevel.wireName}');
    b.writeln('- opinion: ${opinion.shortOpinionSk}');
    b.writeln('- biggestMissingPiece: ${opinion.biggestMissingPiece ?? '—'}');

    return b.toString().trimRight();
  }
}

/// Sumár celého behu.
class StylistChatDebugSummary {
  const StylistChatDebugSummary({
    required this.total,
    required this.succeeded,
    required this.compromise,
    required this.aiExplain,
    required this.localExplain,
    required this.averageConfidence,
  });

  final int total;
  final int succeeded;
  final int compromise;
  final int aiExplain;
  final int localExplain;
  final double averageConfidence;

  static const String _divider =
      '==================================================';

  factory StylistChatDebugSummary.fromReports(
    List<StylistChatScenarioReport> reports,
  ) {
    final succeeded = reports.where((r) => r.ok).toList();
    final confidences = succeeded
        .where((r) => r.stylistOpinion != null)
        .map((r) => r.stylistOpinion!.overallConfidence.toDouble())
        .toList();
    final avg = confidences.isEmpty
        ? 0.0
        : confidences.reduce((a, b) => a + b) / confidences.length;
    return StylistChatDebugSummary(
      total: reports.length,
      succeeded: succeeded.length,
      compromise: succeeded.where((r) => r.usedCompromise).length,
      aiExplain: succeeded
          .where((r) => r.replySource == StylistChatReplySource.ai)
          .length,
      localExplain: succeeded
          .where((r) => r.replySource == StylistChatReplySource.local)
          .length,
      averageConfidence: avg,
    );
  }

  /// Hlavička QA reportu s prehľadom počtov.
  String formatBlock() {
    final b = StringBuffer();
    b.writeln(_divider);
    b.writeln('STYLIST CHAT QA REPORT');
    b.writeln(_divider);
    b.writeln('');
    b.writeln('Počet scenárov: $total');
    b.writeln('Úspešne: $succeeded/$total');
    b.writeln('Compromise: $compromise');
    b.writeln('AI explain: $aiExplain');
    b.writeln('Local explain: $localExplain');
    b.writeln('Priemerná confidence: ${averageConfidence.round()} %');
    return b.toString();
  }
}

/// Kompletný výstup behu — reporty + sumár + hotový text.
class StylistChatDebugRunResult {
  const StylistChatDebugRunResult({
    required this.reports,
    required this.summary,
  });

  final List<StylistChatScenarioReport> reports;
  final StylistChatDebugSummary summary;

  static const String _divider =
      '==================================================';

  /// Záverečný súhrn: najslabšie scenáre + najčastejšie missingItems.
  String footerText() {
    final b = StringBuffer();
    b.writeln(_divider);
    b.writeln('SÚHRN');
    b.writeln(_divider);
    b.writeln('');

    final scored =
        reports.where((r) => r.ok && r.stylistOpinion != null).toList()..sort(
          (a, b) => a.stylistOpinion!.overallConfidence.compareTo(
            b.stylistOpinion!.overallConfidence,
          ),
        );

    b.writeln('Najslabšie scenáre:');
    if (scored.isEmpty) {
      b.writeln('- —');
    } else {
      for (final r in scored.take(3)) {
        final opinion = r.stylistOpinion!;
        b.writeln(
          '- ${r.label}: ${opinion.overallConfidence} % — ${_weaknessReason(r)}',
        );
      }
    }
    b.writeln('');

    final counts = <String, int>{};
    for (final r in reports.where((r) => r.ok)) {
      for (final category in r.missingCategories) {
        counts[category] = (counts[category] ?? 0) + 1;
      }
    }
    final ordered = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    b.writeln('Najčastejšie missingItems:');
    if (ordered.isEmpty) {
      b.writeln('- —');
    } else {
      for (final entry in ordered) {
        b.writeln('- ${entry.key}: ${entry.value}×');
      }
    }

    return b.toString();
  }

  static String _weaknessReason(StylistChatScenarioReport r) {
    final opinion = r.stylistOpinion!;
    final missing = opinion.biggestMissingPiece;
    if (missing != null && missing.trim().isNotEmpty && missing != '—') {
      return 'chýba $missing';
    }
    switch (opinion.opinionLevel) {
      case StylistOpinionLevel.weak:
        return 'slabý súlad s príležitosťou';
      case StylistOpinionLevel.acceptable:
        return 'kompromisný outfit';
      case StylistOpinionLevel.good:
      case StylistOpinionLevel.excellent:
        return 'drobné rezervy';
    }
  }

  String fullText() {
    final b = StringBuffer();
    b.writeln(summary.formatBlock());
    b.writeln('');
    for (var i = 0; i < reports.length; i++) {
      b.writeln(reports[i].formatBlock(index: i + 1));
      b.writeln('');
    }
    b.writeln(footerText());
    return b.toString();
  }
}

/// Debug-only runner — kompletný automatický test Stylist Chatu.
///
/// Jedno spustenie prebehne všetky scenáre a vyrobí report pre každý z nich
/// (outfit, explain, wardrobe analysis, identity score, reply source) + sumár.
class StylistChatPipelineDebugRunner {
  const StylistChatPipelineDebugRunner._();

  static const List<StylistChatDebugScenario> defaultScenarios = [
    StylistChatDebugScenario(label: 'svadba', prompt: 'Večer idem na svadbu.'),
    StylistChatDebugScenario(
      label: 'pohovor',
      prompt: 'Zajtra idem na pohovor.',
    ),
    StylistChatDebugScenario(
      label: 'práca',
      prompt: 'Čo si mám obliecť dnes do práce?',
    ),
    StylistChatDebugScenario(label: 'hory', prompt: 'Zajtra idem do hory.'),
    StylistChatDebugScenario(label: 'huby', prompt: 'Ráno idem na huby.'),
    StylistChatDebugScenario(
      label: 'grilovačka',
      prompt: 'Idem na grilovačku.',
    ),
    StylistChatDebugScenario(label: 'rande', prompt: 'Večer idem na rande.'),
    StylistChatDebugScenario(label: 'kino', prompt: 'Dnes večer idem do kina.'),
    StylistChatDebugScenario(
      label: 'večera',
      prompt: 'Idem na večeru v reštaurácii.',
    ),
    StylistChatDebugScenario(
      label: 'meeting',
      prompt: 'Zajtra mám dôležitý meeting v kancelárii.',
    ),
  ];

  /// Prompty pre spätnú kompatibilitu (staršie volania).
  static List<String> get defaultPrompts =>
      defaultScenarios.map((s) => s.prompt).toList(growable: false);

  static Future<StylistChatDebugRunResult> runAll({
    StylistChatOutfitService? outfitService,
    StylistChatService? chatService,
    List<StylistChatDebugScenario> scenarios = defaultScenarios,
    bool attemptAiExplain = true,
  }) async {
    assert(
      kDebugMode,
      'StylistChatPipelineDebugRunner je iba pre debug build.',
    );
    final outfits = outfitService ?? StylistChatOutfitService();
    final chat = chatService ?? StylistChatService();
    final reports = <StylistChatScenarioReport>[];

    debugPrint('');
    debugPrint('########## STYLIST CHAT PIPELINE DEBUG: START ##########');
    debugPrint('scenarios=${scenarios.length}');
    debugPrint('');

    for (var i = 0; i < scenarios.length; i++) {
      final scenario = scenarios[i];
      debugPrint(
        '--- DEBUG SCENÁR ${i + 1}/${scenarios.length}: '
        '${scenario.label} ---',
      );
      final report = await _runScenario(
        scenario: scenario,
        outfits: outfits,
        chat: chat,
        attemptAiExplain: attemptAiExplain,
      );
      reports.add(report);
    }

    final summary = StylistChatDebugSummary.fromReports(reports);
    final run = StylistChatDebugRunResult(reports: reports, summary: summary);

    // Čistý QA report do Logcatu (bez interných technických logov).
    debugPrint('');
    run.fullText().split('\n').forEach(debugPrint);

    debugPrint('########## STYLIST CHAT PIPELINE DEBUG: DONE ##########');
    debugPrint('');

    return run;
  }

  static Future<StylistChatScenarioReport> _runScenario({
    required StylistChatDebugScenario scenario,
    required StylistChatOutfitService outfits,
    required StylistChatService chat,
    required bool attemptAiExplain,
  }) async {
    final prompt = scenario.prompt;
    try {
      final collector = StylistChatOutfitDebugCollector();
      final event = StylistChatEventFromPrompt.build(prompt);
      final result = await outfits.generateForEvent(
        event: event,
        conversationHint: prompt,
        debugCollector: collector,
      );

      if (result == null) {
        return StylistChatScenarioReport(
          label: scenario.label,
          prompt: prompt,
          ok: false,
          error:
              'Outfit sa nevygeneroval (chýba používateľ, šatník alebo '
              'počasie).',
        );
      }

      final outfitItems = result.flexibleOutfit.items
          .map(
            (item) =>
                (item.display['name'] ?? item.item.canonicalType).toString(),
          )
          .toList(growable: false);
      final suggestedItems = result.flexibleOutfit.items
          .map((item) => <String, dynamic>{...item.display, ...item.toMap()})
          .toList(growable: false);
      final analysis = result.wardrobeAnalysis;

      final profile =
          result.occasionProfile ??
          StylistOccasionGuidance.profileFor(
            occasion: event.occasion,
            conversationText: prompt,
          );
      final activityType = result.outfitIntent?.activityType;

      final localExplain = StylistOutfitExplainBuilder.buildLocalExplainSk(
        suggestedItems: suggestedItems,
        profile: profile,
        wardrobeAnalysis: analysis,
        activityType: activityType,
        stylistOpinion: result.stylistOpinion,
        weatherIsRainy: result.weather?.isRainy ?? false,
        wetGroundMuddy: result.wetGroundMuddy,
        tempC: result.weather?.tempC,
        conversationText: prompt,
      );

      var explain = localExplain;
      var replySource = StylistChatReplySource.local;

      if (attemptAiExplain) {
        final ai = await _tryAiExplain(
          chat: chat,
          prompt: prompt,
          event: event,
          result: result,
          profile: profile,
          suggestedItems: suggestedItems,
        );
        if (ai != null) {
          explain = ai;
          replySource = StylistChatReplySource.ai;
        }
      }

      return StylistChatScenarioReport(
        label: scenario.label,
        prompt: prompt,
        ok: true,
        outfitItems: outfitItems,
        explain: explain,
        usedCompromise: analysis.usedCompromise,
        missingItems: analysis.missingItems,
        compromiseItems: analysis.compromiseItems,
        identityScore: result.activityIdentity?.score,
        identityReasons: result.activityIdentity?.reasons ?? const [],
        replySource: replySource,
        stylistOpinion: result.stylistOpinion,
      );
    } catch (e, st) {
      debugPrint('STYLIST CHAT debug scenario failed: $e\n$st');
      return StylistChatScenarioReport(
        label: scenario.label,
        prompt: prompt,
        ok: false,
        error: e.toString(),
      );
    }
  }

  /// Best-effort AI explain — reálny callable ako v chate. Pri chybe alebo
  /// nepoužiteľnej odpovedi vráti null a report použije lokálny explain.
  static Future<String?> _tryAiExplain({
    required StylistChatService chat,
    required String prompt,
    required StylistChatEventContext event,
    required StylistChatOutfitResult result,
    required StylistOccasionProfile profile,
    required List<Map<String, dynamic>> suggestedItems,
  }) async {
    final weather = result.weather;
    if (weather == null) return null;
    try {
      final explainPayload = <String, dynamic>{
        'occasionContext': <String, dynamic>{
          'label': profile.label,
          'template': result.flexibleOutfit.template.name,
          'items': result.flexibleOutfit.items
              .map((item) => item.toMap())
              .toList(growable: false),
        },
        'bottomGuidance': <String, dynamic>{'source': 'v2_composition'},
        'footwearGuidance': <String, dynamic>{'source': 'v2_composition'},
        'wardrobeAnalysis': result.wardrobeAnalysis.toPayload(),
        if (result.stylistOpinion != null)
          'stylistOpinion': result.stylistOpinion!.toPayload(),
      };
      final weatherContext = <String, dynamic>{
        'tempC': weather.tempC,
        'willRain': weather.isRainy,
        'isWindy': weather.isWindy,
        'season': weather.seasonKey,
        'fromOpenMeteo': false,
      };
      final response = await chat
          .sendMessage(
            prompt,
            mode: 'explain_outfit',
            weatherContext: weatherContext,
            selectedOutfitItems: suggestedItems,
            occasionContext: Map<String, dynamic>.from(
              explainPayload['occasionContext'] as Map,
            ),
            bottomGuidance: Map<String, dynamic>.from(
              explainPayload['bottomGuidance'] as Map,
            ),
            footwearGuidance: Map<String, dynamic>.from(
              explainPayload['footwearGuidance'] as Map,
            ),
            wardrobeAnalysis: explainPayload['wardrobeAnalysis'] is Map
                ? Map<String, dynamic>.from(
                    explainPayload['wardrobeAnalysis'] as Map,
                  )
                : result.wardrobeAnalysis.toPayload(),
            stylistOpinion: explainPayload['stylistOpinion'] is Map
                ? Map<String, dynamic>.from(
                    explainPayload['stylistOpinion'] as Map,
                  )
                : null,
          )
          .timeout(const Duration(seconds: 20));

      final ok = response['ok'] == true;
      final reply = (response['reply'] ?? '').toString().trim();
      final usable =
          ok &&
          reply.isNotEmpty &&
          !_isGenericErrorReply(reply) &&
          !StylistOutfitExplainBuilder.shouldUseLocalExplain(
            aiReply: reply,
            profile: profile,
            wardrobeAnalysis: result.wardrobeAnalysis,
            stylistOpinion: result.stylistOpinion,
          );
      return usable ? reply : null;
    } catch (e) {
      debugPrint('STYLIST CHAT debug ai_explain skipped: $e');
      return null;
    }
  }

  static bool _isGenericErrorReply(String reply) {
    final normalized = reply.toLowerCase();
    return normalized.contains('niečo sa pokazilo') ||
        normalized.contains('nieco sa pokazilo');
  }
}
