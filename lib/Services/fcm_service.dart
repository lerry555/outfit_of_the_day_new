import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_notification_router.dart';

/// Background handler musí byť top-level (alebo statická) funkcia označená
/// @pragma('vm:entry-point'). Správa s `notification` payloadom sa na pozadí
/// zobrazí systémom automaticky, takže tu nemusíme nič robiť.
@pragma('vm:entry-point')
Future<void> stylistFcmBackgroundHandler(RemoteMessage message) async {}

/// Alias kept for callers that prefer a non-stylist name.
@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) =>
    stylistFcmBackgroundHandler(message);

/// Device FCM token + last uid it was persisted for (not a device registry).
class FcmLocalRegistration {
  const FcmLocalRegistration({this.token, this.uid});

  final String? token;
  final String? uid;
}

/// Persist/remove this device token on `users/{uid}.fcmTokens`.
abstract class FcmUserTokenRepository {
  Future<void> addToken({required String uid, required String token});
  Future<void> removeToken({required String uid, required String token});
}

abstract class FcmMessagingClient {
  Future<void> requestPermission();
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;
}

abstract class FcmLocalRegistrationCache {
  Future<FcmLocalRegistration> read();
  Future<void> write(FcmLocalRegistration value);
}

/// Admin claim repair: unique ownership of one live FCM token.
abstract class FcmTokenClaimClient {
  Future<void> claim(String token);
}

/// Registrácia FCM tokenu a povolení pre push notifikácie (post-auth lifecycle).
class FcmService {
  FcmService._({
    String? Function()? currentUid,
    FcmUserTokenRepository? tokens,
    FcmMessagingClient? messaging,
    FcmLocalRegistrationCache? cache,
    AppNotificationRouter? router,
    FcmTokenClaimClient? claim,
  }) : _currentUidOverride = currentUid,
       _tokensOverride = tokens,
       _messagingOverride = messaging,
       _cacheOverride = cache,
       _routerOverride = router,
       _claimOverride = claim;

  factory FcmService() => FcmService._();

  @visibleForTesting
  factory FcmService.forTest({
    required String? Function() currentUid,
    required FcmUserTokenRepository tokens,
    required FcmMessagingClient messaging,
    required FcmLocalRegistrationCache cache,
    AppNotificationRouter? router,
    FcmTokenClaimClient? claim,
  }) {
    return FcmService._(
      currentUid: currentUid,
      tokens: tokens,
      messaging: messaging,
      cache: cache,
      router: router,
      claim: claim ?? const _NoopFcmTokenClaimClient(),
    );
  }

  static final FcmService instance = FcmService();

  static const _localTokenKey = 'fcm_local_token_v1';
  static const _localBoundUidKey = 'fcm_local_bound_uid_v1';

  final String? Function()? _currentUidOverride;
  final FcmUserTokenRepository? _tokensOverride;
  final FcmMessagingClient? _messagingOverride;
  final FcmLocalRegistrationCache? _cacheOverride;
  final AppNotificationRouter? _routerOverride;
  final FcmTokenClaimClient? _claimOverride;

  bool _started = false;
  String? _boundUid;
  StreamSubscription<String>? _tokenRefreshSub;

  String? _currentUid() {
    final override = _currentUidOverride;
    if (override != null) return override();
    return FirebaseAuth.instance.currentUser?.uid;
  }

  FcmUserTokenRepository get _tokens =>
      _tokensOverride ?? const _FirestoreFcmUserTokenRepository();

  FcmMessagingClient get _messaging =>
      _messagingOverride ?? const _FirebaseFcmMessagingClient();

  FcmLocalRegistrationCache get _cache =>
      _cacheOverride ?? const _PrefsFcmLocalRegistrationCache();

  AppNotificationRouter get _router =>
      _routerOverride ?? AppNotificationRouter.instance;

  FcmTokenClaimClient get _claim =>
      _claimOverride ?? const _CallableFcmTokenClaimClient();

  @visibleForTesting
  bool get isStarted => _started;

  @visibleForTesting
  String? get boundUid => _boundUid;

  /// Požiada o povolenie, uloží token zariadenia do
  /// `users/{uid}.fcmTokens` a počúva na jeho obnovu.
  Future<void> init() async {
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      debugPrint('FCM init skipped — signed out');
      return;
    }

    if (_started && _boundUid == uid) {
      _router.installHandlers();
      _router.flushPending();
      await _claimCurrentToken(uid);
      return;
    }

    if (_started && _boundUid != uid) {
      await _detachLifecycle();
    }

    _started = true;
    _boundUid = uid;
    try {
      _router.installHandlers();
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      await _persistToken(token, listenerUid: uid);
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((refreshed) {
        unawaited(_persistToken(refreshed, listenerUid: uid));
      });
      _router.flushPending();
    } catch (e) {
      debugPrint('FCM init error: $e');
      await _detachLifecycle();
    }
  }

  /// Removes this device token from the signed-in user, then resets local FCM.
  /// Best-effort: remote failures are logged and local lifecycle still resets.
  Future<void> clearLocalRegistration() async {
    String? token;
    try {
      token = await _messaging.getToken();
    } catch (_) {}
    token ??= (await _cache.read()).token;

    final uid = _currentUid();
    if (uid != null && token != null && token.trim().isNotEmpty) {
      try {
        await _tokens.removeToken(uid: uid, token: token.trim());
      } catch (e) {
        debugPrint('FCM arrayRemove on logout error: $e');
      }
    }

    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('FCM deleteToken error: $e');
    }

    await _cache.write(const FcmLocalRegistration());
    await _detachLifecycle();
  }

  Future<void> _persistToken(String? token, {required String listenerUid}) async {
    final uid = _currentUid();
    if (uid == null || token == null || token.trim().isEmpty) return;
    if (uid != listenerUid) return;
    if (_boundUid != null && _boundUid != uid) return;

    final trimmed = token.trim();
    final previous = await _cache.read();
    try {
      if (previous.token != null &&
          previous.token!.trim().isNotEmpty &&
          previous.token!.trim() != trimmed &&
          previous.uid == uid) {
        await _tokens.removeToken(uid: uid, token: previous.token!.trim());
      }
      await _tokens.addToken(uid: uid, token: trimmed);
      await _cache.write(FcmLocalRegistration(token: trimmed, uid: uid));
    } catch (e) {
      debugPrint('FCM save token error: $e');
    }
    await _claimToken(trimmed, listenerUid: listenerUid);
  }

  Future<void> _claimCurrentToken(String listenerUid) async {
    try {
      final token = await _messaging.getToken();
      await _claimToken(token, listenerUid: listenerUid);
    } catch (e) {
      debugPrint('FCM claim retry error: $e');
    }
  }

  Future<void> _claimToken(String? token, {required String listenerUid}) async {
    final uid = _currentUid();
    if (uid == null || token == null || token.trim().isEmpty) return;
    if (uid != listenerUid) return;
    if (_boundUid != null && _boundUid != uid) return;
    try {
      await _claim.claim(token.trim());
    } catch (e) {
      debugPrint('FCM claim token error: $e');
    }
  }

  Future<void> _detachLifecycle() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _started = false;
    _boundUid = null;
  }
}

class _FirestoreFcmUserTokenRepository implements FcmUserTokenRepository {
  const _FirestoreFcmUserTokenRepository();

  @override
  Future<void> addToken({required String uid, required String token}) {
    return FirebaseFirestore.instance.collection('users').doc(uid).set(
      <String, dynamic>{
        'fcmTokens': FieldValue.arrayUnion(<String>[token]),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> removeToken({required String uid, required String token}) {
    return FirebaseFirestore.instance.collection('users').doc(uid).set(
      <String, dynamic>{
        'fcmTokens': FieldValue.arrayRemove(<String>[token]),
      },
      SetOptions(merge: true),
    );
  }
}

class _FirebaseFcmMessagingClient implements FcmMessagingClient {
  const _FirebaseFcmMessagingClient();

  @override
  Future<void> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('FCM permission denied — continuing without fatal error');
    }
  }

  @override
  Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  @override
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();

  @override
  Stream<String> get onTokenRefresh => FirebaseMessaging.instance.onTokenRefresh;
}

class _NoopFcmTokenClaimClient implements FcmTokenClaimClient {
  const _NoopFcmTokenClaimClient();

  @override
  Future<void> claim(String token) async {}
}

class _CallableFcmTokenClaimClient implements FcmTokenClaimClient {
  const _CallableFcmTokenClaimClient();

  @override
  Future<void> claim(String token) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-east1')
        .httpsCallable(
          'claimFcmToken',
          options: HttpsCallableOptions(
            timeout: const Duration(seconds: 8),
          ),
        );
    await callable.call(<String, dynamic>{'token': token});
  }
}

class _PrefsFcmLocalRegistrationCache implements FcmLocalRegistrationCache {
  const _PrefsFcmLocalRegistrationCache();

  static const _tokenKey = FcmService._localTokenKey;
  static const _uidKey = FcmService._localBoundUidKey;

  @override
  Future<FcmLocalRegistration> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return FcmLocalRegistration(
        token: prefs.getString(_tokenKey),
        uid: prefs.getString(_uidKey),
      );
    } catch (_) {
      return const FcmLocalRegistration();
    }
  }

  @override
  Future<void> write(FcmLocalRegistration value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = value.token?.trim();
      final uid = value.uid?.trim();
      if (token == null || token.isEmpty) {
        await prefs.remove(_tokenKey);
      } else {
        await prefs.setString(_tokenKey, token);
      }
      if (uid == null || uid.isEmpty) {
        await prefs.remove(_uidKey);
      } else {
        await prefs.setString(_uidKey, uid);
      }
    } catch (_) {}
  }
}
