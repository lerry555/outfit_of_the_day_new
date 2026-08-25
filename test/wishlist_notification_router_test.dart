import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/shopping_wishlist_v2_service.dart';
import 'package:outfitofTheDay/Services/wishlist_notification_router.dart';
import 'package:outfitofTheDay/screens/shopping/shopping_candidate_ui.dart';
import 'package:outfitofTheDay/screens/shopping/shopping_wishlist_v2_screen.dart';

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

void main() {
  late GlobalKey<NavigatorState> navKey;
  late bool authenticated;
  late bool exposeCatalog;
  late WishlistNotificationRouter router;

  setUp(() {
    navKey = GlobalKey<NavigatorState>();
    authenticated = true;
    exposeCatalog = true;
    router = WishlistNotificationRouter(
      navigatorKey: navKey,
      isAuthenticated: () => authenticated,
      mayExposeCatalog: () => exposeCatalog,
      serviceFactory: _StubGateway.new,
    );
  });

  tearDown(() {
    router.resetForTest();
  });

  testWidgets('opens item route with initialWishlistItemId', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('home')),
      ),
    );

    router.handleData({
      'type': 'WISHLIST_V2_ITEM',
      'wishlistItemId': 'wish_42',
      'url': 'https://evil.example',
    });
    await tester.pumpAndSettle();

    expect(find.byType(ShoppingWishlistV2Screen), findsOneWidget);
    final screen = tester.widget<ShoppingWishlistV2Screen>(
      find.byType(ShoppingWishlistV2Screen),
    );
    expect(screen.initialWishlistItemId, 'wish_42');
  });

  testWidgets('opens list route without item id', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('home')),
      ),
    );

    router.handleData({'type': 'WISHLIST_V2_LIST'});
    await tester.pumpAndSettle();

    final screen = tester.widget<ShoppingWishlistV2Screen>(
      find.byType(ShoppingWishlistV2Screen),
    );
    expect(screen.initialWishlistItemId, isNull);
  });

  test('ignores legacy and arbitrary payloads', () {
    expect(router.parseData({'type': 'legacy_wishlist'}), isNull);
    expect(router.parseData({'type': 'WISHLIST_V2_GROUP'}), isNull);
    expect(
      router.parseData({
        'type': 'WISHLIST_V2_ITEM',
        'wishlistItemId': '',
      }),
      isNull,
    );
    expect(router.parseData({'url': 'https://example.com'}), isNull);
  });

  testWidgets('stores pending until auth and nav are ready', (tester) async {
    authenticated = false;
    router.handleData({
      'type': 'WISHLIST_V2_ITEM',
      'wishlistItemId': 'wish_pending',
    });
    expect(router.pendingRoute, isNotNull);
    expect(router.pendingRoute!.wishlistItemId, 'wish_pending');

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('home')),
      ),
    );
    authenticated = true;
    expect(router.flushPending(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingWishlistV2Screen), findsOneWidget);
    expect(router.pendingRoute, isNull);
  });

  testWidgets('keeps pending when SHOP-014 catalog gate is closed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('home')),
      ),
    );
    exposeCatalog = false;
    router.handleData({'type': 'WISHLIST_V2_LIST'});
    expect(router.pendingRoute, isNotNull);
    expect(find.byType(ShoppingWishlistV2Screen), findsNothing);

    expect(router.flushPending(), isFalse);
    exposeCatalog = true;
    expect(router.flushPending(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingWishlistV2Screen), findsOneWidget);
  });
}
