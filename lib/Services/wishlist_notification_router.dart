import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:outfitofTheDay/Services/shopping_wishlist_v2_service.dart';

import '../app/app_router.dart';
import '../models/shopping_ui_feature_flags.dart';
import '../screens/shopping/shopping_wishlist_v2_screen.dart';

enum WishlistNotificationRouteType { item, list }

class WishlistNotificationRoute {
  const WishlistNotificationRoute.item(this.wishlistItemId)
    : type = WishlistNotificationRouteType.item;

  const WishlistNotificationRoute.list()
    : type = WishlistNotificationRouteType.list,
      wishlistItemId = null;

  final WishlistNotificationRouteType type;
  final String? wishlistItemId;
}

/// Opens only typed Wishlist V2 notification payloads. Never legacy wishlist or URLs.
class WishlistNotificationRouter {
  WishlistNotificationRouter({
    GlobalKey<NavigatorState>? navigatorKey,
    bool Function()? isAuthenticated,
    bool Function()? mayExposeCatalog,
    ShoppingWishlistV2Gateway Function()? serviceFactory,
  }) : _navigatorKey = navigatorKey ?? rootNavigatorKey,
       _isAuthenticated =
           isAuthenticated ??
           (() => FirebaseAuth.instance.currentUser != null),
       _mayExposeCatalog =
           mayExposeCatalog ?? (() => ShoppingUiFeatureFlags.mayExposeWishlistV2),
       _serviceFactory = serviceFactory ?? ShoppingWishlistV2Service.new;

  static final WishlistNotificationRouter instance =
      WishlistNotificationRouter();

  final GlobalKey<NavigatorState> _navigatorKey;
  final bool Function() _isAuthenticated;
  final bool Function() _mayExposeCatalog;
  final ShoppingWishlistV2Gateway Function() _serviceFactory;

  WishlistNotificationRoute? _pending;
  bool _handlersInstalled = false;

  @visibleForTesting
  WishlistNotificationRoute? get pendingRoute => _pending;

  void installHandlers() {
    if (_handlersInstalled) return;
    _handlersInstalled = true;
    FirebaseMessaging.onMessageOpenedApp.listen(_onRemoteMessage);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _onRemoteMessage(message);
    });
  }

  void handleRemoteMessage(RemoteMessage message) => _onRemoteMessage(message);

  /// Parses FCM data maps (values are typically strings).
  WishlistNotificationRoute? parseData(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    if (type == 'WISHLIST_V2_ITEM') {
      final id = data['wishlistItemId']?.toString().trim() ?? '';
      if (id.isEmpty) return null;
      return WishlistNotificationRoute.item(id);
    }
    if (type == 'WISHLIST_V2_LIST') {
      return const WishlistNotificationRoute.list();
    }
    return null;
  }

  void enqueue(WishlistNotificationRoute route) {
    _pending = route;
  }

  /// Attempts navigation when auth, navigator, and SHOP-014 gate are ready.
  bool flushPending() {
    final route = _pending;
    if (route == null) return false;
    if (!_isAuthenticated()) return false;
    if (_navigatorKey.currentState == null) return false;
    if (!_mayExposeCatalog()) {
      // Keep pending until catalog exposure is allowed (SHOP-014).
      return false;
    }
    _pending = null;
    return _open(route);
  }

  void handleData(Map<String, dynamic> data) {
    final route = parseData(data);
    if (route == null) return;
    if (!_isAuthenticated() ||
        _navigatorKey.currentState == null ||
        !_mayExposeCatalog()) {
      enqueue(route);
      flushPending();
      return;
    }
    _open(route);
  }

  void _onRemoteMessage(RemoteMessage message) {
    handleData(Map<String, dynamic>.from(message.data));
  }

  bool _open(WishlistNotificationRoute route) {
    final nav = _navigatorKey.currentState;
    if (nav == null) return false;
    if (!_mayExposeCatalog()) {
      enqueue(route);
      return false;
    }
    try {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ShoppingWishlistV2Screen(
            service: _serviceFactory(),
            initialWishlistItemId:
                route.type == WishlistNotificationRouteType.item
                ? route.wishlistItemId
                : null,
          ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Wishlist notification open error: $e');
      enqueue(route);
      return false;
    }
  }

  @visibleForTesting
  void resetForTest() {
    _pending = null;
    _handlersInstalled = false;
  }
}
