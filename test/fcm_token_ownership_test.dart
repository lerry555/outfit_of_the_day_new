import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/app_notification_router.dart';
import 'package:outfitofTheDay/Services/auth_session.dart';
import 'package:outfitofTheDay/Services/fcm_service.dart';
import 'package:outfitofTheDay/Services/shopping_wishlist_v2_service.dart';
import 'package:outfitofTheDay/Services/wishlist_notification_router.dart';
import 'package:outfitofTheDay/screens/shopping/shopping_candidate_ui.dart';

class _MemoryTokens implements FcmUserTokenRepository {
  final Map<String, List<String>> byUid = <String, List<String>>{};
  Object? removeError;
  int removeCalls = 0;
  int addCalls = 0;

  @override
  Future<void> addToken({required String uid, required String token}) async {
    addCalls++;
    final list = byUid.putIfAbsent(uid, () => <String>[]);
    if (!list.contains(token)) list.add(token);
  }

  @override
  Future<void> removeToken({required String uid, required String token}) async {
    removeCalls++;
    if (removeError != null) throw removeError!;
    byUid[uid]?.remove(token);
  }
}

class _MemoryCache implements FcmLocalRegistrationCache {
  FcmLocalRegistration value = const FcmLocalRegistration();

  @override
  Future<FcmLocalRegistration> read() async => value;

  @override
  Future<void> write(FcmLocalRegistration next) async {
    value = next;
  }
}

class _FakeMessaging implements FcmMessagingClient {
  _FakeMessaging(this.token);

  String? token;
  int permissionCalls = 0;
  int deleteCalls = 0;
  int activeRefreshListeners = 0;
  Object? deleteError;
  final StreamController<String> refresh = StreamController<String>.broadcast();

  @override
  Future<void> requestPermission() async {
    permissionCalls++;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> deleteToken() async {
    deleteCalls++;
    if (deleteError != null) throw deleteError!;
    token = 'T-after-delete';
  }

  @override
  Stream<String> get onTokenRefresh {
    return Stream<String>.multi((listener) {
      activeRefreshListeners++;
      final sub = refresh.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = () async {
        activeRefreshListeners--;
        await sub.cancel();
      };
    });
  }
}

class _StubGateway implements ShoppingWishlistV2Gateway {
  @override
  Future<List<Map<String, dynamic>>> getItems() async => const [];

  @override
  Future<Map<String, dynamic>> save(ShoppingWishlistIntent intent) async =>
      const {};

  @override
  Future<Map<String, dynamic>> update(ShoppingWishlistIntent intent) async =>
      const {};

  @override
  Future<void> remove(String variantId) async {}

  @override
  Future<Map<String, dynamic>> refreshAll({String? operationId}) async =>
      const {'status': 'OK'};

  @override
  Future<Map<String, dynamic>> refreshItem(String wishlistItemId) async =>
      const {'status': 'OK'};

  @override
  Future<Map<String, dynamic>> acknowledge(List<String> wishlistItemIds) async =>
      const {'status': 'OK'};
}

class _RecordingClaim implements FcmTokenClaimClient {
  final List<String> tokens = <String>[];
  Object? error;
  int calls = 0;

  @override
  Future<void> claim(String token) async {
    calls++;
    if (error != null) throw error!;
    tokens.add(token);
  }
}

class _RepairingClaim implements FcmTokenClaimClient {
  _RepairingClaim(this.store, this.currentUid);

  final _MemoryTokens store;
  final String? Function() currentUid;

  @override
  Future<void> claim(String token) async {
    final uid = currentUid();
    if (uid == null) return;
    for (final entry in store.byUid.entries) {
      if (entry.key == uid) continue;
      entry.value.remove(token);
    }
    final list = store.byUid.putIfAbsent(uid, () => <String>[]);
    if (!list.contains(token)) list.add(token);
  }
}

class _RecordingRouter extends AppNotificationRouter {
  _RecordingRouter()
    : super(
        isAuthenticated: () => true,
        wishlistRouter: WishlistNotificationRouter(
          navigatorKey: GlobalKey<NavigatorState>(),
          isAuthenticated: () => true,
          mayExposeCatalog: () => false,
          serviceFactory: _StubGateway.new,
        ),
      );

  int installCount = 0;
  int flushCount = 0;

  @override
  void installHandlers() {
    installCount++;
  }

  @override
  bool flushPending() {
    flushCount++;
    return false;
  }
}

void main() {
  late String? uid;
  late _MemoryTokens tokens;
  late _MemoryCache cache;
  late _FakeMessaging messaging;
  late _RecordingRouter router;
  late _RecordingClaim claim;
  late FcmService fcm;

  FcmService build({FcmTokenClaimClient? claimClient}) {
    return FcmService.forTest(
      currentUid: () => uid,
      tokens: tokens,
      messaging: messaging,
      cache: cache,
      router: router,
      claim: claimClient ?? claim,
    );
  }

  setUp(() {
    uid = 'user-a';
    tokens = _MemoryTokens();
    cache = _MemoryCache();
    messaging = _FakeMessaging('T');
    router = _RecordingRouter();
    claim = _RecordingClaim();
    fcm = build();
  });

  tearDown(() async {
    await messaging.refresh.close();
  });

  test('initial registration persists token to signed-in user A', () async {
    await fcm.init();
    expect(tokens.byUid['user-a'], ['T']);
    expect(fcm.boundUid, 'user-a');
    expect(fcm.isStarted, isTrue);
    expect(cache.value.token, 'T');
    expect(cache.value.uid, 'user-a');
    expect(router.installCount, 1);
    expect(router.flushCount, 1);
  });

  test('signed-out init does not write Firestore', () async {
    uid = null;
    await fcm.init();
    expect(tokens.byUid, isEmpty);
    expect(fcm.isStarted, isFalse);
    expect(fcm.boundUid, isNull);
    expect(router.installCount, 0);
  });

  test('same-user duplicate init keeps one refresh listener', () async {
    await fcm.init();
    await fcm.init();
    expect(messaging.activeRefreshListeners, 1);
    expect(tokens.addCalls, 1);
    expect(router.installCount, 2);
    expect(router.flushCount, 2);
    expect(tokens.byUid['user-a'], ['T']);
  });

  test('logout removes only this device token and resets service', () async {
    tokens.byUid['user-a'] = <String>['other-device', 'T'];
    await fcm.init();
    await fcm.clearLocalRegistration();
    expect(tokens.byUid['user-a'], ['other-device']);
    expect(messaging.deleteCalls, 1);
    expect(fcm.isStarted, isFalse);
    expect(fcm.boundUid, isNull);
    expect(cache.value.token, isNull);
    expect(cache.value.uid, isNull);
    expect(messaging.activeRefreshListeners, 0);
  });

  test('AuthSession signs out only after FCM cleanup', () async {
    final order = <String>[];
    final session = AuthSession(
      clearFcmRegistration: () async {
        order.add('fcm');
        await fcm.clearLocalRegistration();
      },
      signOutAuth: () async {
        order.add('auth');
        uid = null;
      },
    );
    await fcm.init();
    await session.signOut();
    expect(order, ['fcm', 'auth']);
    expect(tokens.byUid['user-a'], isEmpty);
    expect(uid, isNull);
  });

  test('Home and Profile production logout both use AuthSession.signOut', () {
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    expect(home.contains('AuthSession.instance.signOut()'), isTrue);
    expect(profile.contains('AuthSession.instance.signOut()'), isTrue);
    expect(
      home.contains('await _auth.signOut()'),
      isFalse,
      reason: 'Home production logout must not call FirebaseAuth.signOut directly',
    );
  });

  test('A → B after logout registers B and is not blocked by A _started', () async {
    await fcm.init();
    final session = AuthSession(
      clearFcmRegistration: fcm.clearLocalRegistration,
      signOutAuth: () async {
        uid = null;
      },
    );
    await session.signOut();
    expect(fcm.isStarted, isFalse);

    uid = 'user-b';
    messaging.token = 'T2';
    await fcm.init();
    expect(tokens.byUid['user-a'], isEmpty);
    expect(tokens.byUid['user-b'], ['T2']);
    expect(fcm.boundUid, 'user-b');
    expect(cache.value.uid, 'user-b');
  });

  test('uid-aware init rebinds when current user changes without no-op', () async {
    await fcm.init();
    expect(messaging.activeRefreshListeners, 1);
    uid = 'user-b';
    messaging.token = 'T-b';
    await fcm.init();
    expect(fcm.boundUid, 'user-b');
    expect(tokens.byUid['user-b'], ['T-b']);
    expect(messaging.activeRefreshListeners, 1);
    expect(tokens.byUid['user-a'], ['T']);
  });

  test('same-user refresh removes old token and stores the new one', () async {
    await fcm.init();
    messaging.refresh.add('T2');
    await Future<void>.delayed(Duration.zero);
    expect(tokens.byUid['user-a'], ['T2']);
    expect(cache.value.token, 'T2');
    expect(cache.value.uid, 'user-a');
  });

  test('stale A refresh callback does not write to B', () async {
    await fcm.init();
    uid = 'user-b';
    messaging.refresh.add('T-stale');
    await Future<void>.delayed(Duration.zero);
    expect(tokens.byUid['user-b'], isNull);
    expect(tokens.byUid['user-a'], ['T']);
  });

  test('signed-out refresh is a safe no-op', () async {
    await fcm.init();
    uid = null;
    messaging.refresh.add('T-signed-out');
    await Future<void>.delayed(Duration.zero);
    expect(tokens.byUid['user-a'], ['T']);
    expect(tokens.addCalls, 1);
  });

  test('logout Firestore failure still resets local FCM and Auth proceeds', () async {
    await fcm.init();
    tokens.removeError = Exception('offline');
    var signedOut = false;
    final session = AuthSession(
      clearFcmRegistration: fcm.clearLocalRegistration,
      signOutAuth: () async {
        signedOut = true;
        uid = null;
      },
    );
    await session.signOut();
    expect(signedOut, isTrue);
    expect(tokens.byUid['user-a'], ['T']);
    expect(messaging.deleteCalls, 1);
    expect(fcm.isStarted, isFalse);
    expect(fcm.boundUid, isNull);
    expect(cache.value.token, isNull);
  });

  test('cached token from A is not treated as B previous token', () async {
    await fcm.init();
    uid = 'user-b';
    messaging.token = 'T-b';
    await fcm.init();
    expect(tokens.byUid['user-b'], ['T-b']);
    expect(tokens.byUid['user-a'], ['T']);
  });

  test('successful init calls claim for the live token', () async {
    await fcm.init();
    expect(claim.tokens, ['T']);
    expect(claim.calls, 1);
  });

  test('claim failure does not block local registration or app start', () async {
    claim.error = Exception('offline');
    await fcm.init();
    expect(fcm.isStarted, isTrue);
    expect(fcm.boundUid, 'user-a');
    expect(tokens.byUid['user-a'], ['T']);
    expect(claim.calls, 1);
  });

  test('next init retries claim after a previous failure', () async {
    claim.error = Exception('offline');
    await fcm.init();
    expect(tokens.addCalls, 1);
    claim.error = null;
    await fcm.init();
    expect(claim.calls, 2);
    expect(claim.tokens, ['T']);
    expect(tokens.addCalls, 1);
    expect(messaging.activeRefreshListeners, 1);
  });

  test('token refresh claims the new token and not the old one', () async {
    await fcm.init();
    messaging.refresh.add('T2');
    await Future<void>.delayed(Duration.zero);
    expect(claim.tokens, ['T', 'T2']);
    expect(tokens.byUid['user-a'], ['T2']);
  });

  test('signed-out state does not call claim', () async {
    uid = null;
    await fcm.init();
    expect(claim.calls, 0);
    expect(tokens.byUid, isEmpty);
  });

  test('stale A token is repaired when B claims after failed logout', () async {
    await fcm.init();
    tokens.removeError = Exception('offline');
    messaging.deleteError = Exception('offline');
    final session = AuthSession(
      clearFcmRegistration: fcm.clearLocalRegistration,
      signOutAuth: () async {
        uid = null;
      },
    );
    await session.signOut();
    expect(tokens.byUid['user-a'], ['T']);
    expect(messaging.token, 'T');

    uid = 'user-b';
    fcm = build(claimClient: _RepairingClaim(tokens, () => uid));
    await fcm.init();
    expect(tokens.byUid['user-a'], isEmpty);
    expect(tokens.byUid['user-b'], ['T']);
    expect(fcm.boundUid, 'user-b');
  });
}
