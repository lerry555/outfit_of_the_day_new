/// M11.1 Phase 10C — Firebase App Check bootstrap.
///
/// Activates App Check after [Firebase.initializeApp] and before wardrobe
/// authority/lifecycle callables. Idempotent. No secrets / debug tokens in
/// source.
library;

import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

typedef FirebaseAppCheckActivator =
    Future<void> Function({
      required AndroidProvider androidProvider,
      required AppleProvider appleProvider,
    });

enum FirebaseAppCheckProviderKind {
  androidPlayIntegrity,
  androidDebug,
  appleDeviceCheck,
  appleDebug,
  unsupported,
}

enum FirebaseAppCheckInitStatus { ready, failed, unsupportedPlatform }

class FirebaseAppCheckInitResult {
  const FirebaseAppCheckInitResult({
    required this.status,
    required this.providerKind,
    required this.isDebugBuild,
    this.reasonCode,
    this.errorMessage,
  });

  final FirebaseAppCheckInitStatus status;
  final FirebaseAppCheckProviderKind providerKind;
  final bool isDebugBuild;
  final String? reasonCode;
  final String? errorMessage;

  bool get isReady => status == FirebaseAppCheckInitStatus.ready;

  /// Soft-defer wardrobe callables when App Check is not ready.
  bool get allowsCallableSoftDefer =>
      status == FirebaseAppCheckInitStatus.failed ||
      status == FirebaseAppCheckInitStatus.unsupportedPlatform;
}

class FirebaseAppCheckBootstrap {
  FirebaseAppCheckBootstrap({
    FirebaseAppCheckActivator? activator,
    bool? debugBuildOverride,
    TargetPlatform? platformOverride,
    bool? firebaseReadyOverride,
  }) : _activator = activator,
       _debugBuildOverride = debugBuildOverride,
       _platformOverride = platformOverride,
       _firebaseReadyOverride = firebaseReadyOverride;

  final FirebaseAppCheckActivator? _activator;
  final bool? _debugBuildOverride;
  final TargetPlatform? _platformOverride;
  final bool? _firebaseReadyOverride;

  static FirebaseAppCheckBootstrap instance = FirebaseAppCheckBootstrap();

  Future<FirebaseAppCheckInitResult>? _inflight;
  FirebaseAppCheckInitResult? _result;

  FirebaseAppCheckInitResult? get lastResult => _result;

  bool get isReady => _result?.isReady == true;

  /// Resolves provider policy without activating (testable).
  static ({
    AndroidProvider android,
    AppleProvider apple,
    FirebaseAppCheckProviderKind kind,
    bool supported,
  })
  resolveProviders({
    required TargetPlatform platform,
    required bool isDebugBuild,
  }) {
    switch (platform) {
      case TargetPlatform.android:
        if (isDebugBuild) {
          return (
            android: AndroidProvider.debug,
            apple: AppleProvider.deviceCheck,
            kind: FirebaseAppCheckProviderKind.androidDebug,
            supported: true,
          );
        }
        return (
          android: AndroidProvider.playIntegrity,
          apple: AppleProvider.deviceCheck,
          kind: FirebaseAppCheckProviderKind.androidPlayIntegrity,
          supported: true,
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        if (isDebugBuild) {
          return (
            android: AndroidProvider.playIntegrity,
            apple: AppleProvider.debug,
            kind: FirebaseAppCheckProviderKind.appleDebug,
            supported: true,
          );
        }
        return (
          android: AndroidProvider.playIntegrity,
          apple: AppleProvider.deviceCheck,
          kind: FirebaseAppCheckProviderKind.appleDeviceCheck,
          supported: true,
        );
      default:
        return (
          android: AndroidProvider.playIntegrity,
          apple: AppleProvider.deviceCheck,
          kind: FirebaseAppCheckProviderKind.unsupported,
          supported: false,
        );
    }
  }

  /// Idempotent activation. Safe to call multiple times.
  Future<FirebaseAppCheckInitResult> ensureInitialized() {
    if (_result != null) return Future.value(_result);
    return _inflight ??= _activateOnce();
  }

  /// Test helper to reset singleton state.
  @visibleForTesting
  void resetForTest() {
    _inflight = null;
    _result = null;
  }

  Future<FirebaseAppCheckInitResult> _activateOnce() async {
    final isDebug = _debugBuildOverride ?? kDebugMode;
    final platform = _platformOverride ?? defaultTargetPlatform;
    final providers = resolveProviders(
      platform: platform,
      isDebugBuild: isDebug,
    );

    if (!providers.supported) {
      final result = FirebaseAppCheckInitResult(
        status: FirebaseAppCheckInitStatus.unsupportedPlatform,
        providerKind: FirebaseAppCheckProviderKind.unsupported,
        isDebugBuild: isDebug,
        reasonCode: 'app_check_unsupported_platform',
      );
      _result = result;
      return result;
    }

    // Release builds must never use debug providers.
    if (!isDebug) {
      if (providers.kind == FirebaseAppCheckProviderKind.androidDebug ||
          providers.kind == FirebaseAppCheckProviderKind.appleDebug) {
        final result = FirebaseAppCheckInitResult(
          status: FirebaseAppCheckInitStatus.failed,
          providerKind: providers.kind,
          isDebugBuild: isDebug,
          reasonCode: 'app_check_debug_provider_forbidden_in_release',
        );
        _result = result;
        return result;
      }
    }

    try {
      final firebaseReady = _firebaseReadyOverride ?? Firebase.apps.isNotEmpty;
      if (!firebaseReady) {
        final result = FirebaseAppCheckInitResult(
          status: FirebaseAppCheckInitStatus.failed,
          providerKind: providers.kind,
          isDebugBuild: isDebug,
          reasonCode: 'firebase_not_initialized',
        );
        _result = result;
        return result;
      }

      final activator = _activator ?? _defaultActivate;
      await activator(
        androidProvider: providers.android,
        appleProvider: providers.apple,
      );

      if (isDebug) {
        debugPrint(
          '[APP_CHECK] activated provider=${providers.kind.name}. '
          'If using debug provider, copy the Firebase-generated debug token '
          'from device logs and register it manually in Firebase Console '
          '(App Check → Manage debug tokens). Do not commit the token.',
        );
      } else {
        debugPrint('[APP_CHECK] activated provider=${providers.kind.name}');
      }

      final result = FirebaseAppCheckInitResult(
        status: FirebaseAppCheckInitStatus.ready,
        providerKind: providers.kind,
        isDebugBuild: isDebug,
        reasonCode: 'app_check_ready',
      );
      _result = result;
      return result;
    } catch (e) {
      debugPrint('[APP_CHECK] activation_failed error=$e');
      final result = FirebaseAppCheckInitResult(
        status: FirebaseAppCheckInitStatus.failed,
        providerKind: providers.kind,
        isDebugBuild: isDebug,
        reasonCode: 'app_check_activation_failed',
        errorMessage: e.toString(),
      );
      _result = result;
      return result;
    }
  }

  static Future<void> _defaultActivate({
    required AndroidProvider androidProvider,
    required AppleProvider appleProvider,
  }) {
    return FirebaseAppCheck.instance.activate(
      androidProvider: androidProvider,
      appleProvider: appleProvider,
    );
  }
}
