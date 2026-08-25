import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/app_notification_router.dart';
import 'package:outfitofTheDay/Services/shopping_wishlist_v2_service.dart';
import 'package:outfitofTheDay/Services/stylist_notification_intent.dart';
import 'package:outfitofTheDay/Services/wishlist_notification_router.dart';
import 'package:outfitofTheDay/screens/main_navigation.dart';
import 'package:outfitofTheDay/screens/shopping/shopping_candidate_ui.dart';
import 'package:outfitofTheDay/screens/shopping/shopping_wishlist_v2_screen.dart';
import 'package:outfitofTheDay/screens/stylist_chat_screen.dart';

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

class _FakeShell extends StatefulWidget {
  const _FakeShell({required this.router});

  final AppNotificationRouter router;

  @override
  State<_FakeShell> createState() => _FakeShellState();
}

class _FakeShellState extends State<_FakeShell> {
  int stackIndex = 0;
  int stylistSelectCount = 0;
  final activated = <int>{0};

  @override
  void initState() {
    super.initState();
    widget.router.attachStylistTabSink(_onStylist);
  }

  @override
  void dispose() {
    widget.router.detachStylistTabSink();
    super.dispose();
  }

  void _onStylist(StylistNotificationIntent intent) {
    stylistSelectCount += 1;
    setState(() {
      activated.add(kStylistIndexedStackIndex);
      stackIndex = kStylistIndexedStackIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: stackIndex,
        children: [
          const Text('home-tab'),
          const Text('wardrobe-tab'),
          activated.contains(kStylistIndexedStackIndex)
              ? const Text('stylist-tab')
              : const SizedBox.shrink(),
        ],
      ),
    );
  }
}

void main() {
  late GlobalKey<NavigatorState> navKey;
  late bool authenticated;
  late bool exposeCatalog;
  late WishlistNotificationRouter wishlist;
  late AppNotificationRouter router;
  late List<StylistNotificationIntent> stylistSelects;

  setUp(() {
    navKey = GlobalKey<NavigatorState>();
    authenticated = true;
    exposeCatalog = true;
    stylistSelects = <StylistNotificationIntent>[];
    wishlist = WishlistNotificationRouter(
      navigatorKey: navKey,
      isAuthenticated: () => authenticated,
      mayExposeCatalog: () => exposeCatalog,
      serviceFactory: _StubGateway.new,
    );
    router = AppNotificationRouter(
      wishlistRouter: wishlist,
      isAuthenticated: () => authenticated,
      onSelectStylistTab: stylistSelects.add,
    );
  });

  tearDown(() {
    router.resetForTest();
    wishlist.resetForTest();
  });

  group('stylist recognition and parsing', () {
    test('stylist_reply is parsed as a Stylist intent', () {
      final intent = AppNotificationRouter.parseStylistIntent({
        'type': 'stylist_reply',
        'jobId': 'job-1',
        'chatId': 'chat-9',
      });
      expect(intent, isNotNull);
      expect(intent!.jobId, 'job-1');
      expect(intent.chatId, 'chat-9');
      expect(intent.dedupeKey, 'stylist_reply|job-1|chat-9');
    });

    test('empty jobId and chatId still route and are stored as null', () {
      final intent = AppNotificationRouter.parseStylistIntent({
        'type': 'stylist_reply',
        'jobId': '',
        'chatId': '   ',
      });
      expect(intent, isNotNull);
      expect(intent!.jobId, isNull);
      expect(intent.chatId, isNull);

      router.handleData({'type': 'stylist_reply', 'jobId': '', 'chatId': ''});
      expect(stylistSelects, hasLength(1));
      expect(stylistSelects.single.jobId, isNull);
      expect(stylistSelects.single.chatId, isNull);
    });

    test('unknown type is a safe no-op', () {
      expect(AppNotificationRouter.parseStylistIntent({'type': 'other'}), isNull);
      router.handleData({'type': 'legacy_wishlist'});
      expect(stylistSelects, isEmpty);
      expect(wishlist.pendingRoute, isNull);
    });
  });

  group('wishlist isolation', () {
    testWidgets('WISHLIST_V2_ITEM still opens the Wishlist screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Text('home')),
        ),
      );
      router.handleData({
        'type': 'WISHLIST_V2_ITEM',
        'wishlistItemId': 'wish_42',
      });
      await tester.pumpAndSettle();
      expect(find.byType(ShoppingWishlistV2Screen), findsOneWidget);
      expect(stylistSelects, isEmpty);
    });

    testWidgets('WISHLIST_V2_LIST still opens the Wishlist list', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Text('home')),
        ),
      );
      router.handleData({'type': 'WISHLIST_V2_LIST'});
      await tester.pumpAndSettle();
      expect(find.byType(ShoppingWishlistV2Screen), findsOneWidget);
      expect(stylistSelects, isEmpty);
    });

    testWidgets('stylist_reply does not open Wishlist', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Text('home')),
        ),
      );
      router.handleData({
        'type': 'stylist_reply',
        'jobId': 'job-1',
        'chatId': 'chat-1',
      });
      await tester.pumpAndSettle();
      expect(find.byType(ShoppingWishlistV2Screen), findsNothing);
      expect(stylistSelects, hasLength(1));
    });
  });

  group('shopping flags and auth', () {
    test('stylist_reply still routes when Shopping/Wishlist gate is closed', () {
      exposeCatalog = false;
      router.handleData({
        'type': 'stylist_reply',
        'jobId': 'job-shop-off',
        'chatId': 'chat-shop-off',
      });
      expect(stylistSelects, hasLength(1));
      expect(stylistSelects.single.jobId, 'job-shop-off');
      expect(wishlist.pendingRoute, isNull);
    });

    test('signed out does not deliver Stylist navigation', () {
      authenticated = false;
      router.handleData({
        'type': 'stylist_reply',
        'jobId': 'job-auth',
        'chatId': 'chat-auth',
      });
      expect(stylistSelects, isEmpty);
      expect(router.pendingStylistIntent, isNotNull);
      expect(router.pendingStylistIntent!.jobId, 'job-auth');
    });
  });

  group('pending intent', () {
    test('retains until shell is ready, then delivers once and clears', () {
      final pendingRouter = AppNotificationRouter(
        wishlistRouter: wishlist,
        isAuthenticated: () => authenticated,
      );
      pendingRouter.handleData({
        'type': 'stylist_reply',
        'jobId': 'job-pending',
        'chatId': 'chat-pending',
      });
      expect(pendingRouter.pendingStylistIntent, isNotNull);
      expect(stylistSelects, isEmpty);

      pendingRouter.attachStylistTabSink(stylistSelects.add);
      expect(stylistSelects, hasLength(1));
      expect(stylistSelects.single.jobId, 'job-pending');
      expect(stylistSelects.single.chatId, 'chat-pending');
      expect(pendingRouter.pendingStylistIntent, isNull);
      expect(
        pendingRouter.lastDeliveredStylistIntent?.jobId,
        'job-pending',
      );

      pendingRouter.flushPending();
      expect(stylistSelects, hasLength(1));
      pendingRouter.resetForTest();
    });

    test('duplicate type+jobId+chatId does not re-select the tab', () {
      final data = {
        'type': 'stylist_reply',
        'jobId': 'job-dup',
        'chatId': 'chat-dup',
      };
      router.handleData(data);
      router.handleData(data);
      expect(stylistSelects, hasLength(1));
      expect(
        StylistNotificationIntentStore.instance.current?.jobId,
        'job-dup',
      );
    });
  });

  group('tab selection shell', () {
    testWidgets(
      'selects existing Stylist tab without pushing StylistChatScreen',
      (tester) async {
        final shellRouter = AppNotificationRouter(
          wishlistRouter: wishlist,
          isAuthenticated: () => true,
        );
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            home: _FakeShell(router: shellRouter),
          ),
        );
        shellRouter.handleData({
          'type': 'stylist_reply',
          'jobId': 'job-tab',
          'chatId': 'chat-tab',
        });
        await tester.pump();

        expect(find.text('stylist-tab'), findsOneWidget);
        expect(find.byType(StylistChatScreen), findsNothing);
        expect(navKey.currentState!.canPop(), isFalse);
        expect(kStylistIndexedStackIndex, 2);
        expect(kStylistBottomBarIndex, 3);

        final state = tester.state<_FakeShellState>(find.byType(_FakeShell));
        expect(state.stackIndex, kStylistIndexedStackIndex);
        expect(state.stylistSelectCount, 1);

        shellRouter.handleData({
          'type': 'stylist_reply',
          'jobId': 'job-tab',
          'chatId': 'chat-tab',
        });
        await tester.pump();
        expect(state.stylistSelectCount, 1);
        expect(find.text('stylist-tab'), findsOneWidget);
        expect(navKey.currentState!.canPop(), isFalse);
        shellRouter.resetForTest();
      },
    );
  });

  test('background/terminated tap contract uses the same handleData path', () {
    router.handleData({
      'type': 'stylist_reply',
      'jobId': 'job-fcm',
      'chatId': 'chat-fcm',
    });
    expect(stylistSelects, hasLength(1));
    expect(stylistSelects.single.dedupeKey, 'stylist_reply|job-fcm|chat-fcm');
  });
}
