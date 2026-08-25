import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'stylist_notification_intent.dart';
import 'wishlist_notification_router.dart';

/// Dispatches FCM notification taps by `data.type`.
///
/// Wishlist types are delegated to [WishlistNotificationRouter] unchanged.
/// `stylist_reply` becomes a Stylist tab intent and is never Shopping-gated.
class AppNotificationRouter {
  AppNotificationRouter({
    WishlistNotificationRouter? wishlistRouter,
    bool Function()? isAuthenticated,
    void Function(StylistNotificationIntent)? onSelectStylistTab,
  }) : _wishlist = wishlistRouter ?? WishlistNotificationRouter.instance,
       _isAuthenticated =
           isAuthenticated ??
           (() => FirebaseAuth.instance.currentUser != null),
       _onSelectStylistTab = onSelectStylistTab;

  static final AppNotificationRouter instance = AppNotificationRouter();

  final WishlistNotificationRouter _wishlist;
  final bool Function() _isAuthenticated;
  void Function(StylistNotificationIntent)? _onSelectStylistTab;

  StylistNotificationIntent? _pendingStylist;
  String? _lastDeliveredDedupeKey;
  bool _handlersInstalled = false;

  @visibleForTesting
  StylistNotificationIntent? get pendingStylistIntent => _pendingStylist;

  @visibleForTesting
  StylistNotificationIntent? get lastDeliveredStylistIntent =>
      StylistNotificationIntentStore.instance.current;

  void attachStylistTabSink(void Function(StylistNotificationIntent) sink) {
    _onSelectStylistTab = sink;
    flushPending();
  }

  void detachStylistTabSink() {
    _onSelectStylistTab = null;
  }

  void installHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;
    FirebaseMessaging.onMessageOpenedApp.listen(_onRemoteMessage);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _onRemoteMessage(message);
    });
  }

  void handleRemoteMessage(RemoteMessage message) => _onRemoteMessage(message);

  void handleData(Map<String, dynamic> data) {
    final stylist = parseStylistIntent(data);
    if (stylist != null) {
      _handleStylist(stylist);
      return;
    }
    _wishlist.handleData(data);
  }

  /// `stylist_reply` always yields an intent. Empty chat/job ids become null.
  static StylistNotificationIntent? parseStylistIntent(
    Map<String, dynamic> data,
  ) {
    final type = data['type']?.toString();
    if (type != 'stylist_reply') return null;
    return StylistNotificationIntent(
      jobId: _nonEmpty(data['jobId']),
      chatId: _nonEmpty(data['chatId']),
    );
  }

  bool flushPending() {
    final stylistDelivered = _flushStylistPending();
    final wishlistDelivered = _wishlist.flushPending();
    return stylistDelivered || wishlistDelivered;
  }

  @visibleForTesting
  void resetForTest() {
    _pendingStylist = null;
    _lastDeliveredDedupeKey = null;
    _handlersInstalled = false;
    _onSelectStylistTab = null;
    StylistNotificationIntentStore.instance.clear();
  }

  void _onRemoteMessage(RemoteMessage message) {
    handleData(Map<String, dynamic>.from(message.data));
  }

  void _handleStylist(StylistNotificationIntent intent) {
    if (!_isAuthenticated() || _onSelectStylistTab == null) {
      _pendingStylist = intent;
      _flushStylistPending();
      return;
    }
    _deliverStylist(intent);
  }

  bool _flushStylistPending() {
    final pending = _pendingStylist;
    if (pending == null) return false;
    if (!_isAuthenticated()) return false;
    if (_onSelectStylistTab == null) return false;
    _pendingStylist = null;
    _deliverStylist(pending);
    return true;
  }

  void _deliverStylist(StylistNotificationIntent intent) {
    StylistNotificationIntentStore.instance.replace(intent);
    if (_lastDeliveredDedupeKey == intent.dedupeKey) {
      return;
    }
    _lastDeliveredDedupeKey = intent.dedupeKey;
    _onSelectStylistTab?.call(intent);
  }

  static String? _nonEmpty(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }
}
