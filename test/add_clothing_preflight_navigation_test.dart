import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/screens/add_clothing_screen.dart';

void main() {
  testWidgets('component preflight forwards saved item id instead of null', (
    tester,
  ) async {
    Object? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              captured = await Navigator.of(context).push<Object?>(
                MaterialPageRoute(
                  builder: (preflightContext) => Scaffold(
                    body: TextButton(
                      onPressed: () {
                        continueAddClothingFromPreflight(
                          navigator: Navigator.of(preflightContext),
                          formRoute: MaterialPageRoute<Object?>(
                            builder: (formContext) => Scaffold(
                              body: TextButton(
                                onPressed: () => Navigator.pop(
                                  formContext,
                                  'item-123',
                                ),
                                child: const Text('save'),
                              ),
                            ),
                          ),
                          returnItemId: true,
                        );
                      },
                      child: const Text('continue'),
                    ),
                  ),
                ),
              );
            },
            child: const Text('start'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(captured, 'item-123');
  });

  testWidgets('set capture callback uses the host Set screen context', (
    tester,
  ) async {
    BuildContext? received;
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    Future<String?> capture(
      BuildContext hostContext,
      VoidCallback onAnalyzerRequest,
    ) async {
      received = hostContext;
      onAnalyzerRequest();
      return 'item-xyz';
    }

    var tracked = 0;
    final id = await capture(host, () => tracked += 1);
    expect(id, 'item-xyz');
    expect(tracked, 1);
    expect(received, same(host));
  });

  testWidgets('single-item preflight replacement does not keep preflight', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (preflightContext) => Scaffold(
                    body: TextButton(
                      onPressed: () {
                        continueAddClothingFromPreflight(
                          navigator: Navigator.of(preflightContext),
                          formRoute: MaterialPageRoute<Object?>(
                            builder: (_) =>
                                const Scaffold(body: Text('form-only')),
                          ),
                          returnItemId: false,
                        );
                      },
                      child: const Text('continue'),
                    ),
                  ),
                ),
              );
            },
            child: const Text('start'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('continue'));
    await tester.pumpAndSettle();

    expect(find.text('form-only'), findsOneWidget);
    expect(find.text('continue'), findsNothing);
  });
}
