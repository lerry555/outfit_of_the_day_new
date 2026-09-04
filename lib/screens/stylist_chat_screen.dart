import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../data/conversation_decision.dart';
import '../data/stylist_opinion.dart';
import '../data/wardrobe_analysis.dart';
import '../debug/stylist_chat_pipeline_debug_runner.dart';
import '../debug/stylist_conversation_qa_runner.dart';
import '../debug/stylist_location_qa_runner.dart';
import '../Services/fcm_service.dart';
import '../Services/hourly_weather_service.dart';
import '../Services/stylist_chat_outfit_service.dart';
import '../Services/stylist_frozen_candidate_decision_service.dart';
import '../Services/stylist_udr_client_routing_v1.dart';
import '../Services/stylist_chat_service.dart';
import '../Services/stylist_simple_agent_service_v1.dart';
import '../Services/stylist_chat_store.dart';
import '../Services/stylist_job_consumer.dart';
import '../Services/stylist_notification_intent.dart';
import '../Services/user_location_service.dart';
import '../utils/slovak_city_locative.dart';
import '../utils/slovak_outfit_instrumental.dart';
import '../models/stylist_trip_window.dart';
import '../models/stylist_chat_progress.dart';
import '../widgets/stylist_quick_reply_buttons.dart';
import '../utils/bottom_family_guidance.dart';
import '../utils/footwear_family_guidance.dart';
import '../utils/event_clarification.dart';
import '../utils/stylist_bottom_request.dart';
import '../utils/stylist_intent_resolver.dart';
import '../utils/stylist_trip_parser.dart';
import '../utils/trip_weather_analyzer.dart';
import '../utils/conversation_reasoner.dart';
import '../utils/stylist_destination_parser.dart';
import '../utils/stylist_day_parser.dart';
import '../utils/stylist_city_suggester.dart';
import '../utils/stylist_occasion_guidance.dart';
import '../utils/stylist_outfit_explain_builder.dart';
import '../utils/stylist_swap_request.dart';
import '../utils/stylist_outfit_edit_routing.dart';
import '../domain/wardrobe_v2/outfit_edit_plan_v1.dart';
import '../utils/stylist_activity_terrain.dart';
import '../utils/stylist_wardrobe_context_need.dart';
import '../utils/stylist_conversation_signals.dart';
import '../utils/stylist_weather_tip.dart';
import '../utils/stylist_weather_adjustment.dart';
import '../utils/stylist_chat_entitlement.dart';
import '../utils/wardrobe_image_url_priority.dart';
import '../models/outfit_context_state.dart';
import '../models/shopping_ui_feature_flags.dart';
import '../models/stylist_shopping_runtime.dart';
import '../Services/shopping_wishlist_v2_service.dart';
import 'shopping/shopping_candidate_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Fáza rozhovoru o poslanej fotke. Riadi, či ďalšiu správu spracujeme ako
/// hodnotenie fotky (a v ktorej fáze), alebo ako bežný chat.
enum _PhotoStage {
  none,
  awaitingContext, // čakáme na intent + miesto (po fáze 1)
  awaitingWardrobeConsent, // po hodnotení sme ponúkli pohľad do šatníka
  awaitingOutfitConsent, // po návrhu kúsku sme ponúkli zloženie celého outfitu
}

class StylistChatMessage {
  final String text;
  final bool isUser;
  final List<Map<String, dynamic>> suggestedItems;
  final List<StylistShoppingAttachment> attachments;

  /// Lokálny súbor fotky (kým prebieha upload) — zobrazí sa hneď v bubline.
  final File? localImage;

  /// Vzdialená URL fotky po uploade (perzistentné zobrazenie po reštarte).
  final String? imageUrl;

  /// Dočasná systémová správa (napr. „pokojne si odbehni…"), ktorá sa po
  /// príchode skutočnej odpovede odstráni a do Firestore sa neukladá.
  final bool ephemeral;

  /// Job that produced this assistant turn. Used to dedupe notification hydration.
  final String? sourceJobId;

  /// Structural marker for a one-slot outfit edit. Persisted so reopening a
  /// chat never has to infer state from user-facing wording.
  final String? outfitUpdateSlot;

  /// Authoritative full outfit state returned by SIMPLE AGENT. This is kept
  /// separately from [suggestedItems], which contains only the IDs the model
  /// explicitly asked the UI to display on this turn.
  final List<Map<String, dynamic>> resultingOutfitItems;

  /// Explicit server-owned interaction hint. It is never inferred from Slovak
  /// wording, so open questions do not accidentally receive Áno/Nie buttons.
  final String quickReplyMode;

  const StylistChatMessage({
    required this.text,
    required this.isUser,
    this.suggestedItems = const <Map<String, dynamic>>[],
    this.attachments = const <StylistShoppingAttachment>[],
    this.localImage,
    this.imageUrl,
    this.ephemeral = false,
    this.sourceJobId,
    this.outfitUpdateSlot,
    this.resultingOutfitItems = const <Map<String, dynamic>>[],
    this.quickReplyMode = 'none',
  });

  StylistChatMessage copyWith({String? sourceJobId, String? outfitUpdateSlot}) {
    return StylistChatMessage(
      text: text,
      isUser: isUser,
      suggestedItems: suggestedItems,
      attachments: attachments,
      localImage: localImage,
      imageUrl: imageUrl,
      ephemeral: ephemeral,
      sourceJobId: sourceJobId ?? this.sourceJobId,
      outfitUpdateSlot: outfitUpdateSlot ?? this.outfitUpdateSlot,
      resultingOutfitItems: resultingOutfitItems,
      quickReplyMode: quickReplyMode,
    );
  }

  /// Serializácia pre Firestore. `localImage` (lokálny súbor) sa neukladá —
  /// po reštarte sa fotka zobrazí z `imageUrl`.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'text': text,
      'isUser': isUser,
      if (suggestedItems.isNotEmpty) 'suggestedItems': suggestedItems,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (sourceJobId != null && sourceJobId!.isNotEmpty)
        'sourceJobId': sourceJobId,
      if (outfitUpdateSlot != null && outfitUpdateSlot!.isNotEmpty)
        'outfitUpdateSlot': outfitUpdateSlot,
      if (resultingOutfitItems.isNotEmpty)
        'resultingOutfitItems': resultingOutfitItems,
      if (quickReplyMode == 'yes_no') 'quickReplyMode': quickReplyMode,
    };
  }

  factory StylistChatMessage.fromMap(Map<String, dynamic> map) {
    final rawItems = map['suggestedItems'];
    final rawResultItems = map['resultingOutfitItems'];
    final sourceJobId = (map['sourceJobId'] ?? '').toString().trim();
    return StylistChatMessage(
      text: (map['text'] ?? '').toString(),
      isUser: map['isUser'] == true,
      suggestedItems: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false)
          : const <Map<String, dynamic>>[],
      // Shopping facts are session-local server DTOs. They are intentionally
      // not restored from client-writable chat documents.
      attachments: const <StylistShoppingAttachment>[],
      imageUrl: (map['imageUrl'] ?? '').toString().isEmpty
          ? null
          : map['imageUrl'].toString(),
      sourceJobId: sourceJobId.isEmpty ? null : sourceJobId,
      outfitUpdateSlot:
          (map['outfitUpdateSlot'] ?? '').toString().trim().isEmpty
          ? null
          : (map['outfitUpdateSlot'] ?? '').toString().trim(),
      resultingOutfitItems: rawResultItems is List
          ? rawResultItems
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false)
          : const <Map<String, dynamic>>[],
      quickReplyMode: map['quickReplyMode'] == 'yes_no' ? 'yes_no' : 'none',
    );
  }
}

class StylistChatScreen extends StatefulWidget {
  final Map<String, dynamic>? initialClothingData;

  const StylistChatScreen({super.key, this.initialClothingData});

  @override
  State<StylistChatScreen> createState() => _StylistChatScreenState();
}

class _StylistChatScreenState extends State<StylistChatScreen> {
  static const _accent = Color(0xFFC8A36A);
  static const _bgTop = Color(0xFF111111);
  static const _bgMid = Color(0xFF0C0C0D);
  static const _bgBottom = Color(0xFF080809);
  static const _textPrimary = Color(0xFFF1F0EC);
  static const _textSecondary = Color(0xFFAAA59B);
  static const int _freeMessageLimit = 3;
  static const int _historyLimit = 8;
  static const bool _useAiClarifyFlow = true;

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _imagePicker = ImagePicker();
  final _stylistChatService = StylistChatService();
  final _stylistSimpleAgentService = StylistSimpleAgentServiceV1();
  final _shoppingWishlistService = ShoppingWishlistV2Service();
  final _shoppingDetailsService = ShoppingCandidateDetailsService();
  final _stylistChatOutfitService = StylistChatOutfitService();
  final _chatStore = StylistChatStore();
  final _hourlyWeatherService = HourlyWeatherService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  static const _greeting = StylistChatMessage(text: 'Ahoj :)', isUser: false);

  final List<StylistChatMessage> _messages = <StylistChatMessage>[_greeting];
  StylistShoppingSessionState _shoppingState =
      const StylistShoppingSessionState();

  // Multi-chat: id aktívneho chatu (null = nový, ešte neuložený), názov a
  // debounce timer na ukladanie do Firestore.
  String? _activeChatId;
  String? _chatTitle;
  bool _chatTitleEdited = false;
  bool _isLoadingChat = false;
  bool _isPersisting = false;
  Timer? _saveTimer;

  // Po ~10 s čakania na odpoveď zobrazíme dočasnú správu „pokojne si odbehni,
  // príde ti notifikácia". Po príchode odpovede ju zase odstránime.
  Timer? _awayHintTimer;
  static const Duration _awayHintDelay = Duration(seconds: 10);
  static const String _awayHintText =
      'Toto mi môže chvíľu trvať. Pokojne si odbehni — keď bude odpoveď '
      'hotová, pošlem ti upozornenie. 🔔';

  int _userMessageCount = 0;
  StylistChatEntitlement _entitlement = StylistChatEntitlement.unknown;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _entitlementSubscription;
  bool _sendingFlag = false;
  bool get _isSending => _sendingFlag;

  /// Pri zmene stavu odosielania spravujeme aj „odbehni" časovač:
  /// pri štarte ho spustíme, pri konci zrušíme a odstránime dočasnú správu.
  /// Pozn.: mutáciu zoznamu robíme priamo (bez setState), lebo priradenie
  /// `_isSending = ...` zvyčajne beží už vnútri setState volajúceho.
  set _isSending(bool value) {
    _sendingFlag = value;
    if (value) {
      _startAwayHintTimer();
    } else {
      _awayHintTimer?.cancel();
      _awayHintTimer = null;
      _messages.removeWhere((m) => m.ephemeral);
    }
  }

  File? _pendingImage;

  // Stav rozhovoru o aktuálnej fotke (lenivé hodnotenie + šatník).
  _PhotoStage _photoStage = _PhotoStage.none;
  String? _activePhotoUrl;
  String? _photoImproveHint;
  String _sendingStatusLabel = 'Stylista píše...';

  void _setSendingProgress(StylistChatProgressPhase phase) {
    if (!mounted || !_isSending) return;
    final next = phase.labelSk;
    if (_sendingStatusLabel == next) return;
    setState(() => _sendingStatusLabel = next);
  }

  Set<String> _lastOutfitItemIds = const {};
  List<Set<String>> _recentOutfitItemIdSets = const <Set<String>>[];
  bool _recentOutfitHistoryLoaded = false;
  List<Map<String, dynamic>> _currentOutfitItems =
      const <Map<String, dynamic>>[];
  bool _currentOutfitUsedCompromise = false;
  String _currentOutfitDecisionRationale = '';
  Map<String, dynamic>? _cachedWeatherContext;
  DateTime? _weatherCachedAt;
  int? _lastResolvedEventTempC;

  /// Obce/miesta, ktoré geokóder nevie nájsť (napr. ulica, malá osada alebo
  /// preklep). Pýtame sa naň raz na najbližšie väčšie mesto a potom ho
  /// preskakujeme, aby sme sa nepýtali dookola.
  final Set<String> _unresolvableDestinations = <String>{};
  OutfitContextState _outfitContextState = const OutfitContextState();
  String? _inFlightJobId;
  Future<void> _notificationWork = Future<void>.value();
  Future<void> _openChatInFlight = Future<void>.value();
  Completer<void>? _persistCompleter;
  static const _jobUnavailableText = 'Túto odpoveď už nemám k dispozícii.';

  @override
  void initState() {
    super.initState();
    _loadPremiumState();
    unawaited(FcmService.instance.init());
    unawaited(_bootstrapChatContext());
    StylistNotificationIntentStore.instance.addListener(
      _onStylistNotificationIntent,
    );
    unawaited(_consumeNotificationIntent());
  }

  /// Vygeneruje unikátne id pre asynchrónny job (na doručenie odpovede aj keď
  /// pôvodné volanie spadne, lebo appka šla na pozadie).
  String _newJobId() => _firestore.collection('stylistJobs').doc().id;

  /// Keď callable zlyhal kvôli pripojeniu, server mohol napriek tomu dobehnúť
  /// a výsledok zapísať do `stylistJobs/{jobId}`. Skúsime ho odtiaľ dotiahnuť,
  /// kým ostáva zobrazené „Stylista píše…". Inak vrátime pôvodnú odpoveď.
  Future<Map<String, dynamic>> _recoverIfOffline(
    Map<String, dynamic> response,
    String jobId,
  ) async {
    final failed = response['ok'] != true;
    final offline = response['offline'] == true;
    if (!failed || !offline) return response;
    final recovered = await _stylistChatService.awaitJobResult(jobId);
    return recovered ?? response;
  }

  Future<void> _bootstrapChatContext() async {
    await UserLocationService.instance.ensureResolved();
    await _ensureWeatherContext();
  }

  /// Notification tap: open the target thread, then hydrate [jobId] once.
  void _onStylistNotificationIntent() {
    unawaited(_consumeNotificationIntent());
  }

  Future<void> _consumeNotificationIntent() {
    _notificationWork = _notificationWork.catchError((_) {}).then((_) async {
      if (!mounted) return;
      await _hydrateNotificationIntent(
        StylistNotificationIntentStore.instance.current,
      );
    });
    return _notificationWork;
  }

  Future<void> _hydrateNotificationIntent(
    StylistNotificationIntent? intent,
  ) async {
    if (intent == null) {
      await _openMostRecentChat();
      return;
    }
    final store = StylistNotificationIntentStore.instance;
    if (store.wasHydrationHandled(intent.dedupeKey)) return;

    final targetedChatId = resolveStylistHydrationChatId(
      intentChatId: intent.chatId,
    );
    if (targetedChatId != null) {
      await _openChat(targetedChatId);
    } else {
      await _openMostRecentChat();
    }
    if (!mounted) return;

    final jobId = intent.jobId?.trim() ?? '';
    if (jobId.isEmpty) {
      store.markHydrationHandled(intent.dedupeKey);
      return;
    }
    if (_inFlightJobId == jobId) return;

    if (_chatAlreadyHasJob(jobId)) {
      unawaited(_stylistChatService.deleteJob(jobId));
      store.markHydrationHandled(intent.dedupeKey);
      return;
    }

    if (mounted) {
      setState(() {
        _isSending = true;
        _sendingStatusLabel = 'Stylista píše';
      });
    }

    final snapshot = await _stylistChatService.jobs.watchForHydration(jobId);
    if (!mounted) return;

    final resultChatId = resolveStylistHydrationChatId(
      resultChatId: snapshot.response?['chatId']?.toString(),
    );
    if (resultChatId != null && resultChatId != _activeChatId) {
      await _openChat(resultChatId);
      if (!mounted) return;
    }

    if (_chatAlreadyHasJob(jobId, replyText: _replyTextOf(snapshot.response))) {
      if (mounted) setState(() => _isSending = false);
      unawaited(_stylistChatService.deleteJob(jobId));
      store.markHydrationHandled(intent.dedupeKey);
      return;
    }

    if (snapshot.status == StylistJobStatus.missing) {
      if (mounted) {
        setState(() {
          _messages.add(
            const StylistChatMessage(text: _jobUnavailableText, isUser: false),
          );
          _isSending = false;
        });
        _scrollToBottom();
      }
      store.markHydrationHandled(intent.dedupeKey);
      return;
    }

    if (snapshot.status == StylistJobStatus.pending) {
      if (mounted) setState(() => _isSending = false);
      return;
    }

    if (snapshot.status == StylistJobStatus.failed) {
      final start = _messages.length;
      await _applyNormalizedJobResponse(
        snapshot.response ??
            const <String, dynamic>{
              'ok': false,
              'offline': false,
              'reply': '',
              'action': 'chat',
            },
      );
      _stampMessagesWithJobId(start, jobId);
      final persisted = await _persistNow(
        awaitWrite: true,
        allowWithoutUserMessages: true,
      );
      if (persisted) await _stylistChatService.deleteJob(jobId);
      store.markHydrationHandled(intent.dedupeKey);
      return;
    }

    try {
      final start = _messages.length;
      final consumed = await consumeCompletedJobSafely(
        snapshot: snapshot,
        apply: _applyNormalizedJobResponse,
        persistChat: () async {
          _stampMessagesWithJobId(start, jobId);
          return _persistNow(awaitWrite: true, allowWithoutUserMessages: true);
        },
        deleteJob: _stylistChatService.deleteJob,
      );
      if (!consumed && mounted) setState(() => _isSending = false);
      if (consumed) {
        store.markHydrationHandled(intent.dedupeKey);
      }
    } catch (_) {
      if (mounted) setState(() => _isSending = false);
    }
  }

  bool _chatAlreadyHasJob(String jobId, {String? replyText}) {
    return stylistChatAlreadyHasJobResult(
      sourceJobIds: _messages.map((m) => m.sourceJobId),
      assistantTexts: _messages
          .where((m) => !m.isUser && !m.ephemeral)
          .map((m) => m.text),
      jobId: jobId,
      replyText: replyText,
    );
  }

  String? _replyTextOf(Map<String, dynamic>? response) {
    final raw = (response?['reply'] ?? '').toString();
    if (raw.trim().isEmpty) return null;
    return _sanitizeStylistReplyForDisplay(raw);
  }

  void _stampMessagesWithJobId(int startIndex, String jobId) {
    for (var i = startIndex; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.isUser || message.ephemeral) continue;
      if (message.sourceJobId != null && message.sourceJobId!.isNotEmpty) {
        continue;
      }
      _messages[i] = message.copyWith(sourceJobId: jobId);
    }
  }

  Future<void> _applyNormalizedJobResponse(
    Map<String, dynamic> response,
  ) async {
    if (response['simpleAgent'] == true) {
      _handleSimpleAgentResponse(response);
      return;
    }
    final lastUser = _messages.lastWhere(
      (m) => m.isUser && m.text.trim().isNotEmpty,
      orElse: () => const StylistChatMessage(text: '', isUser: true),
    );
    await _handleAssistantResponse(
      userText: lastUser.text,
      response: response,
      history: _buildHistoryForBackend(),
      weatherContext: Map<String, dynamic>.from(_cachedWeatherContext ?? {}),
      clientContext: _buildClientContext(
        cityName: _cachedWeatherContext?['cityName']?.toString(),
      ),
    );
  }

  Future<void> _completeSuccessfulJob(String jobId) async {
    final persisted = await _persistNow(awaitWrite: true);
    if (persisted) {
      await _stylistChatService.deleteJob(jobId);
    }
  }

  /// Pri otvorení obrazovky pokračujeme v poslednom chate (ak existuje).
  Future<void> _openMostRecentChat() async {
    try {
      final threads = await _chatStore.watchThreads().first;
      if (!mounted || threads.isEmpty) return;
      // Nezačali sme ešte nič písať → plynule otvoríme posledný chat.
      if (_activeChatId == null && !_hasUserMessages()) {
        await _openChat(threads.first.id);
      }
    } catch (_) {
      // Bez histórie pokračujeme s prázdnym chatom.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _awayHintTimer?.cancel();
    unawaited(_entitlementSubscription?.cancel());
    StylistNotificationIntentStore.instance.removeListener(
      _onStylistNotificationIntent,
    );
    unawaited(_persistNow());
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _hasUserMessages() => _messages.any((m) => m.isUser);

  /// Spustí 10-sekundový časovač, ktorý (ak ešte stále čakáme na odpoveď)
  /// pridá dočasnú správu, že používateľ môže odísť a príde mu notifikácia.
  void _startAwayHintTimer() {
    _awayHintTimer?.cancel();
    _awayHintTimer = Timer(_awayHintDelay, () {
      if (!mounted || !_isSending) return;
      // Nevkladaj duplicitne.
      if (_messages.any((m) => m.ephemeral)) return;
      setState(() {
        _messages.add(
          const StylistChatMessage(
            text: _awayHintText,
            isUser: false,
            ephemeral: true,
          ),
        );
      });
      _scrollToBottom();
    });
  }

  /// Naplánuje uloženie chatu (debounce), aby sa nezapisovalo po každom znaku.
  void _schedulePersist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_persistNow());
    });
  }

  /// Zapíše aktuálny chat do Firestore. Prázdny chat (len pozdrav) neukladá,
  /// unless [allowWithoutUserMessages] (notification hydration).
  Future<bool> _persistNow({
    bool awaitWrite = false,
    bool allowWithoutUserMessages = false,
  }) async {
    if (_isLoadingChat) return false;
    if (!_hasUserMessages() && !allowWithoutUserMessages) return false;
    if (_isPersisting) {
      await _persistCompleter?.future;
    }
    if (_isLoadingChat) return false;
    if (!_hasUserMessages() && !allowWithoutUserMessages) return false;
    if (_isPersisting) return false;
    _isPersisting = true;
    _persistCompleter = Completer<void>();
    try {
      final title = _resolveChatTitle();
      if (_activeChatId == null) {
        final id = await _chatStore.createChat(
          title: title,
          awaitWrite: awaitWrite,
        );
        if (id == null) return false;
        _activeChatId = id;
        _chatTitle = title;
      }
      await _chatStore.saveChat(
        chatId: _activeChatId!,
        messages: _messages
            .where(
              (m) =>
                  !m.ephemeral &&
                  (m.text.trim().isNotEmpty || m.imageUrl != null),
            )
            .map((m) => m.toMap())
            .toList(growable: false),
        title: title,
        photoStage: _photoStage.name,
        activePhotoUrl: _activePhotoUrl,
        photoImproveHint: _photoImproveHint,
        userMessageCount: _userMessageCount,
        awaitWrite: awaitWrite,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      _isPersisting = false;
      final gate = _persistCompleter;
      _persistCompleter = null;
      if (gate != null && !gate.isCompleted) {
        gate.complete();
      }
    }
  }

  /// Názov chatu: ručne zadaný, inak z prvej správy používateľa.
  String _resolveChatTitle() {
    if (_chatTitleEdited && (_chatTitle?.trim().isNotEmpty ?? false)) {
      return _chatTitle!.trim();
    }
    final firstUser = _messages.firstWhere(
      (m) => m.isUser && m.text.trim().isNotEmpty,
      orElse: () => const StylistChatMessage(text: '', isUser: true),
    );
    var raw = firstUser.text.trim();
    if (raw.isEmpty) raw = 'Fotka outfitu';
    if (raw.length > 42) raw = '${raw.substring(0, 42).trimRight()}…';
    return raw;
  }

  /// Vyčistí stav na prázdny chat (BEZ ukladania). Volané z „nový chat" aj po
  /// zmazaní aktívneho chatu.
  void _resetChatState() {
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..add(_greeting);
      _activeChatId = null;
      _chatTitle = null;
      _chatTitleEdited = false;
      _userMessageCount = 0;
      _photoStage = _PhotoStage.none;
      _activePhotoUrl = null;
      _photoImproveHint = null;
      _pendingImage = null;
      _isSending = false;
      _lastOutfitItemIds = const {};
      _currentOutfitItems = const <Map<String, dynamic>>[];
      _outfitContextState = const OutfitContextState();
      _lastResolvedEventTempC = null;
      _unresolvableDestinations.clear();
    });
    _controller.clear();
  }

  /// Založí nový prázdny chat (predošlý ostáva uložený v histórii).
  Future<void> _startNewChat() async {
    _saveTimer?.cancel();
    await _persistNow();
    _resetChatState();
  }

  /// Otvorí existujúci chat z histórie a obnoví jeho stav.
  Future<void> _openChat(String chatId) {
    _openChatInFlight = _openChatInFlight
        .catchError((_) {})
        .then((_) => _openChatBody(chatId));
    return _openChatInFlight;
  }

  Future<void> _openChatBody(String chatId) async {
    if (chatId == _activeChatId) return;
    _saveTimer?.cancel();
    await _persistNow();
    _isLoadingChat = true;
    try {
      final data = await _chatStore.loadChat(chatId);
      if (!mounted) return;
      final rawMessages = data?['messages'];
      final loaded = rawMessages is List
          ? rawMessages
                .whereType<Map>()
                .map(
                  (e) =>
                      StylistChatMessage.fromMap(Map<String, dynamic>.from(e)),
                )
                .toList()
          : <StylistChatMessage>[];
      final stageName = (data?['photoStage'] ?? 'none').toString();
      setState(() {
        _messages
          ..clear()
          ..addAll(loaded.isEmpty ? const [_greeting] : loaded);
        _activeChatId = chatId;
        _chatTitle = (data?['title'] ?? '').toString();
        _chatTitleEdited = _chatTitle!.trim().isNotEmpty;
        _userMessageCount = (data?['userMessageCount'] is int)
            ? data!['userMessageCount'] as int
            : _messages.where((m) => m.isUser).length;
        _photoStage = _PhotoStage.values.firstWhere(
          (s) => s.name == stageName,
          orElse: () => _PhotoStage.none,
        );
        _activePhotoUrl = (data?['activePhotoUrl'] ?? '').toString().isEmpty
            ? null
            : data!['activePhotoUrl'].toString();
        _photoImproveHint = (data?['photoImproveHint'] ?? '').toString().isEmpty
            ? null
            : data!['photoImproveHint'].toString();
        _pendingImage = null;
        _isSending = false;
        _currentOutfitItems = const <Map<String, dynamic>>[];
        final restoredOutfit = _resolvedCurrentOutfitItems();
        _currentOutfitItems = List<Map<String, dynamic>>.unmodifiable(
          restoredOutfit,
        );
        _lastOutfitItemIds = Set<String>.unmodifiable(
          restoredOutfit
              .map((item) => (item['id'] ?? '').toString().trim())
              .where((id) => id.isNotEmpty),
        );
        _outfitContextState = const OutfitContextState();
        _lastResolvedEventTempC = null;
        _unresolvableDestinations.clear();
      });
      _scrollToBottom();
    } catch (_) {
      // Necháme aktuálny chat, ak sa nepodarilo načítať.
    } finally {
      _isLoadingChat = false;
    }
  }

  Future<void> _loadPremiumState() async {
    final user = _auth.currentUser;
    await _entitlementSubscription?.cancel();
    _entitlementSubscription = null;
    if (!mounted) return;
    setState(() => _entitlement = StylistChatEntitlement.unknown);
    if (user == null) return;

    _entitlementSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _entitlement = StylistChatEntitlementPolicy.fromUserDocument(
                snap.data(),
              );
            });
          },
          onError: (_) {
            // UNKNOWN is intentionally fail-open for chat access. A transient
            // entitlement read must never masquerade as an authoritative FREE.
            if (!mounted) return;
            setState(() => _entitlement = StylistChatEntitlement.unknown);
          },
        );
  }

  bool get _freeLimitReached => StylistChatEntitlementPolicy.blocksMessage(
    entitlement: _entitlement,
    userMessageCount: _userMessageCount,
    freeMessageLimit: _freeMessageLimit,
  );

  Future<void> _sendMessage() async {
    if (_isSending) return;
    final text = _controller.text.trim();
    if (_pendingImage != null) {
      await _startPhotoConversation(text);
      return;
    }
    if (_photoStage != _PhotoStage.none) {
      if (text.isEmpty) return;
      await _continuePhotoConversation(text);
      return;
    }
    if (text.isEmpty) return;

    if (_freeLimitReached) {
      _showPremiumBottomSheet();
      return;
    }

    setState(() {
      _messages.add(StylistChatMessage(text: text, isUser: true));
      _controller.clear();
      _userMessageCount += 1;
      _isSending = true;
      _sendingStatusLabel = StylistChatProgressPhase.resolvingContext.labelSk;
    });
    _scrollToBottom();

    try {
      var history = _buildHistoryForBackend();
      if (history.isNotEmpty &&
          history.last['role'] == 'user' &&
          history.last['content'] == text) {
        history = history.sublist(0, history.length - 1);
      }
      final restoredCurrent = _resolvedCurrentOutfitItems();
      final currentIds = restoredCurrent
          .map((item) => (item['id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      _setSendingProgress(StylistChatProgressPhase.checkingWeather);
      final weatherContext = await _simpleAgentWeatherContext();
      final clientContext = _simpleAgentClientContext();
      final jobId = _newJobId();
      _inFlightJobId = jobId;
      _setSendingProgress(StylistChatProgressPhase.thinkingWithContext);
      var response = await _stylistSimpleAgentService.sendTurn(
        message: text,
        history: history,
        currentOutfitItemIds: currentIds,
        currentSelectionReasons: [
          for (final item in restoredCurrent)
            if ((item['stylistSelectionReason'] ?? '').toString().trim().isNotEmpty)
              {
                'itemId': (item['id'] ?? '').toString(),
                'reason': item['stylistSelectionReason'].toString(),
              },
        ],
        weatherContext: weatherContext,
        clientContext: clientContext,
        notifyJobId: jobId,
        chatId: _activeChatId,
      );
      response = await _recoverIfOffline(response, jobId);
      if (!mounted) {
        _inFlightJobId = null;
        return;
      }
      final start = _messages.length;
      _handleSimpleAgentResponse(response);
      _stampMessagesWithJobId(start, jobId);
      if (response['simpleAgent'] == true) {
        await _completeSuccessfulJob(jobId);
      }
      _inFlightJobId = null;
    } catch (_) {
      _inFlightJobId = null;
      if (!mounted) return;
      setState(() {
        _messages.add(
          StylistChatMessage(
            text:
                'Nepodarilo sa spojiť s AI 😅 Skontroluj internetové pripojenie '
                'a skús to znova neskôr.',
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendQuickReply(String text) async {
    if (_isSending) return;
    _controller
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
    await _sendMessage();
  }

  Future<Map<String, dynamic>> _simpleAgentWeatherContext() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final city = UserLocationService.instance.cityShortLabel;
    try {
      final snapshots = await Future.wait([
        _hourlyWeatherService.getWeatherForCityAndDate(city: city, date: today),
        _hourlyWeatherService.getWeatherForCityAndDate(
          city: city,
          date: tomorrow,
        ),
      ]);
      return <String, dynamic>{
        'location': city,
        'today': _snapshotToWeatherContext(snapshots[0]),
        'tomorrow': _snapshotToWeatherContext(snapshots[1]),
      };
    } catch (_) {
      await _ensureWeatherContext();
      return <String, dynamic>{
        'location': city,
        'today': _weatherContextForApi(lightweight: false),
      };
    }
  }

  Map<String, dynamic> _simpleAgentClientContext() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    String dateKey(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    final location = UserLocationService.instance.cityLabel.trim();
    final lat = UserLocationService.instance.latitude;
    final lon = UserLocationService.instance.longitude;
    return <String, dynamic>{
      'now': now.toIso8601String(),
      'todayDateKey': dateKey(today),
      'tomorrowDateKey': dateKey(tomorrow),
      'timezoneOffsetMinutes': now.timeZoneOffset.inMinutes,
      if (location.isNotEmpty) 'userGpsLocation': location,
      if (lat != null) 'latitude': lat,
      if (lon != null) 'longitude': lon,
    };
  }

  void _handleSimpleAgentResponse(Map<String, dynamic> response) {
    final reply = (response['stylistComment'] ?? response['reply'] ?? '')
        .toString()
        .trim();
    if (response['ok'] != true || response['failClosed'] == true) {
      setState(() {
        _messages.add(
          StylistChatMessage(
            text: reply.isEmpty
                ? 'Túto požiadavku sa mi nepodarilo bezpečne dokončiť, takže aktuálny outfit nemením.'
                : reply,
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
      return;
    }

    final resultingRaw = response['resultingOutfitItems'];
    final displayRaw = response['displayItems'];
    final resultingItems = resultingRaw is List
        ? resultingRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final displayItems = displayRaw is List
        ? displayRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final resultingIds = resultingItems
        .map((item) => (item['id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    if (resultingItems.isNotEmpty) {
      _currentOutfitItems = List<Map<String, dynamic>>.unmodifiable(
        resultingItems,
      );
      _lastOutfitItemIds = Set<String>.unmodifiable(resultingIds);
    }
    debugPrint(
      'SIMPLE_AGENT_VALIDATED uiResult=${resultingIds.toList()} '
      'uiDisplay=${displayItems.map((item) => item['id']).toList()}',
    );
    setState(() {
      _messages.add(
        StylistChatMessage(
          text: reply,
          isUser: false,
          suggestedItems: displayItems,
          resultingOutfitItems: resultingItems,
          quickReplyMode: response['quickReplyMode'] == 'yes_no'
              ? 'yes_no'
              : 'none',
        ),
      );
      _isSending = false;
    });
    _scrollToBottom();
  }

  Future<void> _showImageSourceSheet() async {
    if (_isSending) return;
    FocusScope.of(context).unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _bgMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_outlined,
                  color: _accent,
                ),
                title: const Text(
                  'Odfotiť',
                  style: TextStyle(color: _textPrimary),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: _accent,
                ),
                title: const Text(
                  'Vybrať z galérie',
                  style: TextStyle(color: _textPrimary),
                ),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (source == null) return;
    await _pickImage(source);
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null || !mounted) return;
      setState(() => _pendingImage = File(picked.path));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fotku sa nepodarilo načítať.')),
      );
    }
  }

  Future<String?> _uploadStylistPhoto(File file) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    // Pozn.: zámerne nahrávame do už povolenej cesty wardrobe/{uid}/ (rovnaké
    // Storage pravidlo ako pridávanie oblečenia). Prefix `stylist_` odlíši
    // foto z chatu; do šatníka sa nedostane (ten sa riadi Firestore).
    final fileName = 'stylist_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final storagePath = 'wardrobe/${user.uid}/$fileName';
    final ref = _storage.ref().child(storagePath);
    final bytes = await file.readAsBytes();
    final task = await ref
        .putData(bytes, SettableMetadata(contentType: 'image/jpeg'))
        .timeout(const Duration(seconds: 30));
    return task.ref.getDownloadURL().timeout(const Duration(seconds: 15));
  }

  /// Fáza 1: používateľ poslal fotku. Nahráme ju, ukážeme v bubline a
  /// (ak ešte nepoznáme miesto) sa LOKÁLNE spýtame na zámer + kam ide —
  /// bez volania AI a bez čítania šatníka.
  Future<void> _startPhotoConversation(String text) async {
    final image = _pendingImage;
    if (image == null) return;

    if (_freeLimitReached) {
      _showPremiumBottomSheet();
      return;
    }

    setState(() {
      _messages.add(
        StylistChatMessage(text: text, isUser: true, localImage: image),
      );
      _controller.clear();
      _pendingImage = null;
      _userMessageCount += 1;
      _isSending = true;
      _sendingStatusLabel = 'Nahrávam fotku…';
    });
    _scrollToBottom();

    try {
      final imageUrl = await _uploadStylistPhoto(image);
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('upload_failed');
      }
      _activePhotoUrl = imageUrl;
      _photoImproveHint = null;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const StylistChatMessage(
            text: 'Fotku sa mi nepodarilo nahrať 😅 Skús to prosím ešte raz.',
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
      return;
    }

    // Ak už poznáme miesto, alebo z textu vidno jasný zámer (chce názor na
    // outfit, prípadne spomenul príležitosť ako pohreb/svadbu), netreba sa
    // pýtať — rovno hodnotíme. Počasie sa vyrieši z konverzácie alebo z polohy.
    final conversation = _conversationHintText();
    final knownPlace = StylistDestinationParser.inferFromConversation(
      conversation,
      exclude: _unresolvableDestinations,
    );
    final placeKnown =
        knownPlace != null &&
        StylistDestinationParser.isPlausibleDestination(knownPlace);
    if (placeKnown || _photoTextHasClearRatingIntent(text)) {
      _photoStage = _PhotoStage.awaitingContext;
      await _runPhotoRating(text, wardrobeAccess: false);
      return;
    }

    // Nepoznáme ani zámer, ani miesto → položíme jednu prirodzenú otázku.
    if (!mounted) return;
    const askText =
        'Pekná fotka 📸 Mám zhodnotiť celý outfit, alebo sa '
        'zamerať na niečo konkrétne? A kam to ideš / čo máš v pláne?';
    setState(() {
      _messages.add(const StylistChatMessage(text: askText, isUser: false));
      _photoStage = _PhotoStage.awaitingContext;
      _isSending = false;
    });
    _scrollToBottom();
  }

  /// Heuristika: rozpozná, či používateľ v texte k fotke už jasne žiada
  /// zhodnotenie celého outfitu (nech sa appka nepýta zbytočne „čo s fotkou").
  bool _photoTextHasClearRatingIntent(String text) {
    final t = _foldDiacritics(text.toLowerCase());
    if (t.trim().isEmpty) return false;
    const cues = <String>[
      'co si mysl',
      'co tomu hovor',
      'co povies',
      'co hovoris',
      'ohodnot',
      'zhodnot',
      'hodnot',
      'nazor',
      'ako sa ti paci',
      'paci sa ti',
      'sedi mi to',
      'pristane mi',
      'vyzeram',
      'cely outfit',
      'moj outfit',
      'mojom outfite',
      'na outfit',
      'ako vyzera',
      // Príležitosti — keď ich spomenie, vie, že chce hodnotiť outfit naň.
      'pohreb', 'svadb', 'pohovor', 'rande', 'oslav', 'stuzkov', 'maturit',
      'do prace', 'do roboty', 'do divadla', 'do kostola', 'na koncert',
    ];
    return cues.any(t.contains);
  }

  String _foldDiacritics(String input) {
    const map = {
      'á': 'a',
      'ä': 'a',
      'č': 'c',
      'ď': 'd',
      'é': 'e',
      'ě': 'e',
      'í': 'i',
      'ĺ': 'l',
      'ľ': 'l',
      'ň': 'n',
      'ó': 'o',
      'ô': 'o',
      'ŕ': 'r',
      'š': 's',
      'ť': 't',
      'ú': 'u',
      'ů': 'u',
      'ý': 'y',
      'ž': 'z',
    };
    final sb = StringBuffer();
    for (final ch in input.split('')) {
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  /// Ďalšie správy, kým prebieha rozhovor o fotke. Riadi sa podľa fázy.
  Future<void> _continuePhotoConversation(String text) async {
    if (_freeLimitReached) {
      _showPremiumBottomSheet();
      return;
    }

    setState(() {
      _messages.add(StylistChatMessage(text: text, isUser: true));
      _controller.clear();
      _userMessageCount += 1;
      _isSending = true;
      _sendingStatusLabel = 'Stylista píše';
    });
    _scrollToBottom();

    switch (_photoStage) {
      case _PhotoStage.awaitingContext:
        await _runPhotoRating(text, wardrobeAccess: false);
        break;
      case _PhotoStage.awaitingWardrobeConsent:
        if (_isNegativeReply(text)) {
          _photoStage = _PhotoStage.none;
          _addStylistMessage('Ok, nechám to tak 🙂 Keby čokoľvek, som tu.');
        } else {
          await _runPhotoRating(text, wardrobeAccess: true);
        }
        break;
      case _PhotoStage.awaitingOutfitConsent:
        if (_isAffirmativeReply(text)) {
          await _generateOutfitAfterPhoto(text);
        } else {
          _photoStage = _PhotoStage.none;
          _addStylistMessage('Dobre, nechám to na tebe 🙂');
        }
        break;
      case _PhotoStage.none:
        _photoStage = _PhotoStage.none;
        setState(() => _isSending = false);
        break;
    }
  }

  /// Spustí AI hodnotenie fotky. `wardrobeAccess=false` = len názor (fáza 2),
  /// `true` = názor + návrh kúsku zo šatníka (fáza 3).
  Future<void> _runPhotoRating(
    String text, {
    required bool wardrobeAccess,
  }) async {
    final imageUrl = _activePhotoUrl;
    if (imageUrl == null) {
      _photoStage = _PhotoStage.none;
      if (mounted) setState(() => _isSending = false);
      return;
    }
    if (mounted) {
      setState(
        () => _sendingStatusLabel = wardrobeAccess
            ? 'Pozerám do šatníka…'
            : 'Hodnotím outfit…',
      );
    }
    try {
      final history = _buildHistoryForBackend();
      final weatherContext = await _resolveWeatherContextForRequest(
        lightweight: true,
      );
      final clientContext = _buildClientContext(
        cityName: weatherContext['cityName']?.toString(),
      );
      final jobId = _newJobId();
      _inFlightJobId = jobId;
      var response = await _stylistChatService.sendMessage(
        text,
        history: history,
        weatherContext: weatherContext,
        clientContext: clientContext,
        mode: 'rate_photo',
        imageUrl: imageUrl,
        wardrobeAccess: wardrobeAccess,
        improveHint: wardrobeAccess ? _photoImproveHint : null,
        notifyJobId: jobId,
        chatId: _activeChatId,
      );
      // Appka mohla ísť počas analýzy fotky na pozadie — server dobehol a
      // výsledok je vo Firestore, dotiahneme ho.
      response = await _recoverIfOffline(response, jobId);
      if (!mounted) {
        _inFlightJobId = null;
        return;
      }

      // Bez internetu callable zlyhá a vráti prázdnu odpoveď — namiesto mätúceho
      // „zamotal som sa" povieme jasne, že je problém s pripojením.
      if (response['ok'] != true) {
        _inFlightJobId = null;
        _photoStage = wardrobeAccess ? _photoStage : _PhotoStage.none;
        setState(() {
          _messages.add(
            StylistChatMessage(
              text: response['offline'] == true
                  ? 'Vyzerá to, že nie si pripojený na internet 📶 Skontroluj '
                        'pripojenie a skús to znova.'
                  : 'Hodnotenie sa teraz nepodarilo 😅 Skús to prosím o chvíľu.',
              isUser: false,
            ),
          );
          _isSending = false;
        });
        _scrollToBottom();
        return;
      }

      final reply = _sanitizeStylistReplyForDisplay(
        (response['reply'] ?? '').toString(),
      );
      final suggestedRaw = response['suggestedItems'];
      final suggestedItems = _sortStylistSuggestedItems(
        suggestedRaw is List
            ? suggestedRaw
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .take(4)
                  .toList(growable: false)
            : const <Map<String, dynamic>>[],
      );
      final offerWardrobe = response['offerWardrobe'] == true;
      debugPrint(
        'STYLIST CHAT rate_photo wardrobeAccess=$wardrobeAccess '
        'offerWardrobe=$offerWardrobe suggested=${suggestedItems.length}',
      );

      setState(() {
        _messages.add(
          StylistChatMessage(
            text: reply,
            isUser: false,
            suggestedItems: suggestedItems,
            sourceJobId: jobId,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
      if (response['ok'] == true) {
        await _completeSuccessfulJob(jobId);
      }
      _inFlightJobId = null;

      if (!wardrobeAccess) {
        // Fáza 2 → ak AI ponúkla šatník, čakáme na súhlas; inak koniec.
        // Uložíme, čoho sa má vylepšenie týkať, nech fáza 3 nemení iný kúsok.
        _photoImproveHint = (response['improveHint'] ?? '').toString().trim();
        _photoStage = offerWardrobe
            ? _PhotoStage.awaitingWardrobeConsent
            : _PhotoStage.none;
      } else {
        // Fáza 3 → kritika + konkrétne náhrady zo šatníka (a zmienka, čo si
        // môže nechať) sú kompletná odpoveď. Druhý „celý outfit" už NEskladáme
        // — mátol používateľa a strácal kontext príležitosti (napr. pohreb).
        if (suggestedItems.isNotEmpty) {
          _lastOutfitItemIds = suggestedItems
              .map((e) => (e['id'] ?? '').toString().trim())
              .where((id) => id.isNotEmpty)
              .toSet();
        }
        _photoStage = _PhotoStage.none;
      }
    } catch (_) {
      _inFlightJobId = null;
      if (!mounted) return;
      _photoStage = _PhotoStage.none;
      setState(() {
        _messages.add(
          const StylistChatMessage(
            text:
                'Fotku sa mi nepodarilo spracovať 😅 Skús to prosím ešte raz.',
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  /// Fáza 4: po návrhu kúsku zložíme celý outfit cez existujúci hybrid flow.
  Future<void> _generateOutfitAfterPhoto(String text) async {
    _photoStage = _PhotoStage.none;
    try {
      final history = _buildHistoryForBackend();
      final weatherContext = await _resolveWeatherContextForRequest(
        lightweight: true,
      );
      final clientContext = _buildClientContext(
        cityName: weatherContext['cityName']?.toString(),
      );
      // Pozn.: po fotke sa už NEPÝTAME na mesto — počasie sme vyriešili pri
      // hodnotení (z miesta v konverzácii alebo z polohy). Outfit zložíme rovno.
      final event = _eventFromConversation(
        rawEvent: null,
        fallbackLocation: UserLocationService.instance.cityLabel,
      );
      await _runHybridOutfitGeneration(
        userText: text,
        history: history,
        weatherContext: weatherContext,
        clientContext: clientContext,
        event: event,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const StylistChatMessage(
            text: 'Outfit sa mi teraz nepodarilo zložiť 😅 Skús to ešte raz.',
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
    }
  }

  void _addStylistMessage(String text) {
    if (!mounted) return;
    setState(() {
      _messages.add(StylistChatMessage(text: text, isUser: false));
      _isSending = false;
    });
    _scrollToBottom();
  }

  bool _isAffirmativeReply(String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return false;
    const yes = [
      'ano',
      'áno',
      'hej',
      'jasn',
      'okej',
      'okay',
      'jj',
      'pozri',
      'mrkni',
      'mrkn',
      'skus',
      'skús',
      'chcem',
      'môže',
      'moze',
      'rad',
      'rád',
      'super',
      'poď',
      'davaj',
      'dávaj',
      'urcite',
      'určite',
      'beriem',
    ];
    if (t == 'ok' || t == 'no' || t == 'hm' || t.startsWith('ok ')) return true;
    return yes.any(t.contains);
  }

  bool _isNegativeReply(String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return false;
    const no = [
      'nie',
      'netreba',
      'nechaj',
      'nemus',
      'no thanks',
      'nechcem',
      'kludne nie',
      'kľudne nie',
      'radsej nie',
      'radšej nie',
    ];
    return no.any(t.contains);
  }

  Map<String, dynamic>? _brainOutfitDirective(Map<String, dynamic> response) {
    final raw = response['outfitDirective'];
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  String _brainDirectiveValue(
    Map<String, dynamic>? directive,
    String key,
    String fallback,
  ) {
    final value = directive?[key]?.toString().trim().toLowerCase() ?? '';
    return value.isEmpty ? fallback : value;
  }

  StylistSwapRequest? _legacySwapRequestForTurn(
    Map<String, dynamic> response,
    String userText,
  ) {
    final directive = _brainOutfitDirective(response);
    if (directive != null) {
      if (_brainDirectiveValue(directive, 'scope', 'none') != 'single_slot') {
        return null;
      }
      final slot = switch (_brainDirectiveValue(directive, 'slot', 'none')) {
        'top' => StylistSwapSlot.top,
        'bottom' => StylistSwapSlot.bottom,
        'shoes' => StylistSwapSlot.shoes,
        'outerwear' => StylistSwapSlot.outerwear,
        _ => null,
      };
      if (slot == null) return null;
      final family = _brainDirectiveValue(directive, 'family', 'none');
      final bottomFamily = slot == StylistSwapSlot.bottom
          ? switch (family) {
              'shorts' => BottomFamily.shorts,
              'jeans' => BottomFamily.jeans,
              'pants' => BottomFamily.pants,
              'joggers' => BottomFamily.joggers,
              _ => null,
            }
          : null;
      final shoeFamily = slot == StylistSwapSlot.shoes
          ? switch (family) {
              'sneakers' => FootwearFamily.sneakers,
              'boots' => FootwearFamily.boots,
              'sandals' => FootwearFamily.sandals,
              'formal_shoes' => FootwearFamily.formalShoes,
              _ => null,
            }
          : null;
      return StylistSwapRequest(
        slot: slot,
        bottomFamily: bottomFamily,
        shoeFamily: shoeFamily,
      );
    }
    return StylistSwapRequest.parse(userText);
  }

  bool _brainRequiresUpperLayer(Map<String, dynamic> response) {
    final directive = _brainOutfitDirective(response);
    return const {
      'required_upper_layer',
      'optional_upper_layer',
    }.contains(_brainDirectiveValue(directive, 'extraLayer', 'none'));
  }

  String _brainRequiredUpperLayerFamily(Map<String, dynamic> response) {
    final directive = _brainOutfitDirective(response);
    return _brainDirectiveValue(directive, 'layerFamily', 'none');
  }

  bool _brainPreservesCurrentOutfitForLayer(Map<String, dynamic> response) {
    final directive = _brainOutfitDirective(response);
    if (directive == null || !_brainRequiresUpperLayer(response)) return false;
    // Structural invariant: adding a requested layer to a visible full outfit
    // is additive even if the model forgot the boolean flag.
    return _brainDirectiveValue(directive, 'scope', 'none') == 'full_outfit' &&
        _conversationAlreadyHasOutfitCards();
  }

  String _brainPresentationMode(Map<String, dynamic> response) {
    final directive = _brainOutfitDirective(response);
    final value = _brainDirectiveValue(directive, 'presentation', 'normal');
    return const {'normal', 'focused_item', 'concise_full'}.contains(value)
        ? value
        : 'normal';
  }

  Future<void> _handleAssistantResponse({
    required String userText,
    required Map<String, dynamic> response,
    required List<Map<String, String>> history,
    required Map<String, dynamic> weatherContext,
    required Map<String, dynamic> clientContext,
  }) async {
    final action = StylistUdrClientRoutingV1.normalizeContextAction(
      response['action'],
    );
    if (response['clearShoppingContext'] == true) {
      _shoppingState = const StylistShoppingSessionState();
    }
    if (response['ok'] != true && action != 'generate_outfit') {
      setState(() {
        _messages.add(
          StylistChatMessage(
            text: response['offline'] == true
                ? 'Vyzerá to, že nie si pripojený na internet 📶 Skontroluj '
                      'pripojenie a skús to znova.'
                : 'Ups, momentálne sa neviem pripojiť 😅 Skús to ešte raz prosím.',
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
      return;
    }

    if (_isShoppingAction(action)) {
      _handleShoppingResponse(response);
      return;
    }

    _mergeOutfitContextFromResponse(response);

    final editRouting = StylistOutfitEditRoutingV1.resolve(
      response: response,
      userText: userText,
      legacyResolver: _legacySwapRequestForTurn,
    );
    final canonicalPlan = editRouting.canonicalPlan;
    var effectiveAction = action;
    if (editRouting.canonicalPlanInvalid) {
      effectiveAction = 'chat';
      response['reply'] =
          'Tejto úprave som nerozumel dosť presne, takže aktuálny outfit nemením.';
      debugPrint('STYLIST CHAT canonical_edit_plan_invalid fail_closed=true');
    } else if (canonicalPlan?.intent == OutfitEditIntentV1.none &&
        effectiveAction == 'generate_outfit') {
      effectiveAction = 'chat';
      debugPrint('STYLIST CHAT canonical_edit_plan_non_mutating=true');
    }
    if (effectiveAction == 'generate_outfit' &&
        !_conversationAlreadyHasOutfitCards() &&
        StylistConversationSignals.isContextOnlyPlanStatement(userText)) {
      // A declared plan is context only. Grounding becoming sufficient does
      // not mean the user asked us to style them. This client invariant is a
      // safety net even if a conversational model over-eagerly requests D/R.
      effectiveAction = 'chat';
      response['reply'] = 'Jasné 🙂';
      debugPrint('STYLIST CHAT generation_suppressed reason=context_only_plan');
    }
    var requestedImpactFields = response['impactFields'] is List
        ? (response['impactFields'] as List)
              .map((value) => value.toString().trim().toLowerCase())
              .where((value) => value.isNotEmpty)
              .toSet()
        : <String>{};
    // No model phrasing can authorize a frozen candidate request while a
    // deterministic material event fact remains unknown.
    if (_outfitContextState.groundingStatus == 'needs_grounding' &&
        effectiveAction != 'stop') {
      effectiveAction = 'clarify';
      requestedImpactFields = {
        ...requestedImpactFields,
        ..._outfitContextState.unresolvedMaterialFields,
      };
      response['impactFields'] = requestedImpactFields.toList(growable: false);
      // GPT-4o still owns the semantic context decision, while deterministic
      // grounding owns the exact unresolved material delta. Render that delta
      // directly so an otherwise good model reply cannot re-ask a resolved
      // field (or add a low-impact time question) before the destination and
      // activity are actually grounded.
      final brainReply = (response['reply'] ?? '').toString().trim();
      final brainAlreadyClarified =
          action == 'clarify' && brainReply.isNotEmpty;
      if (!brainAlreadyClarified) {
        response['reply'] = _groundingClarificationText(
          _outfitContextState.unresolvedMaterialFields,
          correction: _outfitContextState.userCorrectionDetected,
        );
      }
      debugPrint(
        'STYLIST CHAT grounding_blocked_generation '
        'fields=${_outfitContextState.unresolvedMaterialFields}',
      );
    }
    if (_outfitContextState.groundingStatus == 'sufficient' &&
        _outfitContextState.userCorrectionDetected &&
        _conversationAlreadyHasOutfitCards() &&
        (!editRouting.canonicalPlanPresent ||
            canonicalPlan?.intent != OutfitEditIntentV1.none) &&
        effectiveAction != 'stop') {
      effectiveAction = 'generate_outfit';
      debugPrint('STYLIST CHAT material_correction_refresh=true');
    }
    if (effectiveAction == 'generate_outfit' &&
        OutfitContextState.isMultiDayPackingRequest(_conversationHintText())) {
      // Packing spans several situations and must not be collapsed into one
      // frozen outfit. GPT-4o can give scoped packing advice; D/R remains the
      // authority only when the user actually asks for one outfit.
      effectiveAction = 'chat';
      debugPrint('STYLIST CHAT multi_day_packing_kept_conversational=true');
    }
    final alreadyAsked = _outfitContextState.clarifiedMaterialFields
        .map((value) => value.trim().toLowerCase())
        .toSet();
    if (_outfitContextState.groundingStatus != 'needs_grounding' &&
        effectiveAction == 'clarify' &&
        (requestedImpactFields.isEmpty ||
            requestedImpactFields.every(alreadyAsked.contains))) {
      // A malformed/repeated clarification may be unhelpful, but it must not
      // silently turn into an ungrounded outfit decision.
      effectiveAction = 'chat';
      debugPrint('STYLIST CHAT repeated_or_empty_clarification_blocked');
    }
    if (_outfitContextState.groundingStatus != 'needs_grounding' &&
        canonicalPlan?.intent == OutfitEditIntentV1.createOutfit &&
        effectiveAction != 'stop') {
      effectiveAction = 'generate_outfit';
    }

    if (effectiveAction == 'clarify') {
      final reply = (response['reply'] ?? '').toString();
      debugPrint('STYLIST UDR clarification_source=gpt4o');
      debugPrint(
        'STYLIST CHAT outfit_decision action=clarify '
        'confidence=${response['confidence']} '
        'decisionRisk=${response['decisionRisk']} '
        'impactFields=${response['impactFields']}',
      );
      setState(() {
        _outfitContextState = _outfitContextState.withClarificationAsked(
          requestedImpactFields,
        );
        _messages.add(
          StylistChatMessage(
            text: _sanitizeStylistReplyForDisplay(reply),
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
      return;
    }

    if (effectiveAction == 'stop') {
      final reply = (response['reply'] ?? '').toString().trim();
      setState(() {
        _messages.add(
          StylistChatMessage(
            text: reply.isNotEmpty
                ? reply
                : 'Tento outfit teraz nechcem navrhovať bez bezpečného '
                      'podkladu.',
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
      return;
    }

    if (canonicalPlan?.intent == OutfitEditIntentV1.editCurrentOutfit) {
      if (!_conversationAlreadyHasOutfitCards()) {
        setState(() {
          _messages.add(
            const StylistChatMessage(
              text:
                  'Nemám tu aktuálny outfit, ktorý by som mohol bezpečne upraviť.',
              isUser: false,
            ),
          );
          _isSending = false;
        });
        _scrollToBottom();
        return;
      }
      if (_lastOutfitItemIds.isEmpty) {
        final restored = _resolvedCurrentOutfitItems();
        final restoredIds = restored
            .map((item) => (item['id'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        if (restoredIds.isNotEmpty) {
          _currentOutfitItems = restored;
          _lastOutfitItemIds = restoredIds;
        }
      }
      await _runHybridOutfitGeneration(
        userText: userText,
        history: history,
        weatherContext: weatherContext,
        clientContext: clientContext,
        event: _eventFromConversation(
          rawEvent: response['eventContext'] as Map<String, dynamic>?,
          fallbackLocation: UserLocationService.instance.cityLabel,
        ),
        outfitEditPlan: canonicalPlan,
        presentationMode: canonicalPlan!.presentation,
      );
      return;
    }

    // Legacy compatibility only: old responses without a canonical Brain plan
    // may still request the historical one-slot edit.
    // keď už outfit visí a používateľ chce vymeniť KTORÝKOĽVEK kus (vrch / spodok
    // / obuv / vrstvu), preskladáme HNEĎ len ten kus — bez ohľadu na to, či model
    // vrátil 'chat' alebo 'generate_outfit', a bez zbytočného prehadzovania celého
    // outfitu. Inak by „zmen mi tričko“ spadlo do generate_outfit a zmenilo všetko.
    final swapRequest = editRouting.legacySwap;
    if (_conversationAlreadyHasOutfitCards() && swapRequest != null) {
      // A reopened chat may have outfit cards while the ephemeral ID cache is
      // empty. Rebuild the authoritative current outfit before a one-slot swap.
      if (_lastOutfitItemIds.isEmpty) {
        final restored = _resolvedCurrentOutfitItems();
        final restoredIds = restored
            .map((item) => (item['id'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        if (restoredIds.isNotEmpty) {
          _currentOutfitItems = restored;
          _lastOutfitItemIds = restoredIds;
        }
      }
      final event = _eventFromConversation(
        rawEvent: response['eventContext'] as Map<String, dynamic>?,
        fallbackLocation: UserLocationService.instance.cityLabel,
      );
      if (_shouldUseLegacyClarifyGates(response) &&
          _askForCityIfMissing(event)) {
        return;
      }
      debugPrint(
        'STYLIST CHAT auto_generate_outfit reason=explicit_swap '
        'slot=${swapRequest.slot.name} '
        'bottom=${swapRequest.bottomFamily?.name ?? "-"} '
        'shoes=${swapRequest.shoeFamily?.name ?? "-"} '
        'thermal=${swapRequest.thermalPreference?.name ?? "-"}',
      );
      await _runHybridOutfitGeneration(
        userText: userText,
        history: history,
        weatherContext: weatherContext,
        clientContext: clientContext,
        event: event,
        forceDifferent: true,
        // Explicit single-slot requests keep every other displayed item
        // frozen. A requested family (e.g. jeans -> shorts) only widens which
        // lower-body candidates may replace the current bottom.
        requestedSwap: swapRequest,
        // Pri spodku s konkrétnou rodinou necháme swap rešpektovať voľbu.
        requestedBottomFamily: swapRequest.slot == StylistSwapSlot.bottom
            ? swapRequest.bottomFamily
            : null,
        optionalUpperLayerRequested: false,
        presentationMode: _brainPresentationMode(response),
      );
      return;
    }

    if (effectiveAction == 'generate_outfit') {
      // AI-first: EventClarification ostáva ako poistka pri nízkej confidence.
      final event = _eventFromConversation(
        rawEvent: response['eventContext'] as Map<String, dynamic>?,
        fallbackLocation: UserLocationService.instance.cityLabel,
      );
      if (_shouldUseLegacyClarifyGates(response) &&
          _askForCityIfMissing(event)) {
        return;
      }
      if (_shouldUseLegacyClarifyGates(response) &&
          _askForTimeIfMissing(event)) {
        return;
      }
      await _runHybridOutfitGeneration(
        userText: userText,
        history: history,
        weatherContext: weatherContext,
        clientContext: clientContext,
        event: event,
        outfitEditPlan: canonicalPlan,
        excludeKeywords: response['excludeItemKeywords'] is List
            ? (response['excludeItemKeywords'] as List)
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList(growable: false)
            : const <String>[],
        forceDifferent: editRouting.canonicalPlanPresent
            ? false
            : _shouldForceDifferentOutfit(userText),
        requestedBottomFamily: editRouting.canonicalPlanPresent
            ? null
            : _resolveRequestedBottomFamily(userText),
        optionalUpperLayerRequested: editRouting.canonicalPlanPresent
            ? false
            : _brainRequiresUpperLayer(response),
        preserveCurrentOutfit: editRouting.canonicalPlanPresent
            ? false
            : _brainPreservesCurrentOutfitForLayer(response),
        requiredUpperLayerFamily: editRouting.canonicalPlanPresent
            ? ''
            : _brainRequiredUpperLayerFamily(response),
        presentationMode:
            canonicalPlan?.presentation ?? _brainPresentationMode(response),
      );
      return;
    }

    if (!editRouting.canonicalPlanPresent &&
        action == 'chat' &&
        _conversationAlreadyHasOutfitCards() &&
        _userQuestionsRestaurantFormality(userText)) {
      await _runHybridOutfitGeneration(
        userText: userText,
        history: history,
        weatherContext: weatherContext,
        clientContext: clientContext,
        event: _eventFromConversation(
          rawEvent: response['eventContext'] as Map<String, dynamic>?,
          fallbackLocation: UserLocationService.instance.cityLabel,
        ),
        excludeKeywords: const ['šortky', 'sortky', 'shorts'],
        forceDifferent: true,
      );
      return;
    }

    if (!editRouting.canonicalPlanPresent &&
        action == 'chat' &&
        StylistConversationSignals.userExplicitlyWantsOutfitShown(userText) &&
        !_conversationAlreadyHasOutfitCards()) {
      final event = _eventFromConversation(
        rawEvent: response['eventContext'] as Map<String, dynamic>?,
        fallbackLocation: UserLocationService.instance.cityLabel,
      );
      if (_shouldUseLegacyClarifyGates(response) &&
          _askForCityIfMissing(event)) {
        return;
      }
      if (_shouldUseLegacyClarifyGates(response) &&
          _askForTimeIfMissing(event)) {
        return;
      }
      if (StylistDestinationParser.hasOutfitGenerationContext(
        conversationText: _conversationHintText(),
        hourLocal:
            event.hourLocal ??
            _resolveOutfitHourFromConversation(_conversationHintText()),
        inferredDestination: StylistDestinationParser.inferFromConversation(
          _conversationHintText(),
        ),
        gpsCityLabel: UserLocationService.instance.cityLabel,
      )) {
        debugPrint(
          'STYLIST CHAT auto_generate_outfit reason=explicit_show_outfit',
        );
        await _runHybridOutfitGeneration(
          userText: userText,
          history: history,
          weatherContext: weatherContext,
          clientContext: clientContext,
          event: event,
          excludeKeywords: response['excludeItemKeywords'] is List
              ? (response['excludeItemKeywords'] as List)
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList(growable: false)
              : const <String>[],
          forceDifferent: _shouldForceDifferentOutfit(userText),
          requestedBottomFamily: _resolveRequestedBottomFamily(userText),
          optionalUpperLayerRequested: _brainRequiresUpperLayer(response),
          presentationMode: _brainPresentationMode(response),
        );
        return;
      }
    }

    if (!editRouting.canonicalPlanPresent &&
        action == 'chat' &&
        _shouldAutoGenerateOutfitAfterChat()) {
      debugPrint(
        'STYLIST CHAT auto_generate_outfit reason=full_context_action_was_chat',
      );
      final event = _eventFromConversation(
        rawEvent: response['eventContext'] as Map<String, dynamic>?,
        fallbackLocation: UserLocationService.instance.cityLabel,
      );
      if (_shouldUseLegacyClarifyGates(response) &&
          _askForCityIfMissing(event)) {
        return;
      }
      if (_shouldUseLegacyClarifyGates(response) &&
          _askForTimeIfMissing(event)) {
        return;
      }
      await _runHybridOutfitGeneration(
        userText: userText,
        history: history,
        weatherContext: weatherContext,
        clientContext: clientContext,
        event: event,
        excludeKeywords: response['excludeItemKeywords'] is List
            ? (response['excludeItemKeywords'] as List)
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList(growable: false)
            : const <String>[],
        forceDifferent: _shouldForceDifferentOutfit(userText),
        requestedBottomFamily: _resolveRequestedBottomFamily(userText),
        optionalUpperLayerRequested: _brainRequiresUpperLayer(response),
        preserveCurrentOutfit: _brainPreservesCurrentOutfitForLayer(response),
        requiredUpperLayerFamily: _brainRequiredUpperLayerFamily(response),
        presentationMode: _brainPresentationMode(response),
      );
      return;
    }

    if (action == 'chat' && _userAsksAboutWeather(userText)) {
      final localWeatherReply = await _buildLocalWeatherChatReply();
      if (localWeatherReply != null) {
        debugPrint('STYLIST CHAT reply_source=local_weather_tip');
        setState(() {
          _messages.add(
            StylistChatMessage(
              text: _sanitizeStylistReplyForDisplay(localWeatherReply),
              isUser: false,
            ),
          );
          _isSending = false;
        });
        _scrollToBottom();
        return;
      }
    }

    final reply = (response['reply'] ?? '').toString();
    final suggestedItemsRaw = response['suggestedItems'];
    var suggestedItems = _sortStylistSuggestedItems(
      suggestedItemsRaw is List
          ? suggestedItemsRaw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .take(6)
                .toList(growable: false)
          : const <Map<String, dynamic>>[],
    );
    if (_shouldSuppressRepeatedOutfitCards(userText)) {
      suggestedItems = const <Map<String, dynamic>>[];
    }
    if (suggestedItems.isNotEmpty) {
      _lastOutfitItemIds = suggestedItems
          .map((e) => (e['id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();
    }
    debugPrint(
      'STYLIST CHAT suggestedItems=${suggestedItems.length} '
      'ids=${suggestedItems.map((e) => e['id']).join(",")}',
    );
    setState(() {
      _messages.add(
        StylistChatMessage(
          text: _sanitizeStylistReplyForDisplay(reply),
          isUser: false,
          suggestedItems: suggestedItems,
        ),
      );
      _isSending = false;
    });
    _scrollToBottom();
  }

  bool _isShoppingAction(String action) {
    return const <String>{
      'SHOPPING_CLARIFY_SOURCE',
      'ASK_PERMISSION_TO_SHOP',
      'START_SHOPPING_SEARCH',
      'REFINE_SHOPPING_SEARCH',
      'SHOW_MORE_SHOPPING',
      'SHOW_ALL_SHOPPING',
      'FOCUS_SHOPPING_PRODUCT',
      'OFFER_WISHLIST',
      'WISHLIST_EDITOR',
      'RETURN_TO_WARDROBE_STYLIST',
      'ASK_SHOPPING_MAX_PRICE',
      'SHOPPING_CLARIFY_STYLE',
      'UNSUPPORTED_STRUCTURED_CONSTRAINT',
    }.contains(action);
  }

  void _handleShoppingResponse(Map<String, dynamic> response) {
    final patch = response['shoppingContextPatch'];
    final rawAttachments = response['messageAttachments'];
    final attachments = rawAttachments is List
        ? rawAttachments
              .whereType<Map>()
              .map((item) {
                try {
                  return StylistShoppingAttachment.fromMap(
                    Map<String, dynamic>.from(item),
                  );
                } on FormatException {
                  return null;
                }
              })
              .whereType<StylistShoppingAttachment>()
              .toList(growable: false)
        : const <StylistShoppingAttachment>[];
    setState(() {
      if (response['clearShoppingContext'] == true) {
        _shoppingState = const StylistShoppingSessionState();
      } else if (patch is Map) {
        _shoppingState = _shoppingState.applyPatch(
          Map<String, dynamic>.from(patch),
        );
      }
      _messages.add(
        StylistChatMessage(
          text: _sanitizeStylistReplyForDisplay(
            (response['reply'] ?? '').toString(),
          ),
          isUser: false,
          attachments: attachments,
        ),
      );
      _isSending = false;
    });
    _scrollToBottom();
  }

  Future<void> _sendShoppingAction(String text) async {
    if (_isSending || !ShoppingUiFeatureFlags.mayExposeCatalog) return;
    _controller.text = text;
    await _sendMessage();
  }

  List<ShoppingCandidateData> _shoppingCandidates() {
    return _shoppingState.presentedCandidates
        .map(ShoppingCandidateData.fromServer)
        .where((candidate) => candidate.variantId.isNotEmpty)
        .toList(growable: false);
  }

  void _openShoppingResults({bool isComplete = false, int? exactResultCount}) {
    final candidates = _shoppingCandidates();
    if (candidates.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShoppingResultsScreen(
          candidates: candidates,
          isComplete: isComplete,
          exactResultCount: exactResultCount,
          onCandidate: _openShoppingCandidateDetail,
          onWishlist: _openWishlistEditor,
        ),
      ),
    );
  }

  Future<void> _openShoppingCandidateDetail(
    ShoppingCandidateData candidate,
  ) async {
    var current = candidate;
    final sessionId = _shoppingState.sessionId;
    if (sessionId != null) {
      try {
        final detail = await _shoppingDetailsService.get(
          sessionId: sessionId,
          variantId: candidate.variantId,
        );
        current = candidate.withDetail(detail);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aktuálne údaje sa nepodarilo obnoviť.'),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1B1F),
      builder: (_) => ShoppingCandidateDetailSheet(
        candidate: current,
        onVisitStore: _visitShoppingOffer,
        onWishlist: () {
          Navigator.of(context).pop();
          _openWishlistEditor(current);
        },
      ),
    );
  }

  Future<void> _visitShoppingOffer(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') return;
    if (ShoppingUiFeatureFlags.fixtureMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixture odkaz bol bezpečne zachytený.')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openWishlistEditor(ShoppingCandidateData candidate) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1B1F),
      builder: (_) => ShoppingWishlistEditor(
        candidate: candidate,
        onSave: (intent) async {
          await _shoppingWishlistService.save(intent);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Uložené vo Wishliste.')),
          );
        },
        onDismissed: () => Navigator.of(context).pop(),
      ),
    );
  }

  Future<void> _ensureRecentOutfitHistory() async {
    if (_recentOutfitHistoryLoaded) return;
    try {
      _recentOutfitItemIdSets = await _chatStore
          .loadRecentFullOutfitItemIdSets();
    } catch (_) {
      _recentOutfitItemIdSets = const <Set<String>>[];
    } finally {
      _recentOutfitHistoryLoaded = true;
    }
  }

  void _rememberRecentOutfit(Set<String> ids) {
    if (ids.length < 3) return;
    final next = <Set<String>>[Set<String>.unmodifiable(ids)];
    for (final prior in _recentOutfitItemIdSets) {
      if (prior.length == ids.length && prior.containsAll(ids)) continue;
      next.add(prior);
      if (next.length >= 5) break;
    }
    _recentOutfitItemIdSets = List<Set<String>>.unmodifiable(next);
  }

  Future<void> _runHybridOutfitGeneration({
    required String userText,
    required List<Map<String, String>> history,
    required Map<String, dynamic> weatherContext,
    required Map<String, dynamic> clientContext,
    required StylistChatEventContext event,
    List<String> excludeKeywords = const [],
    bool forceDifferent = false,
    BottomFamily? requestedBottomFamily,
    StylistSwapRequest? requestedSwap,
    OutfitEditPlanV1? outfitEditPlan,
    bool optionalUpperLayerRequested = false,
    bool preserveCurrentOutfit = false,
    String requiredUpperLayerFamily = '',
    String presentationMode = 'normal',
  }) async {
    // Semantic clarification has already been decided by the GPT-4o context
    // callable. Do not re-run the legacy conversation gate here.
    if (!_useAiClarifyFlow &&
        _blockIfConversationNeedsClarification(sourceText: userText)) {
      return;
    }
    if (requestedSwap == null &&
        outfitEditPlan?.intent != OutfitEditIntentV1.editCurrentOutfit &&
        !preserveCurrentOutfit) {
      await _ensureRecentOutfitHistory();
    }
    _setSendingProgress(StylistChatProgressPhase.analyzingWardrobe);
    StylistChatOutfitResult? outfitResult;
    List<String> rejectAllReasons = const <String>[];
    String rejectAllExplanation = '';
    try {
      outfitResult = await _stylistChatOutfitService.generateForEvent(
        event: event,
        excludeItemKeywords: excludeKeywords,
        previousOutfitItemIds: _lastOutfitItemIds,
        forceDifferentOutfit: forceDifferent,
        conversationHint: _conversationHintText(),
        groundedActivityType: _outfitContextState.activityHint,
        requestedBottomFamily: requestedBottomFamily,
        requestedSwap: requestedSwap,
        outfitEditPlan: outfitEditPlan,
        optionalUpperLayerRequested: optionalUpperLayerRequested,
        preserveCurrentOutfit: preserveCurrentOutfit,
        requiredUpperLayerFamily: requiredUpperLayerFamily == 'none'
            ? ''
            : requiredUpperLayerFamily,
        recentOutfitItemIdSets: _recentOutfitItemIdSets,
        presentationMode: presentationMode,
        userRequest: userText,
        onProgress: _setSendingProgress,
      );
    } on StylistFrozenDecisionRejectedExceptionV1 catch (error) {
      rejectAllReasons = error.reasonCodes;
      rejectAllExplanation = error.explanation;
    }
    if (!mounted) return;

    debugPrint('STYLIST UDR decision_source=frozen_candidate_authority');
    _resetClarifyRound();

    if (outfitResult == null) {
      final rejectAll = rejectAllReasons.isNotEmpty;
      setState(() {
        _messages.add(
          StylistChatMessage(
            text: rejectAll
                ? (rejectAllExplanation.isNotEmpty
                      ? rejectAllExplanation
                      : 'Z dostupných možností ti teraz nechcem nasilu potvrdiť outfit, ktorý by neprešiel podmienkami.')
                : 'V šatníku nemám dosť kusov na celý outfit. Skús pridať viac oblečenia.',
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
      return;
    }

    final wardrobeAnalysis = outfitResult.wardrobeAnalysis;
    _currentOutfitUsedCompromise = wardrobeAnalysis.usedCompromise;
    _currentOutfitDecisionRationale = (outfitResult.finalExplanation ?? '')
        .trim();

    final previousIds = _lastOutfitItemIds;
    final suggestedItems = _sortStylistSuggestedItems(
      await _stylistChatOutfitService.suggestedItemsFromFlexibleOutfit(
        outfitResult.flexibleOutfit,
      ),
    );
    final nextIds = suggestedItems
        .map((e) => (e['id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    if (preserveCurrentOutfit && previousIds.isNotEmpty) {
      final added = nextIds.difference(previousIds);
      final removed = previousIds.difference(nextIds);
      if (removed.isNotEmpty || added.length != 1) {
        debugPrint(
          'STYLIST CHAT additive_layer_rejected reason=non_additive_delta '
          'added=$added removed=$removed',
        );
        setState(() {
          _messages.add(
            const StylistChatMessage(
              text:
                  'Vrstva sa mi nepodarila pridať bez zmeny zvyšku outfitu, takže pôvodný outfit nechávam tak.',
              isUser: false,
            ),
          );
          _isSending = false;
        });
        _scrollToBottom();
        return;
      }
    }

    if (requestedSwap != null && previousIds.isNotEmpty) {
      final added = nextIds.difference(previousIds);
      final removed = previousIds.difference(nextIds);
      final strictSingleSlotDelta =
          nextIds.length == previousIds.length &&
          added.length == 1 &&
          removed.length == 1;
      if (!strictSingleSlotDelta) {
        debugPrint(
          'STYLIST CHAT explicit_swap_rejected reason=multi_item_delta '
          'added=$added removed=$removed',
        );
        setState(() {
          _messages.add(
            const StylistChatMessage(
              text:
                  'Túto výmenu nechcem spraviť tak, že ti potichu zmením aj ďalšie kúsky. Skúsim radšej inú náhradu len za ten jeden kus.',
              isUser: false,
            ),
          );
          _isSending = false;
        });
        _scrollToBottom();
        return;
      }
    }

    _lastOutfitItemIds = nextIds;
    if (requestedSwap == null &&
        outfitEditPlan?.intent != OutfitEditIntentV1.editCurrentOutfit) {
      _rememberRecentOutfit(nextIds);
    }
    _currentOutfitItems = List<Map<String, dynamic>>.unmodifiable(
      suggestedItems.map((item) => Map<String, dynamic>.from(item)),
    );

    final canonicalDelta = outfitResult.outfitEditDelta;
    if (outfitEditPlan?.intent == OutfitEditIntentV1.editCurrentOutfit &&
        canonicalDelta?.actualFocusSlot != null) {
      final focusedItems = suggestedItems
          .where(
            (item) => canonicalDelta!.changedAfterItemIds.contains(
              (item['id'] ?? '').toString().trim(),
            ),
          )
          .toList(growable: false);
      if (focusedItems.isEmpty) {
        setState(() {
          _messages.add(
            const StylistChatMessage(
              text:
                  'Zmenený kus sa mi nepodarilo jednoznačne zobraziť, preto si výsledok nechcem domýšľať.',
              isUser: false,
            ),
          );
          _isSending = false;
        });
        _scrollToBottom();
        return;
      }
      debugPrint(
        'STYLIST CHAT reply_source=canonical_outfit_delta '
        'slot=${canonicalDelta!.actualFocusSlot} '
        'display_items=${focusedItems.length}',
      );
      setState(() {
        _messages.add(
          StylistChatMessage(
            text: canonicalDelta.followUpTextSk,
            isUser: false,
            suggestedItems: focusedItems,
            outfitUpdateSlot: canonicalDelta.actualFocusSlot,
          ),
        );
        _isSending = false;
      });
      _scrollToBottom();
      return;
    }

    // An explicit one-slot request is a true local edit: every other item stays
    // frozen internally, and the UI shows only the item the user asked about.
    if (requestedSwap != null) {
      final swapSlot = requestedSwap.slot;
      const slotOrderFor = <StylistSwapSlot, int>{
        StylistSwapSlot.top: 0,
        StylistSwapSlot.outerwear: 1,
        StylistSwapSlot.bottom: 2,
        StylistSwapSlot.shoes: 3,
      };
      final swapDisplayItems = suggestedItems
          .where(
            (item) => _stylistWearSlotOrder(item) == slotOrderFor[swapSlot],
          )
          .toList(growable: false);
      final brainReply = StylistUdrClientRoutingV1.frozenExplanationForDisplay(
        outfitResult.finalExplanation,
      );
      final fallbackReply = _shortSwapReply(
        suggestedItems: suggestedItems,
        slot: swapSlot,
      );
      // A one-slot reply must name the item that was ACTUALLY changed.
      // The frozen explanation describes the whole candidate and can mention a
      // different slot, so deterministic changed-item copy has display priority.
      final focusedReply = fallbackReply ?? brainReply;
      if (focusedReply != null && swapDisplayItems.isNotEmpty) {
        debugPrint(
          'STYLIST CHAT reply_source='
          '${fallbackReply != null ? 'local_swap_fallback' : 'brain_locked_swap'} '
          'slot=${swapSlot.name} display_items=${swapDisplayItems.length}',
        );
        setState(() {
          _messages.add(
            StylistChatMessage(
              text: focusedReply,
              isUser: false,
              suggestedItems: swapDisplayItems,
              outfitUpdateSlot: swapSlot.name,
            ),
          );
          _isSending = false;
        });
        _scrollToBottom();
        return;
      }
    }

    final displayReply = StylistUdrClientRoutingV1.frozenExplanationForDisplay(
      outfitResult.finalExplanation,
    );
    final hasFrozenExplanation = displayReply != null;
    debugPrint(
      'STYLIST UDR explanation_source='
      '${hasFrozenExplanation ? 'frozen_authority' : 'unavailable'}',
    );
    debugPrint('STYLIST UDR legacy_fallback_invoked=false');
    debugPrint(
      'STYLIST CHAT hybrid outfit ids='
      '${suggestedItems.map((e) => e['id']).join(",")}',
    );
    setState(() {
      _messages.add(
        StylistChatMessage(
          text:
              displayReply ??
              'Outfit už mám vybraný, no vysvetlenie sa mi teraz nepodarilo '
                  'načítať. Nechcem si k nemu nič domýšľať — skús mi ho '
                  'prosím poslať ešte raz.',
          isUser: false,
          suggestedItems: suggestedItems,
        ),
      );
      _isSending = false;
    });
    _scrollToBottom();
    await _offerShoppingForWardrobeGap(wardrobeAnalysis);
  }

  Future<void> _offerShoppingForWardrobeGap(
    WardrobeAnalysis wardrobeAnalysis,
  ) async {
    if (wardrobeAnalysis.missingItems.isEmpty || _shoppingState.isActive) {
      return;
    }
    final gap = wardrobeAnalysis.missingItems.first;
    final result = await _stylistChatService.sendMessage(
      'wardrobe_gap_permission',
      shoppingWardrobeSignal: <String, dynamic>{
        'gapDetected': true,
        'suitableOwnedItemExists': false,
        'bestOwnedCompromiseExists': wardrobeAnalysis.usedCompromise,
        'canonicalType': gap.category,
        'needLabel': gap.explanationSk.isNotEmpty
            ? gap.explanationSk
            : gap.category,
      },
    );
    if (!mounted || !_isShoppingAction((result['action'] ?? '').toString())) {
      return;
    }
    _handleShoppingResponse(result);
  }

  /// Zistí, či navrhnutý outfit reálne obsahuje vrchnú vrstvu (bunda/kabát/sako…).
  /// Slot 1 v `_stylistWearSlotOrder` zodpovedá vrchnej vrstve.
  bool _outfitContainsOuterwear(List<Map<String, dynamic>> suggestedItems) {
    return suggestedItems.any((item) => _stylistWearSlotOrder(item) == 1);
  }

  /// Krátka, vecná odpoveď pri výmene JEDNÉHO kusu (vrch / spodok / obuv /
  /// vrstva) — nie copy-paste celého outfitu. Pomenuje zmenený kus a že ladí so
  /// zvyškom. Vráti null, ak nevieme určiť kúsky (vtedy ide bežný AI opis).
  String? _shortSwapReply({
    required List<Map<String, dynamic>> suggestedItems,
    required StylistSwapSlot slot,
  }) {
    const slotOrderFor = <StylistSwapSlot, int>{
      StylistSwapSlot.top: 0,
      StylistSwapSlot.outerwear: 1,
      StylistSwapSlot.bottom: 2,
      StylistSwapSlot.shoes: 3,
    };
    final changed = suggestedItems
        .where((item) => _stylistWearSlotOrder(item) == slotOrderFor[slot])
        .firstOrNull;
    if (changed == null) return null;
    final changedName = (changed['name'] ?? '').toString().trim();
    if (changedName.isEmpty) return null;
    final changedPhrase = SlovakOutfitInstrumental.accusative(changedName);
    return 'Zvolil by som $changedPhrase — z dostupných možností mi k '
        'tomuto outfitu dáva najväčší zmysel.';
  }

  /// Krátke vysvetlenie, keď sa kvôli zladeniu muselo zmeniť viac kúskov, nielen
  /// ten vyžiadaný. Pomenuje vyžiadaný kus a otvorene povie, že kvôli ladeniu
  /// prehodil aj ďalšie — bez copy-paste celého opisu.
  String? _multiChangeSwapReply({
    required List<Map<String, dynamic>> suggestedItems,
    required StylistSwapSlot slot,
  }) {
    String nameForSlot(int slotOrder) {
      for (final item in suggestedItems) {
        if (_stylistWearSlotOrder(item) == slotOrder) {
          return (item['name'] ?? '').toString().trim();
        }
      }
      return '';
    }

    const slotOrderFor = {
      StylistSwapSlot.top: 0,
      StylistSwapSlot.outerwear: 1,
      StylistSwapSlot.bottom: 2,
      StylistSwapSlot.shoes: 3,
    };
    final requestedName = nameForSlot(slotOrderFor[slot]!);
    if (requestedName.isEmpty) return null;
    // „dal som ti …“ aj „prehodil som aj …“ sú akuzatív.
    final requestedPhrase = SlovakOutfitInstrumental.accusative(requestedName);

    final others = <String>[];
    for (final entry in slotOrderFor.entries) {
      if (entry.key == slot) continue;
      final n = nameForSlot(entry.value);
      if (n.isNotEmpty) others.add(SlovakOutfitInstrumental.accusative(n));
    }

    final buffer = StringBuffer('Dal som ti $requestedPhrase');
    if (others.isNotEmpty) {
      buffer.write(
        ' — a aby to spolu ladilo, prehodil som k tomu aj '
        '${SlovakOutfitInstrumental.joinWithA(others)}.',
      );
    } else {
      buffer.write('.');
    }
    return buffer.toString();
  }

  String _conversationHintText() {
    return _messages
        .where((message) => message.isUser)
        .map((message) => message.text.trim())
        .where((text) => text.isNotEmpty)
        .join(' ');
  }

  void _mergeOutfitContextFromResponse(Map<String, dynamic> response) {
    final confidenceRaw = response['confidence'] ?? response['readiness'];
    final impactRaw = response['impactFields'] ?? response['missingFields'];
    final assumptionsRaw = response['assumptions'];
    final assumptions = assumptionsRaw is List
        ? assumptionsRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];
    final impact = impactRaw is List
        ? impactRaw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];
    final parsedConfidence = confidenceRaw is num
        ? confidenceRaw.toDouble()
        : null;
    _outfitContextState = _outfitContextState.mergeFromAiResponse(
      eventContext: response['eventContext'] as Map<String, dynamic>?,
      confidence: parsedConfidence,
      decisionRisk: response['decisionRisk']?.toString(),
      assumptions: assumptions,
      clarifyReason: response['clarifyReason']?.toString(),
      impactFields: impact,
    );
  }

  /// Poistka: EventClarification ostáva, ale pri AI clarify flow ho používame
  /// len keď AI ešte nemá dostatočnú istotu (confidence).
  bool _shouldUseLegacyClarifyGates(Map<String, dynamic> response) {
    // U/D/R routes every semantic clarification through GPT-4o. Local
    // city/time gates remain only for the disabled compatibility flow.
    return !_useAiClarifyFlow;
  }

  void _resetClarifyRound() {
    _outfitContextState = _outfitContextState.withClarifyRoundUsed(false);
  }

  /// [ConversationReasoner] — pred weather/AI/outfit: máme všetko potrebné?
  bool _blockIfConversationNeedsClarification({
    required String sourceText,
    bool blockWeatherAndAi = false,
  }) {
    final conversation = _conversationHintText();
    final decision = ConversationReasoner.evaluate(
      conversation: conversation,
      latestMessage: sourceText,
      gpsCityLabel: UserLocationService.instance.cityLabel,
      excludeDestinations: _unresolvableDestinations,
    );
    if (!decision.shouldBlockPipeline) return false;

    final sanitizedSource = sourceText.replaceAll('\n', ' ').trim();
    debugPrint(
      'STYLIST CHAT conversation_gate_blocked { '
      'action=${decision.action.label}, '
      'missing=${decision.missingInformation.label}, '
      'reason=${decision.reason}, sourceText="$sanitizedSource" }',
    );
    if (blockWeatherAndAi) {
      debugPrint(
        'STYLIST CHAT weather_skipped reason=conversation_needs_clarification',
      );
      debugPrint(
        'STYLIST CHAT ai_skipped reason=conversation_needs_clarification',
      );
    }
    debugPrint(
      'STYLIST CHAT outfit_generation_skipped reason=conversation_needs_clarification',
    );
    final askText =
        decision.clarificationQuestionSk ??
        'Potrebujem ešte pár detailov — napíš mi prosím viac.';
    setState(() {
      _messages.add(StylistChatMessage(text: askText, isUser: false));
      _isSending = false;
    });
    _scrollToBottom();
    return true;
  }

  /// Pýtame sa na mesto len keď nemáme GPS ani explicitné mesto z konverzácie.
  bool _askForCityIfMissing(StylistChatEventContext event) {
    final conversation = _conversationHintText();
    final gpsCity = UserLocationService.instance.cityLabel;
    final inferred = StylistDestinationParser.inferFromConversation(
      conversation,
      exclude: _unresolvableDestinations,
    );
    final needsCity = StylistDestinationParser.needsDestinationForOutfit(
      conversationText: conversation,
      inferredDestination: inferred,
      gpsCityLabel: gpsCity,
    );
    debugPrint(
      'STYLIST CHAT city_gate needsCity=$needsCity inferred=$inferred '
      'eventLoc=${event.locationLabel}',
    );
    if (!needsCity) return false;

    // Ak posledná správa vyzerá ako preklep mesta, spýtame sa cielene
    // („Nemyslíš Mníchov?“) namiesto generického „v ktorom meste“.
    final lastMsg = _latestUserMessageText();
    final suggestion = StylistCitySuggester.suggestCorrection(lastMsg);
    final askText = suggestion != null
        ? 'Mesto „$lastMsg“ akosi nenachádzam 🤔 Nemyslíš náhodou $suggestion? '
              'Napíš mi to a zložím outfit.'
        : 'V ktorom meste to je?';

    setState(() {
      _messages.add(StylistChatMessage(text: askText, isUser: false));
      _isSending = false;
    });
    _scrollToBottom();
    return true;
  }

  /// Bez času nevieme zložiť outfit — spýtame sa krátko, bez vysvetľovania.
  bool _askForTimeIfMissing(StylistChatEventContext event) {
    final conversation = _conversationHintText();
    if (_userSpecifiedOutfitHour(conversation)) return false;
    if (!StylistDestinationParser.userWantsOutfitFromWardrobe(conversation) &&
        !StylistDestinationParser.userWantsOutfitFromWardrobe(
          _latestUserMessageText(),
        )) {
      return false;
    }
    final askText = EventClarification.missingMessage(
      conversation,
      gpsCityLabel: UserLocationService.instance.cityLabel,
    );
    if (askText == null) return false;
    final lower = askText.toLowerCase();
    if (!lower.contains('koľkej') &&
        !lower.contains('kolk') &&
        !lower.contains('dokedy')) {
      return false;
    }
    debugPrint(
      'STYLIST CHAT time_gate needsTime=true '
      'userHourSpecified=false aiHour=${event.hourLocal}',
    );
    setState(() {
      _messages.add(StylistChatMessage(text: askText, isUser: false));
      _isSending = false;
    });
    _scrollToBottom();
    return true;
  }

  bool _shouldClarifyBeforeApiCall(String latestText) {
    final decision = ConversationReasoner.evaluate(
      conversation: _conversationHintText(),
      latestMessage: latestText,
      gpsCityLabel: UserLocationService.instance.cityLabel,
      excludeDestinations: _unresolvableDestinations,
    );
    return decision.shouldBlockPipeline;
  }

  /// Posledná správa od používateľa (na cielené fuzzy návrhy mesta).
  String _latestUserMessageText() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        final t = _messages[i].text.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return '';
  }

  StylistChatEventContext _eventFromConversation({
    Map<String, dynamic>? rawEvent,
    required String fallbackLocation,
  }) {
    final conversation = _conversationHintText();
    final inferred = _outfitContextState.groundingStatus == 'sufficient'
        ? _outfitContextState.activityLocationLabel
        : null;
    final base = StylistChatEventContext.fromDynamic(
      rawEvent,
      now: DateTime.now(),
    );
    var location = '';
    if (inferred != null &&
        StylistDestinationParser.isPlausibleDestination(inferred)) {
      location = inferred;
    }
    if (location.isEmpty) {
      location = base.locationLabel.trim();
      if (location.isNotEmpty &&
          !StylistDestinationParser.isPlausibleDestination(location)) {
        location = '';
      }
    }
    final mayUseGpsAsEventLocation =
        !_outfitContextState.remoteActivityPlanned ||
        _outfitContextState.routineLocalOutfit;
    if (location.isEmpty && mayUseGpsAsEventLocation) {
      location = fallbackLocation.split(',').first.trim();
    }

    var date = base.date;
    final tripParsed = StylistTripParser.parseFromConversation(conversation);
    // Explicitný dátum z user-grounded state má prednosť pred starým
    // modelovým eventContextom. Oprava "nie zajtra, v sobotu" musí zrušiť
    // starú predpoveď, aj keď GPT vráti predchádzajúci dateKey.
    final stateDate = DateTime.tryParse(_outfitContextState.dateKey ?? '');
    final explicitDate =
        stateDate ?? StylistDayParser.resolveDate(conversation);
    if (explicitDate != null) {
      date = explicitDate;
    }

    final hour = _resolveEventHour(
      conversation: conversation,
      aiHourLocal: base.hourLocal,
      tripParsed: tripParsed,
    );
    final mergedTrip = base.tripWindow
        .merge(tripParsed)
        .merge(
          StylistTripWindow(
            eventStartHour: hour,
            tripStartHour: tripParsed.tripStartHour,
            tripEndHour: tripParsed.tripEndHour,
            tripEndEstimated: tripParsed.tripEndEstimated,
          ),
        );
    final profile = StylistOccasionGuidance.profileFor(
      occasion: base.occasion,
      conversationText: conversation,
    );
    return StylistChatEventContext(
      date: date,
      hourLocal: hour,
      locationLabel: location,
      occasion:
          base.occasion ?? (profile.label.isNotEmpty ? profile.label : null),
      performer: base.performer,
      dressCode: base.dressCode,
      tripWindow: mergedTrip,
    );
  }

  String _groundingClarificationText(
    Iterable<String> fields, {
    required bool correction,
  }) {
    final normalized = fields
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    final prefix = correction ? 'Máš pravdu, to som si nemal domýšľať. ' : '';
    if (normalized.contains('destination') && normalized.contains('activity')) {
      return '${prefix}Kam sa chystáš a čo tam budeš približne robiť?';
    }
    if (normalized.contains('activity') && normalized.contains('date')) {
      final weekend = RegExp(
        r'\b(?:víkend|vikend|weekend)\b',
        caseSensitive: false,
      ).hasMatch(_conversationHintText());
      return weekend
          ? '${prefix}Čo budeš po príchode približne robiť a na ktorý deň cez víkend outfit riešime? Počasie sa môže medzi dňami zmeniť.'
          : '${prefix}Čo budeš počas pobytu približne robiť a kedy cestuješ?';
    }
    if (normalized.contains('destination')) {
      final activity = _outfitContextState.activityHint;
      if (activity == 'city_walk') {
        final country = RegExp(
          r'\b(?:usa|spojen(?:e|é)\s+štáty|united\s+states)\b',
          caseSensitive: false,
        ).hasMatch(_conversationHintText());
        return country
            ? '${prefix}Prechádzku po meste mám. Ktoré mesto v USA? Počasie sa tam môže dosť líšiť.'
            : '${prefix}Prechádzku po meste mám. Ešte kam sa chystáš? Podľa miesta vyberiem správne počasie.';
      }
      return '${prefix}Kam sa chystáš? Podľa miesta vyberiem vhodné počasie aj outfit.';
    }
    if (normalized.contains('trip_scope') && !normalized.contains('activity')) {
      return '${prefix}Chceš jeden konkrétny outfit, alebo plán, čo si zbaliť na celý pobyt?';
    }
    if (normalized.contains('activity')) {
      if (_outfitContextState.activityHint == 'travel') {
        return '${prefix}Cestu mám. Čo budeš po príchode približne robiť? To rozhodne, či má byť outfit hlavne pohodlný, alebo aj upravenejší.';
      }
      if (RegExp(
        r'\b(?:\d+|jeden|jedna|dva|dve|tri|štyri|styri|päť|pat)\s+dni?\b',
        caseSensitive: false,
      ).hasMatch(_conversationHintText())) {
        return '${prefix}Čo máš počas pobytu v pláne? Na celodenné chodenie po meste a na lepšiu večeru sa balí trochu inak.';
      }
      return '${prefix}Čo tam budeš približne robiť?';
    }
    if (normalized.contains('date')) {
      return '${prefix}Kedy cestuješ? Podľa termínu overím správne počasie.';
    }
    return '${prefix}Aby som vybral vhodný outfit, potrebujem ešte trochu upresniť plán.';
  }

  bool _shouldAutoGenerateOutfitAfterChat() {
    if (_useAiClarifyFlow) return false;
    if (_conversationAlreadyHasOutfitCards()) return false;
    final conversation = _conversationHintText();
    if (!StylistDestinationParser.userWantsOutfitFromWardrobe(conversation)) {
      return false;
    }
    if (StylistOccasionGuidance.needsActivityClarification(conversation)) {
      return false;
    }
    if (EventClarification.needsMoreContext(
      conversation,
      gpsCityLabel: UserLocationService.instance.cityLabel,
    )) {
      return false;
    }
    final inferred = StylistDestinationParser.inferFromConversation(
      conversation,
    );
    if (StylistDestinationParser.needsDestinationForOutfit(
      conversationText: conversation,
      inferredDestination: inferred,
      gpsCityLabel: UserLocationService.instance.cityLabel,
    )) {
      return false;
    }
    return StylistDestinationParser.hasOutfitGenerationContext(
      conversationText: conversation,
      hourLocal: _resolveOutfitHourFromConversation(conversation),
      inferredDestination: inferred,
      gpsCityLabel: UserLocationService.instance.cityLabel,
    );
  }

  int? _resolveOutfitHourFromConversation(String conversation) {
    return _resolveEventHour(
      conversation: conversation,
      aiHourLocal: null,
      tripParsed: StylistTripParser.parseFromConversation(conversation),
    );
  }

  /// Hodinu berieme len ak ju user povedal — AI nesmie domýšľať „ráno pri zajtra“.
  int? _resolveEventHour({
    required String conversation,
    required int? aiHourLocal,
    required StylistTripWindow tripParsed,
  }) {
    final fromUserText =
        tripParsed.eventStartHour ?? _extractHourFromConversation(conversation);
    if (_userSpecifiedOutfitHour(conversation)) {
      return aiHourLocal ??
          fromUserText ??
          (_conversationSaysNow(conversation) ? DateTime.now().hour : null);
    }
    return fromUserText ??
        (_conversationSaysNow(conversation) ? DateTime.now().hour : null);
  }

  bool _userSpecifiedOutfitHour(String conversation) {
    return _extractHourFromConversation(conversation) != null ||
        _conversationSaysNow(conversation);
  }

  bool _conversationSaysTomorrow(String conversation) {
    final blob = conversation.toLowerCase();
    return blob.contains('zajtra') || blob.contains('tomorrow');
  }

  bool _conversationSaysNow(String conversation) {
    final blob = conversation.toLowerCase();
    return blob.contains('teraz') ||
        blob.contains('hned') ||
        blob.contains('ihned');
  }

  int? _extractHourFromConversation(String conversation) {
    final match = RegExp(
      r'(?:o|okolo)\s*(\d{1,2})(?::\d{2})?',
      caseSensitive: false,
    ).firstMatch(conversation.toLowerCase());
    if (match == null) return null;
    final hour = int.tryParse(match.group(1) ?? '');
    if (hour == null || hour < 0 || hour > 23) return null;
    return hour;
  }

  bool _returnTimeKnown(StylistTripWindow window) {
    return window.eventEndHour != null ||
        (window.tripEndHour != null && !window.tripEndEstimated);
  }

  Future<({OutfitWeatherDaySnapshot snapshot, Map<String, dynamic> context})>
  _weatherContextForOutfitExplain(StylistChatEventContext event) async {
    final city = event.locationLabel.trim().isNotEmpty
        ? event.locationLabel
        : UserLocationService.instance.cityLabel;
    final snap = await _hourlyWeatherService.getWeatherForCityAndDate(
      city: city,
      date: event.date,
    );
    _lastResolvedEventTempC =
        snap.noonTempC ?? snap.maxTempC ?? snap.eveningTempC;
    debugPrint(
      'STYLIST CHAT outfit weather city=$city date=${snap.date.toIso8601String().split('T').first} '
      'rain=${snap.willRain} fromApi=${snap.fromOpenMeteo}',
    );
    final context = _snapshotToWeatherContext(snap);
    context['cityName'] = city;
    final trip = TripWeatherAnalyzer.analyze(
      day: snap,
      window: event.effectiveTripWindow,
      timeKnown: event.effectiveTripWindow.hasExplicitTime,
    );
    context.addAll(trip.toWeatherContextPayload());
    final now = DateTime.now();
    final conversation = _conversationHintText();
    final terrain = StylistActivityTerrainClassifier.classify(
      conversationText: conversation,
      occasion: event.occasion,
    );
    final returnKnown = _returnTimeKnown(event.effectiveTripWindow);
    final isTomorrow = _conversationSaysTomorrow(conversation);
    final occasionProfile = StylistOccasionGuidance.profileFor(
      occasion: event.occasion,
      conversationText: conversation,
    );
    context['nowHourLocal'] = now.hour;
    context['nowMinuteLocal'] = now.minute;
    context['hourLocal'] = event.hourLocal;
    context['hourAssumedDefault'] =
        event.hourLocal != null && !_userSpecifiedOutfitHour(conversation);
    context['tripMinTempC'] = trip.minTempC;
    context['tripMaxTempC'] = trip.maxTempC;
    final rawOutfitTempC = event.hourLocal != null
        ? (TripWeatherAnalyzer.tempAtHour(snap, event.hourLocal!) ??
              trip.outfitTempC)
        : trip.outfitTempC;
    final outfitTempC = StylistWeatherAdjustment.adjustActivityTempC(
      rawTempC: rawOutfitTempC,
      terrain: terrain,
      hourLocal: event.hourLocal,
    );
    context['outfitTempC'] = outfitTempC;
    context['rawOutfitTempC'] = rawOutfitTempC;
    context['weatherSource'] = 'open_meteo';
    if (event.hourLocal != null) {
      debugPrint(
        'STYLIST CHAT outfit hour=${event.hourLocal} '
        'rawTempC=$rawOutfitTempC outfitTempC=$outfitTempC '
        'terrain=${terrain.name} morningBlock=${snap.morningTempC}',
      );
    }
    context['activityTerrain'] = terrain == StylistActivityTerrain.wetGround
        ? 'wetGround'
        : 'urban';
    context['returnTimeKnown'] = returnKnown;
    final declinedRain = _userDeclinedRainAdvice();
    context['userDeclinedRainAdvice'] = declinedRain;
    context['rainAdviceSk'] = declinedRain
        ? null
        : StylistWeatherTipBuilder.rainAdviceForNow(
            snapshot: snap,
            now: now,
            eventHour: event.hourLocal,
            terrain: terrain,
            returnTimeKnown: returnKnown,
          );
    final contextLine = StylistWeatherTipBuilder.outfitContextLine(
      snapshot: snap,
      eventHour: event.hourLocal,
      locationLabel: event.locationLabel,
      isTomorrow: isTomorrow,
      isSmartCasual: occasionProfile.isSmartCasual,
      smartCasualPhrase: occasionProfile.smartCasualPhrase,
      now: now,
      terrain: terrain,
    );
    final tips = StylistWeatherTipBuilder.outfitAddon(
      snapshot: snap,
      eventHour: event.hourLocal,
      now: now,
      terrain: terrain,
      returnTimeKnown: returnKnown,
    );
    if (contextLine != null) {
      context['weatherSummaryForStylist'] = contextLine;
    }
    if (tips != null && tips.isNotEmpty) {
      context['stylistWeatherTips'] = tips;
    }
    if (trip.advisorySk.isNotEmpty && !declinedRain) {
      context['tripWeatherAdvisory'] = trip.advisorySk;
    }
    final chatSummary = StylistWeatherTipBuilder.naturalDaySummarySk(
      snapshot: snap,
      locationLabel: city,
      isTomorrow: isTomorrow,
      eventHour: event.hourLocal,
      terrain: terrain,
      includeRain: !declinedRain,
    );
    if (chatSummary != null) {
      context['weatherChatSummarySk'] = chatSummary;
    }
    return (snapshot: snap, context: context);
  }

  Future<String?> _buildLocalWeatherChatReply() async {
    final event = _eventFromConversation(
      rawEvent: null,
      fallbackLocation: UserLocationService.instance.cityLabel,
    );
    final city = event.locationLabel.trim();
    if (city.isEmpty) return null;
    final snap = await _hourlyWeatherService.getWeatherForCityAndDate(
      city: city,
      date: event.date,
    );
    return StylistWeatherTipBuilder.temperatureChatReply(
      snapshot: snap,
      eventHour: event.hourLocal,
      locationLabel: city,
      conversationText: _conversationHintText(),
      returnTimeKnown: _returnTimeKnown(event.effectiveTripWindow),
    );
  }

  bool _userAsksAboutWeather(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('stupň') ||
        lower.contains('stupn') ||
        lower.contains('teplot')) {
      return true;
    }
    if ((lower.contains('koľko') || lower.contains('kolko')) &&
        (lower.contains('stup') ||
            lower.contains('teplo') ||
            lower.contains('bude'))) {
      return true;
    }
    if (lower.contains('bude prša') ||
        lower.contains('bude prsa') ||
        lower.contains('bude dáž') ||
        lower.contains('bude daz')) {
      return true;
    }
    // Generic questions such as „aké hlásia počasie?“ must use the same
    // Open-Meteo snapshot as the rest of the app instead of free-form model
    // prose, otherwise a daily maximum can be mistaken for the current temp.
    if (lower.contains('počas') ||
        lower.contains('pocas') ||
        lower.contains('predpove') ||
        lower.contains('hlásia') ||
        lower.contains('hlasia') ||
        lower.contains('weather')) {
      return true;
    }
    return false;
  }

  bool _userQuestionsRestaurantFormality(String text) {
    final lower = text.toLowerCase();
    final restaurant =
        lower.contains('reštaur') ||
        lower.contains('restaur') ||
        lower.contains('večer') ||
        lower.contains('vecer');
    final questionsFit =
        lower.contains('vhodn') ||
        lower.contains('skôr') ||
        lower.contains('skor') ||
        lower.contains('rifle') ||
        lower.contains('nohavice') ||
        lower.contains('elegant') ||
        lower.contains('nemal by som') ||
        lower.contains('nemala by som');
    return restaurant && questionsFit;
  }

  String _seasonKeyFromDate(DateTime date) {
    final m = date.month;
    if (m >= 3 && m <= 5) return 'jar';
    if (m >= 6 && m <= 8) return 'let';
    if (m >= 9 && m <= 11) return 'jese';
    return 'zim';
  }

  String _resolveHybridExplainReply({
    required Map<String, dynamic> explainResponse,
    required List<Map<String, dynamic>> suggestedItems,
    required StylistChatEventContext event,
    required Map<String, dynamic> weatherContext,
    OutfitWeatherDaySnapshot? weatherSnapshot,
    WardrobeAnalysis? wardrobeAnalysis,
    StylistOccasionProfile? occasionProfile,
    StylistOpinion? stylistOpinion,
    bool weatherIsRainy = false,
    bool wetGroundMuddy = false,
    int? tempC,
  }) {
    final profile =
        occasionProfile ??
        StylistOccasionGuidance.profileFor(
          occasion: event.occasion,
          conversationText: _conversationHintText(),
        );
    final explainOk = explainResponse['ok'] == true;
    final reply = (explainResponse['reply'] ?? '').toString().trim();
    final aiUsable =
        explainOk &&
        reply.isNotEmpty &&
        !_isGenericStylistErrorReply(reply) &&
        !StylistOutfitExplainBuilder.shouldUseLocalExplain(
          aiReply: reply,
          profile: profile,
          wardrobeAnalysis: wardrobeAnalysis,
          stylistOpinion: stylistOpinion,
        );
    if (aiUsable) {
      debugPrint('STYLIST CHAT reply_source=ai_explain');
      return reply;
    }
    if (explainOk != true) {
      debugPrint(
        'STYLIST CHAT reply_source=local_fallback reason=callable_failed',
      );
    } else if (reply.isEmpty || _isGenericStylistErrorReply(reply)) {
      debugPrint(
        'STYLIST CHAT reply_source=local_fallback reason=empty_or_generic_reply',
      );
    } else {
      debugPrint(
        'STYLIST CHAT reply_source=local_fallback reason=unsafe_or_technical_reply',
      );
    }
    return _localOutfitExplainReply(
      suggestedItems: suggestedItems,
      event: event,
      weatherSnapshot: weatherSnapshot,
      weatherContext: weatherContext,
      wardrobeAnalysis: wardrobeAnalysis,
      occasionProfile: profile,
      stylistOpinion: stylistOpinion,
      weatherIsRainy: weatherIsRainy,
      wetGroundMuddy: wetGroundMuddy,
      tempC: tempC,
    );
  }

  bool _isGenericStylistErrorReply(String reply) {
    final normalized = reply.toLowerCase();
    return normalized.contains('niečo sa pokazilo') ||
        normalized.contains('nieco sa pokazilo');
  }

  String _localOutfitExplainReply({
    required List<Map<String, dynamic>> suggestedItems,
    required StylistChatEventContext event,
    OutfitWeatherDaySnapshot? weatherSnapshot,
    Map<String, dynamic>? weatherContext,
    WardrobeAnalysis? wardrobeAnalysis,
    StylistOccasionProfile? occasionProfile,
    StylistOpinion? stylistOpinion,
    bool weatherIsRainy = false,
    bool wetGroundMuddy = false,
    int? tempC,
  }) {
    final profile =
        occasionProfile ??
        StylistOccasionGuidance.profileFor(
          occasion: event.occasion,
          conversationText: _conversationHintText(),
        );

    String? weatherLine;
    if (weatherSnapshot != null &&
        (weatherSnapshot.fromOpenMeteo ||
            weatherContext?['fromOpenMeteo'] == true)) {
      final terrain = StylistActivityTerrainClassifier.classify(
        conversationText: _conversationHintText(),
        occasion: event.occasion,
      );
      weatherLine = StylistWeatherTipBuilder.outfitContextLine(
        snapshot: weatherSnapshot,
        eventHour: event.hourLocal,
        locationLabel: event.locationLabel.trim(),
        isTomorrow: _conversationSaysTomorrow(_conversationHintText()),
        isSmartCasual: profile.isSmartCasual,
        smartCasualPhrase: profile.smartCasualPhrase,
        now: DateTime.now(),
        terrain: terrain,
      );
    }

    return StylistOutfitExplainBuilder.buildLocalExplainSk(
      suggestedItems: suggestedItems,
      profile: profile,
      wardrobeAnalysis: wardrobeAnalysis,
      weatherLine: weatherLine,
      activityType: StylistIntentResolver.resolve(
        conversationText: _conversationHintText(),
      ).activityType,
      stylistOpinion: stylistOpinion,
      weatherIsRainy: weatherIsRainy,
      wetGroundMuddy: wetGroundMuddy,
      tempC: tempC,
      conversationText: _conversationHintText(),
    );
  }

  // Historical local clarification path retained for rollback comparison.
  // ignore: unused_element
  bool _shouldRespondWithLocalClarification() {
    final conversation = _conversationHintText();
    final gpsCity = UserLocationService.instance.cityLabel;
    if (!StylistDestinationParser.userWantsOutfitFromWardrobe(conversation) &&
        !EventClarification.needsMoreContext(
          conversation,
          gpsCityLabel: gpsCity,
        )) {
      return false;
    }
    if (StylistOccasionGuidance.needsActivityClarification(conversation)) {
      return true;
    }
    return EventClarification.missingMessage(
          conversation,
          gpsCityLabel: gpsCity,
        ) !=
        null;
  }

  String _localClarificationBeforeOutfit() {
    final decision = ConversationReasoner.evaluate(
      conversation: _conversationHintText(),
      gpsCityLabel: UserLocationService.instance.cityLabel,
      excludeDestinations: _unresolvableDestinations,
    );
    if (decision.clarificationQuestionSk != null) {
      return decision.clarificationQuestionSk!;
    }
    final gps = UserLocationService.instance.cityShortLabel;
    final styleHint = StylistDestinationParser.occasionStyleHint(
      _conversationHintText(),
    );
    return StylistDestinationParser.clarificationPrompt(
      gpsCityShort: gps,
      styleHint: styleHint,
    );
  }

  bool _replyIsBadGenericOutfitAdvice(String reply) {
    final lower = reply.toLowerCase();
    final conversation = _conversationHintText();
    final profile = StylistOccasionGuidance.profileFor(
      conversationText: conversation,
      tempC: _lastResolvedEventTempC,
    );
    if (profile.excludeShorts &&
        (lower.contains('šortk') ||
            lower.contains('shortk') ||
            lower.contains('kratas'))) {
      return true;
    }
    return lower.contains('aké je divadlo') ||
        lower.contains('ake je divadlo') ||
        lower.contains('aké divadlo') ||
        lower.contains('ake divadlo') ||
        lower.contains('a či v ') ||
        lower.contains('a ci v ') ||
        (lower.contains('môžeš zvážiť') &&
            !lower.contains('šatník') &&
            !lower.contains('satnik'));
  }

  bool _replyAsksUserForWeather(String reply) {
    final lower = reply.toLowerCase();
    return (lower.contains('aké je počasie') ||
            lower.contains('ake je pocasie') ||
            lower.contains('aké bude počasie') ||
            lower.contains('ake bude pocasie') ||
            lower.contains('aké tam bude') ||
            lower.contains('ake tam bude')) &&
        lower.contains('?');
  }

  bool _shouldForceDifferentOutfit(String text) {
    final lower = text.toLowerCase();
    const patterns = <String>[
      'iné',
      'ine',
      'zmeň',
      'zmen',
      'daj niečo',
      'daj nieco',
      'niečo iné',
      'nieco ine',
    ];
    return patterns.any(lower.contains);
  }

  /// Zistí, akú rodinu spodku si používateľ pýta. Najprv pozrie aktuálnu
  /// správu; ak v nej nič nie je (napr. medzitým odpovedal „to je jedno“ na
  /// otázku AI), prehľadá posledné správy používateľa, aby sa požiadavka
  /// (napr. „radšej kraťasy“) nestratila počas spresňujúceho kola.
  BottomFamily? _resolveRequestedBottomFamily(String userText) {
    final direct = StylistBottomRequest.parse(userText);
    if (direct != null) return direct;
    final userMessages = _messages
        .where((message) => message.isUser)
        .map((message) => message.text)
        .toList(growable: false);
    for (final text in userMessages.reversed.take(4)) {
      final parsed = StylistBottomRequest.parse(text);
      if (parsed != null) return parsed;
    }
    return null;
  }

  List<Map<String, dynamic>> _resolvedCurrentOutfitItems() {
    if (_currentOutfitItems.isNotEmpty) {
      return _currentOutfitItems
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }

    var current = <Map<String, dynamic>>[];
    for (final message in _messages) {
      if (message.isUser) continue;
      if (message.resultingOutfitItems.isNotEmpty) {
        current = message.resultingOutfitItems
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: true);
        continue;
      }
      if (message.suggestedItems.isEmpty) continue;
      final incoming = _sortStylistSuggestedItems(
        message.suggestedItems
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false),
      );
      if (incoming.length >= 2) {
        current = incoming;
        continue;
      }
      if (current.isEmpty || incoming.length != 1) continue;
      final lower = message.text.toLowerCase();
      final looksLikePartialSwap =
          (message.outfitUpdateSlot?.isNotEmpty ?? false) ||
          lower.contains('vymenil som') ||
          lower.contains('prehodil som') ||
          lower.contains('dal som ti');
      if (!looksLikePartialSwap) continue;
      final replacement = incoming.single;
      final slot = _stylistWearSlotOrder(replacement);
      final index = current.indexWhere(
        (item) => _stylistWearSlotOrder(item) == slot,
      );
      if (index >= 0) {
        current[index] = replacement;
      } else {
        current.add(replacement);
      }
      current = _sortStylistSuggestedItems(current);
    }
    return current;
  }

  List<Map<String, String>> _currentDisplayedOutfitContext() {
    String valueFor(Map<String, dynamic> item, List<String> keys) {
      for (final key in keys) {
        final raw = item[key];
        if (raw == null) continue;
        if (raw is List) {
          final value = raw
              .map((part) => part.toString().trim())
              .where((part) => part.isNotEmpty)
              .take(3)
              .join(', ');
          if (value.isNotEmpty) return value;
          continue;
        }
        if (raw is Map) {
          for (final nestedKey in const ['family', 'name', 'label']) {
            final nested = raw[nestedKey]?.toString().trim() ?? '';
            if (nested.isNotEmpty) return nested;
          }
          continue;
        }
        final value = raw.toString().trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final current = _resolvedCurrentOutfitItems();
    if (current.isNotEmpty) {
      return current
          .take(6)
          .map((item) {
            final name = valueFor(item, const [
              'name',
              'displayName',
              'title',
              'canonicalType',
              'type',
            ]);
            final type = valueFor(item, const [
              'canonicalType',
              'type',
              'subType',
              'category',
            ]);
            final color = valueFor(item, const [
              'primaryColor',
              'color',
              'colorName',
              'colors',
            ]);
            return <String, String>{
              if (name.isNotEmpty) 'name': name,
              if (type.isNotEmpty) 'type': type,
              if (color.isNotEmpty) 'color': color,
            };
          })
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <Map<String, String>>[];
  }

  Map<String, dynamic> _buildClientContext({String? cityName}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    String dateKey(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final locationLabel = UserLocationService.instance.cityLabel.trim();
    final eventDestination = StylistDestinationParser.inferFromConversation(
      _conversationHintText(),
    );
    final lat = UserLocationService.instance.latitude;
    final lon = UserLocationService.instance.longitude;
    final currentOutfit = _currentDisplayedOutfitContext();
    return <String, dynamic>{
      'now': now.toIso8601String(),
      'todayDateKey': dateKey(today),
      'tomorrowDateKey': dateKey(tomorrow),
      'timezoneOffsetMinutes': now.timeZoneOffset.inMinutes,
      'weatherFromApp': true,
      if (locationLabel.isNotEmpty) ...{
        'userGpsLocation': locationLabel,
        'defaultWeatherCity': locationLabel.split(',').first.trim(),
      },
      if (eventDestination != null && eventDestination.isNotEmpty)
        'eventDestination': eventDestination,
      if (currentOutfit.isNotEmpty) ...{
        'currentOutfit': currentOutfit,
        'currentOutfitDecision': <String, dynamic>{
          'recommendedByStylist': true,
          'usedCompromise': _currentOutfitUsedCompromise,
          if (_currentOutfitDecisionRationale.isNotEmpty)
            'rationale': _currentOutfitDecisionRationale,
        },
      },
      if (lat != null) 'latitude': lat,
      if (lon != null) 'longitude': lon,
    };
  }

  int _stylistWearSlotOrder(Map<String, dynamic> item) {
    final blob = [
      item['name'],
      item['category'],
      item['subCategory'],
      item['mainGroup'],
    ].whereType<String>().join(' ').toLowerCase();
    bool has(List<String> needles) =>
        needles.any((needle) => blob.contains(needle));
    if (has([
      'topán',
      'topan',
      'tenis',
      'sneaker',
      'obuv',
      'shoes',
      'čiž',
      'ciz',
    ])) {
      return 3;
    }
    if (has(['nohav', 'rifl', 'jeans', 'šort', 'short', 'sukn', 'skirt'])) {
      return 2;
    }
    if (has([
      'bunda',
      'kabát',
      'kabat',
      'sako',
      'blazer',
      'vetrovka',
      'parka',
    ])) {
      return 1;
    }
    if (has([
      'trič',
      'trick',
      'tielko',
      't-shirt',
      'koše',
      'blúz',
      'top',
      'sveter',
      'mikina',
      'hoodie',
    ])) {
      return 0;
    }
    return 9;
  }

  List<Map<String, dynamic>> _sortStylistSuggestedItems(
    List<Map<String, dynamic>> items,
  ) {
    final sorted = List<Map<String, dynamic>>.from(items);
    sorted.sort(
      (a, b) => _stylistWearSlotOrder(a).compareTo(_stylistWearSlotOrder(b)),
    );
    return sorted;
  }

  bool _conversationAlreadyHasOutfitCards() {
    return _messages.any(
      (message) => !message.isUser && message.suggestedItems.isNotEmpty,
    );
  }

  bool _requestsNewOutfitOrShow(String text) {
    final lower = text.toLowerCase();
    const patterns = <String>[
      'ukáž',
      'ukaz',
      'zobraz',
      'ukážeš',
      'ukazes',
      'obliecť',
      'obliect',
      'outfit',
      'kombináci',
      'kombinaci',
      'nechcem',
      'radšej',
      'radsej',
      'zmeň',
      'zmen',
      'daj mi',
      'navrhni',
      'čo si mám',
      'co si mam',
      'porad mi čo',
      'porad mi co',
    ];
    return patterns.any(lower.contains);
  }

  bool _shouldSuppressRepeatedOutfitCards(String userMessage) {
    if (!_conversationAlreadyHasOutfitCards()) return false;
    if (_requestsNewOutfitOrShow(userMessage)) return false;
    return true;
  }

  bool _messageNeedsWardrobeContext(String text) =>
      stylistMessageNeedsWardrobeContext(text);

  Map<String, dynamic> _lightweightWeatherSlice(
    Map<String, dynamic> full,
    String dayLabel,
  ) {
    return <String, dynamic>{
      'cityName': full['cityName'],
      'date': full['date'],
      'dayLabel': dayLabel,
      'noonTempC': full['noonTempC'],
      'eveningTempC': full['eveningTempC'],
      'willRain': full['willRain'] ?? false,
      'isWindy': full['isWindy'] ?? false,
      'fromOpenMeteo': full['fromOpenMeteo'] ?? false,
      'summaryText': full['summaryText'],
      if (full['weatherChatSummarySk'] != null)
        'weatherChatSummarySk': full['weatherChatSummarySk'],
      'userDeclinedRainAdvice': full['userDeclinedRainAdvice'] == true,
      if (full['activityTerrain'] != null)
        'activityTerrain': full['activityTerrain'],
      if (full['wetGroundRisk'] != null) 'wetGroundRisk': full['wetGroundRisk'],
      if (full['rainBeforeEvent'] != null)
        'rainBeforeEvent': full['rainBeforeEvent'],
      if (full['rainTimeText'] != null) 'rainTimeText': full['rainTimeText'],
    };
  }

  Future<Map<String, dynamic>> _resolveWeatherContextForRequest({
    required bool lightweight,
    bool allowGpsEventFallback = true,
  }) async {
    final conversation = _conversationHintText();
    // Resolve an event destination only from the authoritative grounding
    // state. A correction can quote an assistant's invented city ("Martin"),
    // so reparsing the complete text here would turn the quote into weather
    // evidence before the user has supplied an actual destination.
    final dest = _outfitContextState.groundingStatus == 'sufficient'
        ? _outfitContextState.activityLocationLabel
        : null;
    final date = _eventDateFromConversation(conversation);
    final dayLabel = _dayLabelForDate(date);
    if (dest != null && StylistDestinationParser.isPlausibleDestination(dest)) {
      final snap = await _hourlyWeatherService.getWeatherForCityAndDate(
        city: dest,
        date: date,
      );
      _lastResolvedEventTempC =
          snap.noonTempC ?? snap.maxTempC ?? snap.eveningTempC;
      debugPrint(
        'STYLIST CHAT weather event city=$dest date=${snap.date.toIso8601String().split('T').first} '
        'rain=${snap.willRain} fromApi=${snap.fromOpenMeteo}',
      );
      final base = _snapshotToWeatherContext(snap);
      // Vždy prezentuj počasie pod menom cieľovej obce, nech to znie ako jej
      // vlastné počasie (nie „približné z iného mesta“).
      base['cityName'] = dest;
      final full = _enrichWeatherWithTrip(base, snap, conversation);
      full['dayLabel'] = dayLabel;
      if (!lightweight) return full;
      return _lightweightWeatherSlice(full, dayLabel);
    }
    if (!allowGpsEventFallback) {
      return <String, dynamic>{
        'dayLabel': dayLabel,
        'eventWeatherStatus': 'deferred_pending_grounding',
        'weatherDeferredForGrounding': true,
        'fromOpenMeteo': false,
      };
    }
    // Bez konkrétneho mesta berieme GPS polohu. Ak používateľ spomenul iný deň
    // (napr. „idem zajtra“), stiahneme počasie pre TEN deň, nie len dnešné
    // cache — inak by appka radila podľa zlej teploty.
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (!isToday) {
      final city = UserLocationService.instance.cityShortLabel;
      final snap = await _hourlyWeatherService.getWeatherForCityAndDate(
        city: city,
        date: date,
      );
      _lastResolvedEventTempC =
          snap.noonTempC ?? snap.maxTempC ?? snap.eveningTempC;
      debugPrint(
        'STYLIST CHAT weather gps city=$city day=$dayLabel '
        'date=${snap.date.toIso8601String().split('T').first} '
        'rain=${snap.willRain} fromApi=${snap.fromOpenMeteo}',
      );
      final base = _snapshotToWeatherContext(snap);
      final full = _enrichWeatherWithTrip(base, snap, conversation);
      full['dayLabel'] = dayLabel;
      if (!lightweight) return full;
      return _lightweightWeatherSlice(full, dayLabel);
    }
    if (!lightweight) {
      await _ensureWeatherContext();
      final ctx = _weatherContextForApi(lightweight: false);
      ctx['dayLabel'] = dayLabel;
      return ctx;
    }
    if (_cachedWeatherContext != null) {
      final ctx = _weatherContextForApi(lightweight: true);
      ctx['dayLabel'] = dayLabel;
      return ctx;
    }
    return <String, dynamic>{
      'cityName': UserLocationService.instance.cityShortLabel,
      'dayLabel': dayLabel,
      'willRain': false,
      'fromOpenMeteo': false,
    };
  }

  /// Vráti ľudský názov dňa pre teplotný riadok ("dnes"/"zajtra"/dátum).
  String _dayLabelForDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    if (diff <= 0) return 'dnes';
    if (diff == 1) return 'zajtra';
    if (diff == 2) return 'pozajtra';
    if (diff >= 3 && diff <= 6) {
      final phrase = StylistDayParser.inDayPhrase(target);
      if (phrase != null) return phrase;
    }
    final dd = target.day.toString().padLeft(2, '0');
    final mm = target.month.toString().padLeft(2, '0');
    return '$dd.$mm.';
  }

  /// Ak používateľ zadá miesto, ktoré geokóder nevie nájsť (ulica, osada,
  /// preklep), NEPREDSTIERAME počasie z iného mesta — appka sa úprimne spýta na
  /// najbližšie väčšie mesto. Vráti správu na zobrazenie, alebo null ak je
  /// všetko v poriadku (miesto sa našlo / je to GPS poloha / nič sa nepýta).
  // Historical geocoder clarification path retained for rollback comparison.
  // ignore: unused_element
  Future<String?> _destinationWeatherClarification() async {
    final conversation = _conversationHintText();
    final wantsOuting =
        StylistDestinationParser.userWantsOutfitFromWardrobe(conversation) ||
        EventClarification.needsMoreContext(
          conversation,
          gpsCityLabel: UserLocationService.instance.cityLabel,
        );
    if (!wantsOuting) return null;

    final dest = StylistDestinationParser.inferFromConversation(
      conversation,
      exclude: _unresolvableDestinations,
    );
    if (dest == null) return null;

    final gpsCity = UserLocationService.instance.cityShortLabel;
    if (dest.toLowerCase().trim() == gpsCity.toLowerCase().trim()) {
      return null;
    }

    // Autoritou je geokóder – pozná mestá celého sveta, nielen tie veľké. Skús
    // mesto nájsť; ak ho geokóder pozná (akokoľvek malé), je to OK a pustíme to
    // ďalej na AI. Až keď ho NEnájde, riešime preklep/otázku.
    final date = _eventDateFromConversation(conversation);
    final snap = await _hourlyWeatherService.getWeatherForCityAndDate(
      city: dest,
      date: date,
    );
    if (snap.fromOpenMeteo) return null;

    // Mesto neexistuje / je preklep. Nehádame náhodné mesto – pre časté mestá
    // ponúkneme tip, inak sa úprimne spýtame znova.
    _unresolvableDestinations.add(dest.toLowerCase().trim());
    final suggestion = StylistCitySuggester.suggestCorrection(dest);
    if (suggestion != null) {
      return 'Hmm, mesto „$dest“ som nenašiel 🤔 Nemyslíš náhodou $suggestion? '
          'Ak nie, napíš mi ho prosím inak (alebo najbližšie väčšie mesto).';
    }
    return 'Hmm, mesto „$dest“ som nenašiel 😅 Skús mi ho prosím napísať inak '
        'alebo mi napíš najbližšie väčšie mesto – podľa neho vezmem počasie '
        'a doladím outfit.';
  }

  DateTime _eventDateFromConversation(String conversation) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final stateDate = DateTime.tryParse(_outfitContextState.dateKey ?? '');
    if (stateDate != null) {
      return DateTime(stateDate.year, stateDate.month, stateDate.day);
    }
    return StylistDayParser.resolveDate(conversation, now: now) ?? today;
  }

  bool _userDeclinedRainAdvice() {
    return StylistConversationSignals.userDeclinedRainAdvice(
      _conversationHintText(),
    );
  }

  Map<String, dynamic> _enrichWeatherWithTrip(
    Map<String, dynamic> base,
    OutfitWeatherDaySnapshot snapshot,
    String conversation,
  ) {
    final event = _eventFromConversation(
      rawEvent: null,
      fallbackLocation: UserLocationService.instance.cityLabel,
    );
    final trip = TripWeatherAnalyzer.analyze(
      day: snapshot,
      window: event.effectiveTripWindow,
      timeKnown: event.effectiveTripWindow.hasExplicitTime,
    );
    final isTomorrow = _conversationSaysTomorrow(conversation);
    final terrain = StylistActivityTerrainClassifier.classify(
      conversationText: conversation,
      occasion: event.occasion,
    );
    final declinedRain = _userDeclinedRainAdvice();
    final city = event.locationLabel.trim().isNotEmpty
        ? event.locationLabel.split(',').first.trim()
        : UserLocationService.instance.cityShortLabel;
    final chatSummary = StylistWeatherTipBuilder.naturalDaySummarySk(
      snapshot: snapshot,
      locationLabel: city,
      isTomorrow: isTomorrow,
      eventHour: event.hourLocal,
      terrain: terrain,
      includeRain: !declinedRain,
    );
    final tripPayload = trip.toWeatherContextPayload();
    final rawSuitabilityTempC = trip.outfitTempC;
    final outfitTempC = StylistWeatherAdjustment.adjustActivityTempC(
      rawTempC: rawSuitabilityTempC,
      terrain: terrain,
      hourLocal: event.hourLocal,
    );
    // One canonical suitability temperature prevents raw forecast and
    // terrain-adjusted values from alternating in user-facing chat.
    tripPayload['outfitTempC'] = outfitTempC;
    tripPayload['forecastTempC'] = rawSuitabilityTempC;
    tripPayload.remove('tripOutfitTempC');
    if (declinedRain) {
      tripPayload.remove('tripWeatherAdvisory');
    }
    final wetGroundRisk =
        terrain == StylistActivityTerrain.wetGround &&
        (snapshot.willRain ||
            trip.rainBeforeEvent ||
            trip.rainDuringEvent ||
            snapshot.morningRainSegment);
    return <String, dynamic>{
      ...base,
      ...tripPayload,
      'activityTerrain': terrain == StylistActivityTerrain.wetGround
          ? 'wetGround'
          : 'urban',
      'wetGroundRisk': wetGroundRisk,
      'outfitTempC': outfitTempC,
      'userDeclinedRainAdvice': declinedRain,
      if (chatSummary != null) 'weatherChatSummarySk': chatSummary,
      if (declinedRain) 'rainAdviceSk': null,
    };
  }

  Map<String, dynamic> _snapshotToWeatherContext(
    OutfitWeatherDaySnapshot snapshot,
  ) {
    return <String, dynamic>{
      'cityName': snapshot.cityName,
      'date': snapshot.date.toIso8601String(),
      'morningTempC': snapshot.morningTempC,
      'noonTempC': snapshot.noonTempC,
      'eveningTempC': snapshot.eveningTempC,
      'minTempC': snapshot.minTempC,
      'maxTempC': snapshot.maxTempC,
      'willRain': snapshot.willRain,
      'rainTimeText': snapshot.rainTimeText,
      'morningRainSegment': snapshot.morningRainSegment,
      'afternoonRainSegment': snapshot.afternoonRainSegment,
      'isWindy': snapshot.isWindy,
      'summaryText': snapshot.summaryText,
      'fromOpenMeteo': snapshot.fromOpenMeteo,
      if (snapshot.hourlyTempCByLocalHour != null)
        'hourlyTempCByLocalHour': snapshot.hourlyTempCByLocalHour,
      if (snapshot.hourlyWeatherCodeByLocalHour != null)
        'hourlyWeatherCodeByLocalHour': snapshot.hourlyWeatherCodeByLocalHour,
    };
  }

  Future<void> _ensureWeatherContext() async {
    if (_cachedWeatherContext != null &&
        _weatherCachedAt != null &&
        DateTime.now().difference(_weatherCachedAt!) <
            const Duration(minutes: 15)) {
      return;
    }
    _cachedWeatherContext = await _fetchWeatherContext();
    _weatherCachedAt = DateTime.now();
  }

  Map<String, dynamic> _weatherContextForApi({required bool lightweight}) {
    final full =
        _cachedWeatherContext ??
        <String, dynamic>{
          'cityName': UserLocationService.instance.cityShortLabel,
        };
    if (!lightweight) return Map<String, dynamic>.from(full);
    return <String, dynamic>{
      'cityName': full['cityName'],
      'noonTempC': full['noonTempC'],
      'eveningTempC': full['eveningTempC'],
      'willRain': full['willRain'] ?? false,
      'isWindy': full['isWindy'] ?? false,
    };
  }

  Future<Map<String, dynamic>> _fetchWeatherContext() async {
    final today = DateTime.now();
    final city = UserLocationService.instance.cityShortLabel;
    final snapshot = await _hourlyWeatherService.getWeatherForCityAndDate(
      city: city,
      date: today,
    );
    return _snapshotToWeatherContext(snapshot);
  }

  /// Odstráni z textu odporúčanie zobrať si vrchnú vrstvu (bundu/kabát/sako…),
  /// keď v outfite žiadna nie je. Dáždnik a iné rady ostávajú – ten reálne
  /// pomôže aj bez toho, aby sme ho ukazovali ako kus oblečenia.
  String _stripOuterwearAdvice(String text) {
    const noun =
        r'(?:bundu|bunda|kabát|kabat|sako|vetrovku|vetrovka|parku|parka|kardigán|kardigan|mikinu|mikina)';
    var out = text;
    // 1) Pár so spojkou – vrchná vrstva ako druhá: „dáždnik či bundu“ → „dáždnik“.
    out = out.replaceAll(
      RegExp(
        r'\s*,?\s*(?:a|aj|či|ci|alebo|prípadne|pripadne)\s+' + noun + r'\b',
        caseSensitive: false,
      ),
      '',
    );
    // 2) Pár so spojkou – vrchná vrstva ako prvá: „bundu či dáždnik“ → „dáždnik“.
    out = out.replaceAll(
      RegExp(
        r'\b' + noun + r'\s+(?:a|aj|či|ci|alebo|prípadne|pripadne)\s+',
        caseSensitive: false,
      ),
      '',
    );
    // 3) Samostatná veta/klauza s výzvou obliecť si vrchnú vrstvu.
    out = out.replaceAll(
      RegExp(
        r'\b(?:zober|zober si|vezmi|vezmi si|pribaľ|pribal|nezabudni|obleč|oblec|daj si|prihoď|prihod)\b[^.!?]*\b' +
            noun +
            r'\b[^.!?]*(?:[.!?]|$)',
        caseSensitive: false,
      ),
      '',
    );
    out = out
        .replaceAll(RegExp(r'\s+,'), ',')
        .replaceAll(RegExp(r',\s*\.'), '.')
        .replaceAll(RegExp(r'\s+\.'), '.')
        .replaceAll(RegExp(r'\(\s*\)'), '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r'\s+([!?])'), r'$1')
        .trim();
    return out;
  }

  String _stripRainAdvice(String text) {
    var out = text;
    out = out.replaceAll(
      RegExp(
        r'\b(?:nezabudni|zober|vezmi|prihoď|prihod)\b[^.!?]*\b(?:dáždnik|dazdnik|daždnik)\b[^.!?]*(?:[.!?]|$)',
        caseSensitive: false,
      ),
      '',
    );
    out = out.replaceAll(
      RegExp(
        r'[^.!?]*(?:očakáva|ocekava|môže|moze)\s+(?:dážď|dazd|dažd|prehánka)[^.!?]*(?:[.!?]|$)',
        caseSensitive: false,
      ),
      '',
    );
    return out
        .replaceAll(RegExp(r'\s+,'), ',')
        .replaceAll(RegExp(r',\s*\.'), '.')
        .replaceAll(RegExp(r'\s+\.'), '.')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  String _sanitizeStylistReplyForDisplay(
    String raw, {
    bool isOutfitReply = false,
    bool outfitHasOuterwear = true,
    bool stripRainAdvice = false,
  }) {
    var out = raw.trim();
    if (isOutfitReply && !outfitHasOuterwear) {
      out = _stripOuterwearAdvice(out);
    }
    if (stripRainAdvice) {
      out = _stripRainAdvice(out);
    }
    out = out.replaceAll(
      RegExp(r'suggestedItemIds\s*:\s*\[[^\]]*\]', caseSensitive: false),
      '',
    );
    out = out.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '');
    out = out.replaceAll(RegExp(r'https?:\/\/\S+'), '');
    out = out.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'),
      (match) => match.group(1) ?? '',
    );
    out = out.replaceAll(
      RegExp(r'\bid:\s*[A-Za-z0-9_-]{8,}\b', caseSensitive: false),
      '',
    );
    out = out.replaceAll(RegExp(r'\(\s*\)'), '');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    out = out.trim();
    out = SlovakCityLocative.fixCityDeclensionInText(out);
    // Poistka: nikdy nezobraz surový JSON
    // keď model vráti pokazený formát). Radšej ľudská hláška.
    final looksLikeGarbage =
        out.isEmpty || RegExp(r'''^[\s{}\[\]"',.:;]*$''').hasMatch(out);
    if (looksLikeGarbage) {
      return isOutfitReply
          ? 'Toto je môj návrh outfitu podľa počasia a tvojho šatníka.'
          : 'Prepáč, trochu som sa pri tom zamotal 😅 Skús to prosím napísať '
                'ešte raz.';
    }
    if (isOutfitReply) {
      out = StylistOutfitExplainBuilder.stripTechnicalJargon(out);
      if (out.isEmpty) {
        return 'Pripravil som ti outfit z toho, čo máš v šatníku.';
      }
      return out;
    }
    if (_replyAsksUserForWeather(out) || _replyIsBadGenericOutfitAdvice(out)) {
      // Odpoveď nahradíme otázkou LEN ak naozaj niečo chýba. Pri follow-up
      // otázke typu „prečo práve táto kombinácia“ je už všetko známe — vtedy
      // by bola otázka úplne mimo, tak radšej necháme pôvodný text.
      final gpsCity = UserLocationService.instance.cityLabel;
      final missing = EventClarification.missingMessage(
        _conversationHintText(),
        gpsCityLabel: gpsCity,
      );
      if (missing != null) return missing;
    }
    return out;
  }

  List<Map<String, String>> _buildHistoryForBackend() {
    final start = _messages.length > _historyLimit
        ? _messages.length - _historyLimit
        : 0;
    final recentMessages = _messages.sublist(start);
    return recentMessages
        .map(
          (message) => <String, String>{
            'role': message.isUser ? 'user' : 'assistant',
            'content': message.text,
          },
        )
        .toList(growable: false);
  }

  void _showPremiumBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Stylist chat je Premium',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pokračuj v konverzácii a získaj osobné odporúčania.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: const Color(0xFF191512),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text(
                      'Vyskúšať Premium',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scrollToBottom() {
    _schedulePersist();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _buildChatDrawer() {
    return Drawer(
      backgroundColor: _bgMid,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chaty',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      if (!_isSending) _startNewChat();
                    },
                    icon: const Icon(Icons.add, size: 18, color: _accent),
                    label: const Text(
                      'Nový',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: StreamBuilder<List<StylistChatThread>>(
                stream: _chatStore.watchThreads(),
                builder: (context, snapshot) {
                  final threads = snapshot.data ?? const <StylistChatThread>[];
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: _accent),
                    );
                  }
                  if (threads.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Zatiaľ nemáš žiadne uložené chaty.\nZačni písať a chat sa uloží sem.',
                        style: TextStyle(color: _textSecondary, height: 1.4),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: threads.length,
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      final isActive = thread.id == _activeChatId;
                      return ListTile(
                        selected: isActive,
                        selectedTileColor: Colors.white.withOpacity(0.05),
                        leading: Icon(
                          Icons.chat_bubble_outline,
                          size: 20,
                          color: isActive ? _accent : _textSecondary,
                        ),
                        title: Text(
                          thread.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isActive ? _accent : _textPrimary,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          _openChat(thread.id);
                        },
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert,
                            color: _textSecondary,
                            size: 20,
                          ),
                          color: _bgTop,
                          onSelected: (value) {
                            if (value == 'rename') {
                              _renameChatDialog(thread);
                            } else if (value == 'delete') {
                              _deleteChatDialog(thread);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text(
                                'Premenovať',
                                style: TextStyle(color: _textPrimary),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Zmazať',
                                style: TextStyle(color: Color(0xFFE57373)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (kDebugMode) ...[
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined, color: _accent),
                title: const Text(
                  'Pipeline debug testy',
                  style: TextStyle(color: _accent, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  '10 scenárov → outfit, explain, wardrobe, identity + sumár',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
                onTap: _isSending ? null : _runPipelineDebugTests,
              ),
              ListTile(
                leading: const Icon(Icons.map_outlined, color: _accent),
                title: const Text(
                  'Location QA testy',
                  style: TextStyle(color: _accent, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Destinácie M9 — krajiny, mestá, POI, letiská',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
                onTap: _isSending ? null : _runLocationQaTests,
              ),
              ListTile(
                leading: const Icon(Icons.psychology_outlined, color: _accent),
                title: const Text(
                  'Conversation QA testy',
                  style: TextStyle(color: _accent, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Rozhodnutia M10 — GENERATE vs CLARIFY (300+ scenárov)',
                  style: TextStyle(color: _textSecondary, fontSize: 12),
                ),
                onTap: _isSending ? null : _runConversationQaTests,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runPipelineDebugTests() async {
    Navigator.of(context).pop();
    if (!kDebugMode) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Spúšťam Stylist Chat pipeline debug testy…'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      final run = await StylistChatPipelineDebugRunner.runAll(
        outfitService: _stylistChatOutfitService,
        chatService: _stylistChatService,
      );
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      await _showDebugReportDialog(run);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Debug testy zlyhali: $e')),
      );
    }
  }

  Future<void> _runLocationQaTests() async {
    Navigator.of(context).pop();
    if (!kDebugMode) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Spúšťam Location QA testy…')),
    );
    try {
      await Future<void>.delayed(Duration.zero);
      final run = StylistLocationQaRunner.runAll();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      await _showTextReportDialog(
        title: 'Location QA report',
        header: '',
        body: run.fullText(),
        passLabel:
            '${run.summary.passed}/${run.summary.total} OK · ${run.meta.durationMs} ms',
        allPass: run.summary.failed == 0,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Location QA testy zlyhali: $e')),
      );
    }
  }

  Future<void> _runConversationQaTests() async {
    Navigator.of(context).pop();
    if (!kDebugMode) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Spúšťam Conversation QA testy…')),
    );
    try {
      await Future<void>.delayed(Duration.zero);
      final run = StylistConversationQaRunner.runAll();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      await _showTextReportDialog(
        title: 'Conversation QA report',
        header: '',
        body: run.fullText(),
        passLabel:
            '${run.summary.passed}/${run.summary.total} OK · ${run.meta.durationMs} ms',
        allPass: run.summary.failed == 0,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Conversation QA testy zlyhali: $e')),
      );
    }
  }

  Future<void> _showTextReportDialog({
    required String title,
    required String header,
    required String body,
    required String passLabel,
    required bool allPass,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: _bgMid,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.bug_report_outlined, color: _accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      passLabel,
                      style: TextStyle(
                        color: allPass
                            ? const Color(0xFF7FBF7F)
                            : const Color(0xFFE57373),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    body,
                    style: const TextStyle(
                      color: _accent,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: body));
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('Kopírovať report'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDebugReportDialog(StylistChatDebugRunResult run) async {
    final summary = run.summary;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: _bgMid,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.bug_report_outlined, color: _accent),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Stylist Chat test report',
                        style: TextStyle(
                          color: _accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      '${summary.succeeded}/${summary.total} OK',
                      style: TextStyle(
                        color: summary.succeeded == summary.total
                            ? const Color(0xFF7FBF7F)
                            : const Color(0xFFE57373),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        summary.formatBlock(),
                        style: const TextStyle(
                          color: _accent,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < run.reports.length; i++) ...[
                        SelectableText(
                          run.reports[i].formatBlock(index: i + 1),
                          style: TextStyle(
                            color: run.reports[i].ok
                                ? _textPrimary
                                : const Color(0xFFE57373),
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SelectableText(
                        run.footerText(),
                        style: const TextStyle(
                          color: _accent,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: run.fullText()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Report skopírovaný'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text(
                        'Kopírovať',
                        style: TextStyle(color: _textSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'Zavrieť',
                        style: TextStyle(color: _accent),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _renameChatDialog(StylistChatThread thread) async {
    final controller = TextEditingController(text: thread.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _bgMid,
          title: const Text(
            'Premenovať chat',
            style: TextStyle(color: _textPrimary),
          ),
          content: Theme(
            // Override-neme farby výberu/úchytov, nech nie sú fialové z default
            // témy a kurzor je zlatý.
            data: Theme.of(dialogContext).copyWith(
              textSelectionTheme: const TextSelectionThemeData(
                cursorColor: _accent,
                selectionColor: Color(0x55C8A36A),
                selectionHandleColor: _accent,
              ),
            ),
            child: TextField(
              controller: controller,
              autofocus: true,
              cursorColor: _accent,
              style: const TextStyle(color: _textPrimary),
              decoration: InputDecoration(
                hintText: 'Názov chatu',
                hintStyle: const TextStyle(color: _textSecondary),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _textSecondary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _accent, width: 2),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Zrušiť',
                style: TextStyle(color: _textSecondary),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Uložiť', style: TextStyle(color: _accent)),
            ),
          ],
        );
      },
    );
    if (newTitle == null || newTitle.isEmpty) return;
    await _chatStore.renameChat(thread.id, newTitle);
    if (thread.id == _activeChatId && mounted) {
      setState(() {
        _chatTitle = newTitle;
        _chatTitleEdited = true;
      });
    }
  }

  Future<void> _deleteChatDialog(StylistChatThread thread) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _bgMid,
          title: const Text(
            'Zmazať chat?',
            style: TextStyle(color: _textPrimary),
          ),
          content: Text(
            'Naozaj chceš zmazať „${thread.title}"? Túto akciu nie je možné vrátiť.',
            style: const TextStyle(color: _textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Zrušiť',
                style: TextStyle(color: _textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Zmazať',
                style: TextStyle(color: Color(0xFFE57373)),
              ),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;
    // Ak mažeme práve otvorený chat, najprv zrušíme naplánované uloženie a
    // vyčistíme stav BEZ ukladania — inak by debounce/persist zmazaný dokument
    // hneď znova vytvoril (preto sa predtým „nič nestalo" a až napodruhé zmazal).
    final deletingActive = thread.id == _activeChatId;
    if (deletingActive) {
      _saveTimer?.cancel();
      _activeChatId = null;
      _resetChatState();
    }
    await _chatStore.deleteChat(thread.id);
  }

  /// Premenuje práve otvorený chat (funguje aj keď ešte nie je v histórii).
  Future<void> _renameCurrentChat() async {
    final id = _activeChatId;
    if (id == null) {
      // Nový/neuložený chat — premenovanie nemá čo zapísať, povieme to.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Najprv napíš správu, potom sa dá premenovať.'),
        ),
      );
      return;
    }
    await _renameChatDialog(
      StylistChatThread(id: id, title: _chatTitle ?? 'Nový chat'),
    );
  }

  /// Zmaže (alebo zahodí) práve otvorený chat. Pre nový neuložený chat len
  /// vyčistí obrazovku — netreba ísť do bočného panela.
  Future<void> _deleteCurrentChat() async {
    final id = _activeChatId;
    final hasContent = _hasUserMessages();
    // Úplne prázdny nový chat — nie je čo mazať.
    if (id == null && !hasContent) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tento chat je prázdny.')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _bgMid,
          title: const Text(
            'Zmazať chat?',
            style: TextStyle(color: _textPrimary),
          ),
          content: const Text(
            'Naozaj chceš zmazať tento chat? Túto akciu nie je možné vrátiť.',
            style: TextStyle(color: _textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Zrušiť',
                style: TextStyle(color: _textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Zmazať',
                style: TextStyle(color: Color(0xFFE57373)),
              ),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    // Najprv zrušíme naplánované uloženie a vyčistíme stav BEZ ukladania,
    // aby debounce/persist zmazaný dokument hneď znova nevytvoril.
    _saveTimer?.cancel();
    final toDelete = id;
    _activeChatId = null;
    _resetChatState();
    if (toDelete != null) {
      await _chatStore.deleteChat(toDelete);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatTheme = Theme.of(context).copyWith(
      colorScheme: Theme.of(
        context,
      ).colorScheme.copyWith(primary: _accent, secondary: _accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _accent,
        selectionColor: _accent.withOpacity(0.35),
        selectionHandleColor: _accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        focusColor: _accent.withOpacity(0.08),
        hoverColor: Colors.transparent,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accent.withOpacity(0.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _accent.withOpacity(0.45)),
        ),
      ),
    );

    return Theme(
      data: chatTheme,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        drawer: _buildChatDrawer(),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Stylist chat',
            style: TextStyle(color: _accent, fontWeight: FontWeight.w700),
          ),
          iconTheme: const IconThemeData(color: _textPrimary),
          actions: [
            IconButton(
              tooltip: 'Nový chat',
              icon: const Icon(Icons.edit_square, color: _accent),
              onPressed: _isSending ? null : _startNewChat,
            ),
            PopupMenuButton<String>(
              tooltip: 'Možnosti chatu',
              color: _bgMid,
              icon: const Icon(Icons.more_vert, color: _textPrimary),
              onSelected: (value) {
                if (value == 'rename') {
                  _renameCurrentChat();
                } else if (value == 'delete') {
                  _deleteCurrentChat();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'rename',
                  child: Text(
                    'Premenovať tento chat',
                    style: TextStyle(color: _textPrimary),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(
                    'Zmazať tento chat',
                    style: TextStyle(color: Color(0xFFE57373)),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_bgTop, _bgMid, _bgBottom],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      itemCount: _messages.length + (_isSending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_isSending && index == _messages.length) {
                          return _TypingBubble(label: _sendingStatusLabel);
                        }
                        final message = _messages[index];
                        return _MessageBubble(
                          message: message,
                          onQuickReply:
                              shouldShowStylistQuickReplies(
                                quickReplyMode: message.quickReplyMode,
                                isUser: message.isUser,
                                isLatest: index == _messages.length - 1,
                                isSending: _isSending,
                                hasPendingImage: _pendingImage != null,
                                isPhotoConversationActive:
                                    _photoStage != _PhotoStage.none,
                                hasAlternativeActions:
                                    message.attachments.isNotEmpty,
                              )
                              ? _sendQuickReply
                              : null,
                          onShoppingText: _sendShoppingAction,
                          onShowAll: _openShoppingResults,
                          onCandidate: _openShoppingCandidateDetail,
                          onWishlist: _openWishlistEditor,
                        );
                      },
                    ),
                  ),
                  if (_pendingImage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                _pendingImage!,
                                height: 72,
                                width: 72,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -8,
                              right: -8,
                              child: InkWell(
                                onTap: _isSending
                                    ? null
                                    : () =>
                                          setState(() => _pendingImage = null),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF1B1B1F),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: _textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _isSending ? null : _showImageSourceSheet,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B1B1F),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 20,
                              color: _isSending
                                  ? _accent.withOpacity(0.45)
                                  : _accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 4,
                            cursorColor: _accent,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            style: const TextStyle(color: _accent),
                            decoration: InputDecoration(
                              hintText: _pendingImage != null
                                  ? 'Napíš k fotke (nepovinné)...'
                                  : 'Napíš správu...',
                              hintStyle: TextStyle(
                                color: _textPrimary.withOpacity(0.72),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _isSending ? null : _sendMessage,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _isSending
                                  ? _accent.withOpacity(0.45)
                                  : _accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.send_rounded,
                              size: 18,
                              color: Color(0xFF191512),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final StylistChatMessage message;
  final ValueChanged<String>? onShoppingText;
  final ValueChanged<String>? onQuickReply;
  final void Function({bool isComplete, int? exactResultCount})? onShowAll;
  final ValueChanged<ShoppingCandidateData>? onCandidate;
  final ValueChanged<ShoppingCandidateData>? onWishlist;

  const _MessageBubble({
    required this.message,
    this.onQuickReply,
    this.onShoppingText,
    this.onShowAll,
    this.onCandidate,
    this.onWishlist,
  });

  @override
  Widget build(BuildContext context) {
    const userBg = Color(0xFFC8A36A);
    const stylistBg = Color(0xFF1B1B1F);
    const textPrimary = Color(0xFFF1F0EC);

    final isUser = message.isUser;
    final hasItems = !isUser && message.suggestedItems.isNotEmpty;
    final hasShoppingAttachments = !isUser && message.attachments.isNotEmpty;
    final hasImage =
        message.localImage != null || (message.imageUrl?.isNotEmpty ?? false);
    final hasText = message.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: hasItems || hasShoppingAttachments ? 320 : 280,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? userBg : stylistBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 240,
                          maxWidth: 240,
                        ),
                        child: message.localImage != null
                            ? Image.file(message.localImage!, fit: BoxFit.cover)
                            : Image.network(
                                message.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: textPrimary,
                                  size: 28,
                                ),
                              ),
                      ),
                    ),
                    if (hasText) const SizedBox(height: 8),
                  ],
                  if (hasText)
                    Text(
                      message.text,
                      style: TextStyle(
                        color: isUser ? const Color(0xFF191512) : textPrimary,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  if (hasItems) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Z tvojho šatníka',
                      style: TextStyle(
                        color: textPrimary.withOpacity(0.72),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.02,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 118,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: message.suggestedItems.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = message.suggestedItems[index];
                          return _SuggestedItemCard(item: item);
                        },
                      ),
                    ),
                  ],
                  if (hasShoppingAttachments) ...[
                    const SizedBox(height: 10),
                    ...message.attachments.map(
                      (attachment) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _ShoppingAttachmentTile(
                          attachment: attachment,
                          onShoppingText: onShoppingText,
                          onShowAll: onShowAll,
                          onCandidate: onCandidate,
                          onWishlist: onWishlist,
                        ),
                      ),
                    ),
                  ],
                  if (!isUser &&
                      message.quickReplyMode == 'yes_no' &&
                      onQuickReply != null) ...[
                    const SizedBox(height: 10),
                    StylistQuickReplyButtons(onSelected: onQuickReply!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShoppingAttachmentTile extends StatelessWidget {
  const _ShoppingAttachmentTile({
    required this.attachment,
    this.onShoppingText,
    this.onShowAll,
    this.onCandidate,
    this.onWishlist,
  });

  final StylistShoppingAttachment attachment;
  final ValueChanged<String>? onShoppingText;
  final void Function({bool isComplete, int? exactResultCount})? onShowAll;
  final ValueChanged<ShoppingCandidateData>? onCandidate;
  final ValueChanged<ShoppingCandidateData>? onWishlist;

  @override
  Widget build(BuildContext context) {
    final candidateRaw = attachment.payload['candidate'];
    final candidate = candidateRaw is Map
        ? Map<String, dynamic>.from(candidateRaw)
        : const <String, dynamic>{};
    if (attachment.kind == 'shopping_candidate') {
      final item = ShoppingCandidateData.fromServer(candidate);
      if (!item.isUsable) return const SizedBox.shrink();
      return ShoppingCandidateCard(
        candidate: item,
        onTap: onCandidate == null ? null : () => onCandidate!(item),
        onWishlist: onWishlist == null ? null : () => onWishlist!(item),
      );
    }
    if (attachment.kind == 'shopping_clarification') {
      final options = (attachment.payload['options'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false);
      return _ShoppingPanel(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final label = switch (option) {
              'WARDROBE' => 'Zo šatníka',
              'SHOPPING' => 'Z obchodov',
              'NO_THANKS' => 'Nie, ďakujem',
              _ => option,
            };
            final message = switch (option) {
              'WARDROBE' => 'zo šatníka',
              'SHOPPING' => 'z obchodov',
              'NO_THANKS' => 'nie, ďakujem',
              _ => option,
            };
            return OutlinedButton(
              onPressed: onShoppingText == null
                  ? null
                  : () => onShoppingText!(message),
              child: Text(label),
            );
          }).toList(),
        ),
      );
    }
    if (attachment.kind == 'shopping_result_group') {
      final complete = attachment.payload['isComplete'] == true;
      final count = attachment.payload['exactResultCount'];
      final label = complete && count is num
          ? 'Zobraziť všetky (${count.toInt()})'
          : 'Zobraziť ďalšie výsledky';
      return _ShoppingPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFFF1F0EC))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: onShowAll == null
                      ? null
                      : () => onShowAll!(
                          isComplete: complete,
                          exactResultCount: count is num ? count.toInt() : null,
                        ),
                  child: const Text('Zobraziť všetky'),
                ),
                OutlinedButton(
                  onPressed: onShoppingText == null
                      ? null
                      : () => onShoppingText!('ukáž ďalšie'),
                  child: const Text('Ukázať ďalšie'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (attachment.kind == 'shopping_session_recovery') {
      final stale = attachment.payload['errorCode'] == 'POOL_STALE';
      return _ShoppingPanel(
        child: FilledButton.icon(
          onPressed: onShoppingText == null
              ? null
              : () => onShoppingText!(
                  attachment.payload['actionMessage']?.toString() ??
                      'vyhľadaj znova',
                ),
          icon: const Icon(Icons.refresh),
          label: Text(stale ? 'Aktualizovať výsledky' : 'Znova vyhľadať'),
        ),
      );
    }
    if (attachment.kind == 'shopping_relaxations') {
      final relaxations =
          (attachment.payload['relaxations'] as List? ?? const [])
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .where(
                (item) => item['label'] is String && item['message'] is String,
              )
              .toList(growable: false);
      return _ShoppingPanel(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: relaxations
              .map(
                (item) => OutlinedButton(
                  onPressed: onShoppingText == null
                      ? null
                      : () => onShoppingText!(item['message'] as String),
                  child: Text(item['label'] as String),
                ),
              )
              .toList(growable: false),
        ),
      );
    }
    final isWishlist =
        attachment.kind == 'wishlist_offer' ||
        attachment.kind == 'wishlist_editor';
    final wishlistCandidate = ShoppingCandidateData.fromServer(candidate);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFF26262C),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: const Color(0xFFC8A36A).withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite_border, color: Color(0xFFC8A36A), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              wishlistCandidate.isUsable
                  ? 'Nastav cieľovú cenu a veľkosti.'
                  : 'Vyber konkrétny produkt pre Wishlist.',
              style: const TextStyle(color: Color(0xFFF1F0EC), fontSize: 12),
            ),
          ),
          if (isWishlist)
            TextButton(
              onPressed: wishlistCandidate.isUsable && onWishlist != null
                  ? () => onWishlist!(wishlistCandidate)
                  : null,
              child: const Text('Pridať'),
            ),
        ],
      ),
    );
  }
}

class _ShoppingPanel extends StatelessWidget {
  const _ShoppingPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFF26262C),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFC8A36A).withValues(alpha: .45)),
    ),
    child: child,
  );
}

class _SuggestedItemCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _SuggestedItemCard({required this.item});

  String? _resolveImageUrl(Map<String, dynamic> item) {
    final cutout = (item['cutoutImageUrl'] ?? '').toString().trim();
    if (cutout.startsWith('http')) return cutout;
    final clean = (item['cleanImageUrl'] ?? '').toString().trim();
    if (clean.startsWith('http')) return clean;
    return getBestWardrobeImageUrlOrNull(item);
  }

  @override
  Widget build(BuildContext context) {
    const textPrimary = Color(0xFFF1F0EC);
    const textSecondary = Color(0xFFAAA59B);
    final label = (item['name'] ?? item['label'] ?? item['category'] ?? 'Kúsok')
        .toString();
    final imageUrl = _resolveImageUrl(item);

    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 78,
            width: double.infinity,
            child: imageUrl == null
                ? const Icon(Icons.checkroom, color: textSecondary, size: 22)
                : Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: textSecondary,
                      size: 20,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bublina „Stylista píše …" s animovanými bodkami (•, ••, •••).
class _TypingBubble extends StatefulWidget {
  const _TypingBubble({required this.label});

  final String label;

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const stylistBg = Color(0xFF1B1B1F);
    const textPrimary = Color(0xFFF1F0EC);
    // Label zbavíme koncových bodiek – animované si pridáme sami.
    final cleanLabel = widget.label
        .replaceAll(RegExp(r'[.\u2026]+$'), '')
        .trimRight();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: stylistBg,
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        cleanLabel,
                        style: const TextStyle(
                          color: textPrimary,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    // Tri bodky, ktoré sa postupne rozsvecujú.
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (i) {
                            // Každá bodka má posunutú fázu animácie.
                            final phase = (_controller.value * 3 - i).clamp(
                              0.0,
                              1.0,
                            );
                            final opacity =
                                0.25 +
                                0.75 *
                                    (1 - (phase - 0.5).abs() * 2).clamp(
                                      0.0,
                                      1.0,
                                    );
                            return Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: Opacity(
                                opacity: opacity,
                                child: const Text(
                                  '.',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 16,
                                    height: 1.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
