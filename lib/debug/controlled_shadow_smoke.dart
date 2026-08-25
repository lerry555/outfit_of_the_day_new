/// Debug-only manually fired controlled-shadow smoke harness.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../Services/firebase_app_check_bootstrap.dart';
import '../Services/wardrobe_qualification_authority_client.dart';

enum ControlledSmokeState { inactive, arming, armed, fired, completed, failed, blocked }

typedef SmokeCall = Future<({bool ok, String? reasonCode})> Function(String itemId);
typedef FreshAppCheckTokenReady = Future<bool> Function();

class ControlledShadowSmokeController extends ChangeNotifier {
  ControlledShadowSmokeController({required this.debugEnabled,
    required this.expectedUid, required this.itemId, required this.currentUid,
    required this.appCheckReady, required this.freshAppCheckTokenReady,
    required this.call});

  final bool debugEnabled;
  final String expectedUid;
  final String itemId;
  final Future<String?> Function() currentUid;
  final Future<bool> Function() appCheckReady;
  final FreshAppCheckTokenReady freshAppCheckTokenReady;
  final SmokeCall call;
  ControlledSmokeState state = ControlledSmokeState.inactive;
  String? reasonCode;
  String? _verifiedUid;
  bool _fired = false;
  bool authReady = false;
  bool appCheckActivationReady = false;
  bool freshTokenReady = false;

  bool get isArmed => state == ControlledSmokeState.armed;
  bool get hasFired => _fired;
  String get uidFingerprint => _fingerprint(_verifiedUid ?? expectedUid);
  String get itemFingerprint => _fingerprint(itemId);

  Future<void> arm() async {
    if (!debugEnabled || _fired) return;
    state = ControlledSmokeState.arming; reasonCode = null; notifyListeners();
    final uid = await currentUid();
    if (uid == null || uid != expectedUid || itemId.trim().isEmpty) {
      state = ControlledSmokeState.blocked;
      reasonCode = 'operator_binding_mismatch'; notifyListeners(); return;
    }
    authReady = true;
    if (!await appCheckReady()) {
      state = ControlledSmokeState.blocked;
      reasonCode = 'app_check_not_ready'; notifyListeners(); return;
    }
    appCheckActivationReady = true;
    try {
      freshTokenReady = await freshAppCheckTokenReady();
    } catch (_) {
      freshTokenReady = false;
    }
    if (!freshTokenReady) {
      state = ControlledSmokeState.blocked;
      reasonCode = 'app_check_token_unavailable'; notifyListeners(); return;
    }
    _verifiedUid = uid;
    state = ControlledSmokeState.armed; notifyListeners();
  }

  Future<void> fire() async {
    if (!debugEnabled || !isArmed) {
      reasonCode = _fired ? 'local_smoke_already_fired' : 'smoke_not_armed';
      notifyListeners(); return;
    }
    // Synchronous lock before the first await: duplicate taps cannot send twice.
    _fired = true; state = ControlledSmokeState.fired; notifyListeners();
    final uid = await currentUid();
    if (uid == null || uid != _verifiedUid) {
      authReady = false; freshTokenReady = false;
      reasonCode = 'auth_not_ready';
      state = ControlledSmokeState.failed; notifyListeners(); return;
    }
    try {
      freshTokenReady = await freshAppCheckTokenReady();
    } catch (_) {
      freshTokenReady = false;
    }
    if (!freshTokenReady) {
      reasonCode = 'app_check_token_unavailable';
      state = ControlledSmokeState.failed; notifyListeners(); return;
    }
    try {
      final result = await call(itemId);
      reasonCode = result.reasonCode;
      state = ControlledSmokeState.completed;
    } catch (_) {
      reasonCode = 'client_error_no_retry';
      state = ControlledSmokeState.failed;
    }
    notifyListeners();
  }

  static String _fingerprint(String value) {
    var hash = 0; for (final code in value.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

abstract final class ControlledShadowSmoke {
  static const enabled = bool.fromEnvironment('OOTD_CONTROLLED_SHADOW_SMOKE');
  static const itemId = String.fromEnvironment('OOTD_SMOKE_ITEM_ID');
  static const expectedUid = String.fromEnvironment('OOTD_SMOKE_EXPECTED_UID');
  static ControlledShadowSmokeController? _controller;

  static bool get isEnabled => kDebugMode && enabled;

  static ControlledShadowSmokeController controller() => _controller ??=
      ControlledShadowSmokeController(debugEnabled: isEnabled,
        expectedUid: expectedUid, itemId: itemId,
        currentUid: () async => FirebaseAuth.instance.currentUser?.uid,
        appCheckReady: () async => (await FirebaseAppCheckBootstrap.instance
          .ensureInitialized()).isReady,
        freshAppCheckTokenReady: () async {
          final token = await FirebaseAppCheck.instance.getToken(true);
          return token != null && token.trim().isNotEmpty;
        },
        call: (candidate) async {
          final result = await WardrobeQualificationAuthorityClient.instance
              .analyzeCurrentSource(itemId: candidate,
                idempotencyKey: 'm11-1-10g-3c-manual-one-shot');
          return (ok: result.ok, reasonCode: result.reasonCode);
        });

  /// Arms only. Never sends a callable.
  static Future<void> armIfEnabled() async {
    if (isEnabled) await controller().arm();
  }

  static Widget overlay(Widget child) => isEnabled ?
      ControlledShadowSmokeOverlay(controller: controller(), child: child) : child;
}

class ControlledShadowSmokeOverlay extends StatelessWidget {
  const ControlledShadowSmokeOverlay({required this.controller,
    required this.child, super.key});
  final ControlledShadowSmokeController controller;
  final Widget child;

  @override Widget build(BuildContext context) => Stack(children: [child,
    Positioned(right: 12, top: 42, child: AnimatedBuilder(
      animation: controller, builder: (_, child) => Material(color: Colors.transparent,
        child: Container(width: 310, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.black87,
            borderRadius: BorderRadius.circular(12)), child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [const Text('Smoke Harness: manual-v2 - Build: 10G-3C.3',
              style: TextStyle(color: Colors.lightBlueAccent)),
              Text('SHADOW SMOKE: ${controller.state.name.toUpperCase()}',
              style: const TextStyle(color: Colors.white)),
              Text('user ${controller.uidFingerprint} • item ${controller.itemFingerprint}',
                style: const TextStyle(color: Colors.white70)),
              Text('Auth: ${controller.authReady ? "READY" : "NOT READY"}',
                style: const TextStyle(color: Colors.white70)),
              Text('App Check activation: ${controller.appCheckActivationReady ? "READY" : "NOT READY"}',
                style: const TextStyle(color: Colors.white70)),
              Text('Fresh token: ${controller.freshTokenReady ? "READY" : "NOT READY"}',
                style: const TextStyle(color: Colors.white70)),
              if (controller.reasonCode != null) Text(controller.reasonCode!,
                style: const TextStyle(color: Colors.amber)),
              const SizedBox(height: 8),
              if (!controller.isArmed && !controller.hasFired)
                ElevatedButton(onPressed: controller.arm,
                  child: const Text('ARM SHADOW SMOKE')),
              ElevatedButton(onPressed: controller.isArmed &&
                  controller.authReady && controller.freshTokenReady &&
                  !controller.hasFired ? controller.fire : null,
                child: const Text('FIRE ONE SHADOW SMOKE REQUEST'))])))))]);
}
