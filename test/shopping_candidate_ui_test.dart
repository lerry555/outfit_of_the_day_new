import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/screens/shopping/shopping_candidate_ui.dart';

Map<String, dynamic> fixture({
  bool available = true,
  bool stale = false,
  String? coupon,
  String title =
      'Veľmi dlhý názov tmavomodrej mikiny pre overenie responzívneho rozloženia',
}) => {
  'variantId': 'fixture-v1',
  'displayName': title,
  'brand': 'Fixture',
  'exactColorName': 'Tmavomodrá',
  'effectivePublicPrice': {
    'price': {'amountMinor': 4599, 'currency': 'EUR'},
    ...?(coupon == null ? null : {'couponCode': coupon}),
  },
  'selectedSizeEvidence': {
    'selectedSizeKey': 'M',
    'purchasableForSelectedSize': available,
  },
  'freshnessEvidence': {'stale': stale},
  'primaryOffer': {
    'offerId': 'offer-a',
    'store': {'partnerId': 'store-a', 'displayName': 'Store A'},
    'url': 'https://fixture.test/item',
    'regularPrice': {'amountMinor': 5999, 'currency': 'EUR'},
    'salePrice': {'amountMinor': 4599, 'currency': 'EUR'},
    'effectivePrice': {
      'price': {'amountMinor': 4599, 'currency': 'EUR'},
      ...?(coupon == null ? null : {'couponCode': coupon}),
    },
    'selectedSizes': [
      {
        'normalizedSizeKey': 'M',
        'displayLabel': 'M',
        'availability': available ? 'AVAILABLE' : 'UNAVAILABLE',
        'reliableQuantity': available ? 3 : null,
      },
    ],
    'freshness': {
      'stale': stale,
      'priceVerifiedAt': '2026-08-15T10:00:00.000Z',
      'availabilityVerifiedAt': '2026-08-15T09:00:00.000Z',
    },
  },
  'alternativeOffers': [
    {
      'offerId': 'offer-b',
      'store': {'partnerId': 'store-b', 'displayName': 'Store B'},
      'url': 'https://fixture-b.test/item',
      'regularPrice': {'amountMinor': 4999, 'currency': 'EUR'},
      'effectivePrice': {
        'price': {'amountMinor': 4999, 'currency': 'EUR'},
      },
      'selectedSizes': [
        {
          'normalizedSizeKey': 'M',
          'displayLabel': 'M',
          'availability': 'UNKNOWN',
        },
      ],
      'freshness': {'stale': false},
    },
  ],
};

void main() {
  testWidgets('candidate card shows coupon and honest unavailable size', (
    tester,
  ) async {
    final candidate = ShoppingCandidateData.fromServer(
      fixture(available: false, coupon: 'FIXTURE10'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShoppingCandidateCard(candidate: candidate)),
      ),
    );

    expect(find.text('s kódom FIXTURE10'), findsOneWidget);
    expect(find.textContaining('M — momentálne nedostupná'), findsOneWidget);
    expect(find.text('45,99 €'), findsOneWidget);
    expect(find.text('59,99 €'), findsOneWidget);
    expect(find.text('Store A'), findsOneWidget);
  });

  testWidgets('unknown availability is distinct from unavailable', (
    tester,
  ) async {
    final raw = fixture();
    (raw['selectedSizeEvidence'] as Map).remove('purchasableForSelectedSize');
    ((((raw['primaryOffer'] as Map)['selectedSizes'] as List).first)
            as Map)['availability'] =
        'UNKNOWN';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShoppingCandidateCard(
            candidate: ShoppingCandidateData.fromServer(raw),
          ),
        ),
      ),
    );
    expect(find.textContaining('neoverená dostupnosť'), findsOneWidget);
  });

  testWidgets('results preserve input rank and show known exact count', (
    tester,
  ) async {
    final candidates = List.generate(
      37,
      (index) =>
          ShoppingCandidateData.fromServer(fixture(title: 'Mikina $index')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingResultsScreen(
          candidates: candidates,
          isComplete: true,
          exactResultCount: 37,
          onCandidate: (_) {},
          onWishlist: (_) {},
        ),
      ),
    );
    expect(find.text('Našiel som 37 vhodných kúskov.'), findsOneWidget);
    expect(find.text('🥇'), findsOneWidget);
    expect(find.text('Mikina 0'), findsOneWidget);
  });

  testWidgets(
    'wishlist editor requires target price and has no low-stock option',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShoppingWishlistEditor(
              candidate: ShoppingCandidateData.fromServer(fixture()),
              onDismissed: () {},
              onSave: (_) async {},
            ),
          ),
        ),
      );
      expect(find.text('Sledovať cenu'), findsOneWidget);
      expect(find.text('Sledovať dostupnosť veľkosti'), findsOneWidget);
      expect(
        find.textContaining('low stock', findRichText: true),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Uložiť'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '20');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Uložiť'))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('low stock and separate freshness are factual UI only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShoppingCandidateCard(
            candidate: ShoppingCandidateData.fromServer(fixture()),
          ),
        ),
      ),
    );
    expect(find.textContaining('posledné 3 ks'), findsOneWidget);
    expect(find.textContaining('Cena '), findsOneWidget);
    expect(find.textContaining('Dostupnosť '), findsOneWidget);
    expect(find.textContaining('Sledovať low stock'), findsNothing);
  });

  testWidgets('detail renders alternatives and exact Visit Store callback', (
    tester,
  ) async {
    String? visited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShoppingCandidateDetailSheet(
            candidate: ShoppingCandidateData.fromServer(fixture()),
            onWishlist: () {},
            onVisitStore: (url) => visited = url,
          ),
        ),
      ),
    );
    expect(find.text('Dostupné aj v ďalších obchodoch'), findsOneWidget);
    expect(find.text('Store B'), findsOneWidget);
    final visit = find.text('Navštíviť obchod');
    await tester.ensureVisible(visit);
    await tester.tap(visit);
    expect(visited, 'https://fixture.test/item');
  });

  testWidgets('wishlist save waits for server confirmation before closing', (
    tester,
  ) async {
    final completion = Completer<void>();
    var dismissed = false;
    var saveStarted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShoppingWishlistEditor(
            candidate: ShoppingCandidateData.fromServer(fixture()),
            onDismissed: () => dismissed = true,
            onSave: (_) {
              saveStarted = true;
              return completion.future;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '20');
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Uložiť');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(saveStarted, true);
    expect(dismissed, false);
    completion.complete();
    await tester.pump();
    expect(dismissed, true);
  });
}
