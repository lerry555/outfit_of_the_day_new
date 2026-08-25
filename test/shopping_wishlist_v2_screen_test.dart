import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/shopping_wishlist_v2_service.dart';
import 'package:outfitofTheDay/screens/shopping/shopping_candidate_ui.dart';
import 'package:outfitofTheDay/screens/shopping/shopping_wishlist_v2_screen.dart';

class _FakeGateway implements ShoppingWishlistV2Gateway {
  var updateCount = 0;
  var removeCount = 0;
  var refreshAllCount = 0;
  var acknowledgeCount = 0;
  List<String> acknowledgedIds = const [];
  var removed = false;
  Completer<void>? refreshBlocker;
  List<Map<String, dynamic>> items;

  _FakeGateway({List<Map<String, dynamic>>? items})
    : items = items ?? [_baseItem()];

  @override
  Future<List<Map<String, dynamic>>> getItems() async =>
      removed ? const [] : List<Map<String, dynamic>>.from(items);

  @override
  Future<Map<String, dynamic>> save(ShoppingWishlistIntent intent) async =>
      items.first;

  @override
  Future<Map<String, dynamic>> update(ShoppingWishlistIntent intent) async {
    updateCount++;
    return items.first;
  }

  @override
  Future<void> remove(String variantId) async {
    removeCount++;
    removed = true;
  }

  @override
  Future<Map<String, dynamic>> refreshAll({String? operationId}) async {
    refreshAllCount++;
    final blocker = refreshBlocker;
    if (blocker != null) await blocker.future;
    return const {'status': 'OK'};
  }

  @override
  Future<Map<String, dynamic>> refreshItem(String wishlistItemId) async =>
      const {'status': 'OK'};

  @override
  Future<Map<String, dynamic>> acknowledge(List<String> wishlistItemIds) async {
    acknowledgeCount++;
    acknowledgedIds = List<String>.from(wishlistItemIds);
    items = items
        .map((item) {
          if (!wishlistItemIds.contains(item['wishlistItemId'])) return item;
          final tracking = Map<String, dynamic>.from(
            item['tracking'] as Map? ?? const {},
          );
          tracking['highlightState'] = 'NONE';
          tracking['highlight'] = {
            'state': 'ACKNOWLEDGED',
          };
          tracking['sortTier'] = tracking['lowStockState'] == 'LOW_STOCK'
              ? 1
              : 2;
          return {...item, 'tracking': tracking};
        })
        .toList(growable: false);
    return {'status': 'OK', 'acknowledged': wishlistItemIds.length};
  }

  static Map<String, dynamic> _baseItem({
    String wishlistItemId = 'wish_1',
    String variantId = 'v1',
    String title = 'Mikina',
    String highlightState = 'NONE',
    String lowStockState = 'NORMAL',
    int sortTier = 2,
    int sortEventAt = 0,
    int updatedAt = 1,
  }) {
    return <String, dynamic>{
      'wishlistItemId': wishlistItemId,
      'variantId': variantId,
      'selectedSizes': ['M'],
      'preferredSize': 'M',
      'targetPrice': {'amountMinor': 2000, 'currency': 'EUR'},
      'priceMonitoringEnabled': true,
      'sizeMonitoringEnabled': true,
      'updatedAt': updatedAt,
      'tracking': {
        'evaluatedPriceState': 'SATISFIED',
        'highlightState': highlightState,
        'highlight': {
          'state': highlightState == 'GOLD' ? 'UNACKNOWLEDGED' : 'NONE',
        },
        'lowStockState': lowStockState,
        'lifecycleState': 'ACTIVE',
        'sortTier': sortTier,
        'sortEventAt': sortEventAt,
        'freshness': {
          'stale': false,
          'priceVerifiedAt': '2026-08-15T10:00:00.000Z',
          'availabilityVerifiedAt': '2026-08-15T10:05:00.000Z',
        },
      },
      'currentCatalogProjection': {
        'candidate': {
          'variantId': variantId,
          'displayName': title,
          'brand': 'Brand',
          'exactColorName': 'Navy',
          'primaryOffer': {
            'offerId': 'o1',
            'store': {'partnerId': 'p1', 'displayName': 'Store'},
            'regularPrice': {'amountMinor': 1800, 'currency': 'EUR'},
            'effectivePrice': {
              'price': {'amountMinor': 1800, 'currency': 'EUR'},
            },
            'url': 'https://store.example/item',
            'selectedSizes': [
              {
                'normalizedSizeKey': 'M',
                'displayLabel': 'M',
                'availability': 'AVAILABLE',
              },
            ],
            'freshness': {'stale': false},
          },
        },
      },
    };
  }
}

void main() {
  testWidgets('persisted Wishlist screen edits and removes V2 items', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingWishlistV2Screen(
          service: gateway,
          forceCatalogExposure: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Mikina'), findsOneWidget);
    expect(find.text('Cieľ: 20,00 €'), findsOneWidget);
    expect(find.text('Aktuálny stav ceny: cieľ splnený'), findsOneWidget);

    await tester.tap(find.text('Upraviť'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Upraviť');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(gateway.updateCount, 1);

    await tester.tap(find.text('Odstrániť'));
    await tester.pumpAndSettle();
    expect(gateway.removeCount, 1);
    expect(find.text('Wishlist je zatiaľ prázdny.'), findsOneWidget);
  });

  testWidgets('closed when catalog gate is off', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      MaterialApp(home: ShoppingWishlistV2Screen(service: gateway)),
    );
    await tester.pump();
    expect(find.text('Wishlist momentálne nie je dostupný.'), findsOneWidget);
    expect(find.text('Mikina'), findsNothing);
    expect(find.text('Aktualizovať všetko'), findsNothing);
  });

  testWidgets('gold card styling and Rozumiem acknowledges', (tester) async {
    final gateway = _FakeGateway(
      items: [
        _FakeGateway._baseItem(
          wishlistItemId: 'wish_gold',
          highlightState: 'GOLD',
          sortTier: 0,
          sortEventAt: 100,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingWishlistV2Screen(
          service: gateway,
          forceCatalogExposure: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Nová zmena'), findsOneWidget);
    expect(find.text('Rozumiem'), findsOneWidget);
    expect(gateway.acknowledgeCount, 0);

    await tester.tap(find.text('Rozumiem'));
    await tester.pumpAndSettle();
    expect(gateway.acknowledgeCount, 1);
    expect(gateway.acknowledgedIds, ['wish_gold']);
    expect(find.text('Nová zmena'), findsNothing);
  });

  testWidgets('refresh all has in-flight protection', (tester) async {
    final gateway = _FakeGateway()..refreshBlocker = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingWishlistV2Screen(
          service: gateway,
          forceCatalogExposure: true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('wishlist_refresh_all')));
    await tester.pump();
    expect(gateway.refreshAllCount, 1);

    await tester.tap(find.byKey(const Key('wishlist_refresh_all')));
    await tester.pump();
    expect(gateway.refreshAllCount, 1);

    gateway.refreshBlocker!.complete();
    await tester.pumpAndSettle();
    expect(gateway.refreshAllCount, 1);
  });

  testWidgets('acknowledges session-seen gold on leave', (tester) async {
    final gateway = _FakeGateway(
      items: [
        _FakeGateway._baseItem(
          wishlistItemId: 'wish_gold',
          highlightState: 'GOLD',
          sortTier: 0,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ShoppingWishlistV2Screen(
                    service: gateway,
                    forceCatalogExposure: true,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Nová zmena'), findsOneWidget);
    expect(gateway.acknowledgeCount, 0);

    Navigator.of(tester.element(find.text('Nová zmena'))).pop();
    await tester.pumpAndSettle();
    expect(gateway.acknowledgeCount, 1);
    expect(gateway.acknowledgedIds, ['wish_gold']);
  });

  test('client-side ordering prefers GOLD then LOW_STOCK then recency', () {
    final items = sortWishlistItemsClientSide([
      ShoppingWishlistItemData.fromServer(
        _FakeGateway._baseItem(
          wishlistItemId: 'normal',
          title: 'Normal',
          sortTier: 2,
          updatedAt: 50,
        ),
      ),
      ShoppingWishlistItemData.fromServer(
        _FakeGateway._baseItem(
          wishlistItemId: 'low',
          title: 'Low',
          lowStockState: 'LOW_STOCK',
          sortTier: 1,
          updatedAt: 10,
        ),
      ),
      ShoppingWishlistItemData.fromServer(
        _FakeGateway._baseItem(
          wishlistItemId: 'gold_old',
          title: 'Gold old',
          highlightState: 'GOLD',
          sortTier: 0,
          sortEventAt: 1,
          updatedAt: 1,
        ),
      ),
      ShoppingWishlistItemData.fromServer(
        _FakeGateway._baseItem(
          wishlistItemId: 'gold_new',
          title: 'Gold new',
          highlightState: 'GOLD',
          sortTier: 0,
          sortEventAt: 9,
          updatedAt: 9,
        ),
      ),
    ]);
    expect(
      items.map((item) => item.wishlistItemId).toList(),
      ['gold_new', 'gold_old', 'low', 'normal'],
    );
  });
}
