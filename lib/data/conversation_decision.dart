/// Čo má chat urobiť pred weather / AI / outfit generation.
enum ConversationAction {
  /// Máme dosť kontextu — pokračovať (weather, AI, outfit podľa flow).
  generate,

  /// Chýba kritická informácia — najprv doplňujúca otázka.
  clarify,

  /// Správa nie je outfit požiadavka — neblokujeme bežný chat.
  passthrough,
}

extension ConversationActionLabel on ConversationAction {
  String get label => switch (this) {
        ConversationAction.generate => 'GENERATE',
        ConversationAction.clarify => 'CLARIFY',
        ConversationAction.passthrough => 'PASSTHROUGH',
      };
}

/// Kritické chýbajúce informácie (môže ich byť viac; reasoner vráti prvú).
enum MissingInformation {
  none,
  specificLocation,
  destination,
  activity,
  time,
  venueType,
  performer,
}

extension MissingInformationLabel on MissingInformation {
  String get label => switch (this) {
        MissingInformation.none => 'none',
        MissingInformation.specificLocation => 'specific_location',
        MissingInformation.destination => 'destination',
        MissingInformation.activity => 'activity',
        MissingInformation.time => 'time',
        MissingInformation.venueType => 'venue_type',
        MissingInformation.performer => 'performer',
      };
}

/// Výsledok [ConversationReasoner.evaluate].
class ConversationDecision {
  const ConversationDecision({
    required this.action,
    required this.missingInformation,
    this.clarificationQuestionSk,
    required this.confidence,
    required this.reason,
    this.wantsOutfit = false,
  });

  factory ConversationDecision.passthrough({String reason = 'not_outfit_request'}) =>
      ConversationDecision(
        action: ConversationAction.passthrough,
        missingInformation: MissingInformation.none,
        confidence: 1.0,
        reason: reason,
      );

  factory ConversationDecision.generate({
    required String reason,
    double confidence = 0.9,
    bool wantsOutfit = true,
  }) =>
      ConversationDecision(
        action: ConversationAction.generate,
        missingInformation: MissingInformation.none,
        confidence: confidence,
        reason: reason,
        wantsOutfit: wantsOutfit,
      );

  factory ConversationDecision.clarify({
    required MissingInformation missing,
    required String questionSk,
    required String reason,
    double confidence = 0.92,
    bool wantsOutfit = true,
  }) =>
      ConversationDecision(
        action: ConversationAction.clarify,
        missingInformation: missing,
        clarificationQuestionSk: questionSk,
        confidence: confidence,
        reason: reason,
        wantsOutfit: wantsOutfit,
      );

  final ConversationAction action;
  final MissingInformation missingInformation;
  final String? clarificationQuestionSk;
  final double confidence;
  final String reason;
  final bool wantsOutfit;

  bool get shouldBlockPipeline =>
      action == ConversationAction.clarify;
}
