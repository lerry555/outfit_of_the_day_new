import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/debug/controlled_shadow_smoke.dart';

ControlledShadowSmokeController controller({
  bool debug = true,
  Future<({bool ok, String? reasonCode})> Function(String)? call,
  Future<String?> Function()? uid,
  Future<bool> Function()? appCheck,
  FreshAppCheckTokenReady? freshToken,
}) => ControlledShadowSmokeController(
  debugEnabled: debug,
  expectedUid: 'user-secret',
  itemId: 'item-secret',
  currentUid: uid ?? () async => 'user-secret',
  appCheckReady: appCheck ?? () async => true,
  freshAppCheckTokenReady: freshToken ?? () async => true,
  call: call ?? (_) async => (ok: true, reasonCode: 'shadow_ok'),
);

void main() {
  test('activate and fresh token success arms with zero calls', () async {
    var calls = 0;
    final c = controller(call: (_) async {
      calls++;
      return (ok: true, reasonCode: null);
    });
    await c.arm();
    expect(c.isArmed, true);
    expect(c.authReady, true);
    expect(c.appCheckActivationReady, true);
    expect(c.freshTokenReady, true);
    expect(calls, 0);
  });

  for (final tokenCase in <String, Future<bool> Function()>{
    'null equivalent': () async => false,
    'empty equivalent': () async => false,
    'error': () async => throw StateError('safe-token-error'),
  }.entries) {
    test('activate success, ${tokenCase.key} blocks', () async {
      var calls = 0;
      final c = controller(freshToken: tokenCase.value, call: (_) async {
        calls++;
        return (ok: true, reasonCode: null);
      });
      await c.arm();
      expect(c.state, ControlledSmokeState.blocked);
      expect(c.reasonCode, 'app_check_token_unavailable');
      expect(c.freshTokenReady, false);
      expect(calls, 0);
    });
  }

  test('auth null invokes neither token nor callable', () async {
    var tokens = 0;
    var calls = 0;
    final c = controller(
      uid: () async => null,
      freshToken: () async { tokens++; return true; },
      call: (_) async { calls++; return (ok: true, reasonCode: null); },
    );
    await c.arm();
    expect(tokens, 0);
    expect(calls, 0);
  });

  test('fresh token immediately before fire invokes callable once', () async {
    var tokens = 0;
    var calls = 0;
    final c = controller(
      freshToken: () async { tokens++; return true; },
      call: (_) async { calls++; return (ok: true, reasonCode: 'shadow_ok'); },
    );
    await c.arm();
    await c.fire();
    expect(tokens, 2);
    expect(calls, 1);
    expect(c.state, ControlledSmokeState.completed);
  });

  test('token absent at fire locks and invokes callable zero times', () async {
    var tokens = 0;
    var calls = 0;
    final c = controller(
      freshToken: () async => ++tokens == 1,
      call: (_) async { calls++; return (ok: true, reasonCode: null); },
    );
    await c.arm();
    await c.fire();
    expect(calls, 0);
    expect(c.hasFired, true);
    expect(c.state, ControlledSmokeState.failed);
    expect(c.reasonCode, 'app_check_token_unavailable');
  });

  test('token error at fire has no retry', () async {
    var tokens = 0;
    var calls = 0;
    final c = controller(
      freshToken: () async {
        if (++tokens == 1) return true;
        throw StateError('not-exposed');
      },
      call: (_) async { calls++; return (ok: true, reasonCode: null); },
    );
    await c.arm();
    await c.fire();
    expect(tokens, 2);
    expect(calls, 0);
    expect(c.reasonCode, 'app_check_token_unavailable');
  });

  test('callable failure has no retry', () async {
    var calls = 0;
    final c = controller(call: (_) async {
      calls++;
      return (ok: false, reasonCode: 'unavailable');
    });
    await c.arm();
    await c.fire();
    expect(calls, 1);
    expect(c.hasFired, true);
  });

  test('concurrent and second fire add no calls', () async {
    var calls = 0;
    final gate = Completer<({bool ok, String? reasonCode})>();
    final c = controller(call: (_) { calls++; return gate.future; });
    await c.arm();
    final first = c.fire();
    final second = c.fire();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    gate.complete((ok: true, reasonCode: 'shadow_ok'));
    await Future.wait([first, second]);
    await c.fire();
    expect(calls, 1);
  });

  test('token never enters callable payload or visible state', () async {
    String? received;
    final c = controller(call: (itemId) async {
      received = itemId;
      return (ok: true, reasonCode: null);
    });
    await c.arm();
    await c.fire();
    expect(received, 'item-secret');
    expect(c.reasonCode, isNot(contains('token-secret')));
  });

  test('debug gate false and rebuild-style reads never fire', () async {
    var calls = 0;
    final c = controller(debug: false, call: (_) async {
      calls++;
      return (ok: true, reasonCode: null);
    });
    await c.arm();
    for (var i = 0; i < 10; i++) {
      c.uidFingerprint;
      c.itemFingerprint;
      c.notifyListeners();
    }
    await c.fire();
    expect(calls, 0);
    expect(c.state, ControlledSmokeState.inactive);
  });

  test('owner or activation mismatch blocks without token or call', () async {
    var tokens = 0;
    var calls = 0;
    final wrongOwner = controller(
      uid: () async => 'other',
      freshToken: () async { tokens++; return true; },
      call: (_) async { calls++; return (ok: true, reasonCode: null); },
    );
    final noActivation = controller(
      appCheck: () async => false,
      freshToken: () async { tokens++; return true; },
      call: (_) async { calls++; return (ok: true, reasonCode: null); },
    );
    await wrongOwner.arm();
    await noActivation.arm();
    expect(tokens, 0);
    expect(calls, 0);
  });
}
