import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/firebase_app_check_bootstrap.dart';
import 'package:outfitofTheDay/Services/wardrobe_qualification_authority_client.dart';
import 'package:outfitofTheDay/Services/wardrobe_revision_lifecycle_client.dart';

void main() {
  group('FirebaseAppCheckBootstrap providers', () {
    test('1 Firebase must be initialized before activate', () async {
      final bootstrap = FirebaseAppCheckBootstrap(
        debugBuildOverride: true,
        platformOverride: TargetPlatform.android,
        firebaseReadyOverride: false,
        activator:
            ({
              required AndroidProvider androidProvider,
              required AppleProvider appleProvider,
            }) async {
              fail('activate must not run');
            },
      );
      final result = await bootstrap.ensureInitialized();
      expect(result.isReady, isFalse);
      expect(result.reasonCode, 'firebase_not_initialized');
    });

    test('2 App Check initialization once', () async {
      var calls = 0;
      final bootstrap = FirebaseAppCheckBootstrap(
        debugBuildOverride: true,
        platformOverride: TargetPlatform.android,
        firebaseReadyOverride: true,
        activator:
            ({
              required AndroidProvider androidProvider,
              required AppleProvider appleProvider,
            }) async {
              calls += 1;
            },
      );
      final first = await bootstrap.ensureInitialized();
      expect(first.isReady, isTrue);
      expect(calls, 1);
    });

    test('3 repeated ensureInitialized is idempotent', () async {
      var calls = 0;
      final bootstrap = FirebaseAppCheckBootstrap(
        debugBuildOverride: false,
        platformOverride: TargetPlatform.android,
        firebaseReadyOverride: true,
        activator:
            ({
              required AndroidProvider androidProvider,
              required AppleProvider appleProvider,
            }) async {
              calls += 1;
            },
      );
      final a = await bootstrap.ensureInitialized();
      final b = await bootstrap.ensureInitialized();
      expect(identical(a, b), isTrue);
      expect(calls, 1);
      expect(a.providerKind, FirebaseAppCheckProviderKind.androidPlayIntegrity);
    });

    test('4 Android debug provider', () {
      final p = FirebaseAppCheckBootstrap.resolveProviders(
        platform: TargetPlatform.android,
        isDebugBuild: true,
      );
      expect(p.android, AndroidProvider.debug);
      expect(p.kind, FirebaseAppCheckProviderKind.androidDebug);
      expect(p.supported, isTrue);
    });

    test('5 Android release Play Integrity', () {
      final p = FirebaseAppCheckBootstrap.resolveProviders(
        platform: TargetPlatform.android,
        isDebugBuild: false,
      );
      expect(p.android, AndroidProvider.playIntegrity);
      expect(p.kind, FirebaseAppCheckProviderKind.androidPlayIntegrity);
    });

    test('6 unsupported platform policy', () async {
      final bootstrap = FirebaseAppCheckBootstrap(
        debugBuildOverride: false,
        platformOverride: TargetPlatform.linux,
        firebaseReadyOverride: true,
        activator:
            ({
              required AndroidProvider androidProvider,
              required AppleProvider appleProvider,
            }) async {
              fail('unsupported must not activate');
            },
      );
      final result = await bootstrap.ensureInitialized();
      expect(result.status, FirebaseAppCheckInitStatus.unsupportedPlatform);
      expect(result.reasonCode, 'app_check_unsupported_platform');
      expect(result.isReady, isFalse);
    });

    test('7 activation failure soft result', () async {
      final bootstrap = FirebaseAppCheckBootstrap(
        debugBuildOverride: true,
        platformOverride: TargetPlatform.android,
        firebaseReadyOverride: true,
        activator:
            ({
              required AndroidProvider androidProvider,
              required AppleProvider appleProvider,
            }) async {
              throw StateError('activate_boom');
            },
      );
      final result = await bootstrap.ensureInitialized();
      expect(result.isReady, isFalse);
      expect(result.status, FirebaseAppCheckInitStatus.failed);
      expect(result.reasonCode, 'app_check_activation_failed');
    });

    test('8 no debug token in bootstrap source', () {
      final source = File(
        'lib/Services/firebase_app_check_bootstrap.dart',
      ).readAsStringSync();
      expect(source.contains('debugToken'), isFalse);
      expect(source.contains('DEBUG_TOKEN'), isFalse);
      expect(source.contains('X-Firebase-AppCheck'), isFalse);
      expect(
        source.contains('androidProvider: AndroidProvider.debug'),
        isFalse,
      );
    });
  });

  group('callable App Check ordering', () {
    test('9-10 live path waits and soft-defers before callable', () async {
      var activated = false;
      var transportWouldRun = false;
      final bootstrap = FirebaseAppCheckBootstrap(
        debugBuildOverride: true,
        platformOverride: TargetPlatform.android,
        firebaseReadyOverride: false,
        activator:
            ({
              required AndroidProvider androidProvider,
              required AppleProvider appleProvider,
            }) async {
              activated = true;
            },
      );
      final client = WardrobeRevisionLifecycleClient(
        appCheckBootstrap: bootstrap,
      );
      final result = await client.callOperation(
        operationKind: kLifecycleOpInitializeUserPhoto,
        itemId: 'i1',
      );
      expect(activated, isFalse);
      expect(transportWouldRun, isFalse);
      expect(result.status, WardrobeLifecycleCallStatus.deferredUntilExport);
      expect(result.reasonCode, 'firebase_not_initialized');
    });

    test('11 init failure preserves safe soft-defer UX', () async {
      final bootstrap = FirebaseAppCheckBootstrap(
        debugBuildOverride: true,
        platformOverride: TargetPlatform.android,
        firebaseReadyOverride: true,
        activator:
            ({
              required AndroidProvider androidProvider,
              required AppleProvider appleProvider,
            }) async {
              throw Exception('boom');
            },
      );
      final client = WardrobeQualificationAuthorityClient(
        appCheckBootstrap: bootstrap,
      );
      final result = await client.analyzeCurrentSource(itemId: 'i1');
      expect(result.status, WardrobeLifecycleCallStatus.deferredUntilExport);
      expect(result.reasonCode, 'app_check_activation_failed');
      expect(result.ok, isTrue);
    });
  });

  group('callable clients', () {
    test('12-16 names, no uid/revision fields, soft-defer unchanged', () async {
      Map<String, dynamic>? lifeData;
      Map<String, dynamic>? authData;
      final life = WardrobeRevisionLifecycleClient(
        transport: (name, data) async {
          expect(name, 'wardrobeRevisionLifecycle');
          lifeData = data;
          return {
            'ok': true,
            'result': {'status': 'ok'},
          };
        },
      );
      final auth = WardrobeQualificationAuthorityClient(
        transport: (name, data) async {
          expect(name, 'wardrobeQualificationAuthority');
          authData = data;
          return {
            'ok': true,
            'result': {'reasonCode': 'shadow_ok'},
          };
        },
      );

      await life.callOperation(
        operationKind: kLifecycleOpClassificationEdit,
        itemId: 'i1',
        patch: {'name': 'A'},
      );
      await auth.analyzeCurrentSource(itemId: 'i1');

      expect(lifeData!.containsKey('uid'), isFalse);
      expect(lifeData!.containsKey('imageRevision'), isFalse);
      expect(lifeData!.containsKey('qualificationAuthority'), isFalse);
      expect(authData!.containsKey('uid'), isFalse);
      expect(authData!.containsKey('imageRevision'), isFalse);
      expect(authData!.containsKey('qualificationAuthority'), isFalse);
      expect(
        kWardrobeRevisionLifecycleCallableName,
        'wardrobeRevisionLifecycle',
      );
      expect(
        kWardrobeQualificationAuthorityCallableName,
        'wardrobeQualificationAuthority',
      );
    });

    test('17 failed-precondition soft-defers', () async {
      final client = WardrobeRevisionLifecycleClient(
        transport: (name, data) async {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'app check',
          );
        },
      );
      final result = await client.callOperation(
        operationKind: kLifecycleOpUserCorrection,
        itemId: 'i1',
        correction: {'field': 'x'},
      );
      expect(result.status, WardrobeLifecycleCallStatus.deferredUntilExport);
      expect(result.reasonCode, 'failed-precondition');
    });

    test('18 unauthenticated soft-defers', () async {
      final client = WardrobeQualificationAuthorityClient(
        transport: (name, data) async {
          throw FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'auth',
          );
        },
      );
      final result = await client.analyzeCurrentSource(itemId: 'i1');
      expect(result.status, WardrobeLifecycleCallStatus.deferredUntilExport);
      expect(result.reasonCode, 'unauthenticated');
    });

    test('19 permission-denied soft-defers', () async {
      final client = WardrobeRevisionLifecycleClient(
        transport: (name, data) async {
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'denied',
          );
        },
      );
      final result = await client.callOperation(
        operationKind: kLifecycleOpDerivativeCompletion,
        itemId: 'i1',
        derivativeKind: 'thumb',
      );
      expect(result.status, WardrobeLifecycleCallStatus.deferredUntilExport);
      expect(result.reasonCode, 'permission-denied');
    });
  });

  group('static policy scans', () {
    test('20 no debug secrets/token scan across App Check sources', () {
      final paths = [
        'lib/Services/firebase_app_check_bootstrap.dart',
        'lib/Services/wardrobe_revision_lifecycle_client.dart',
        'lib/Services/wardrobe_qualification_authority_client.dart',
        'lib/main.dart',
      ];
      for (final path in paths) {
        final src = File(path).readAsStringSync();
        expect(src.contains('debugToken:'), isFalse, reason: path);
        expect(src.contains('DEBUG_TOKEN'), isFalse, reason: path);
        expect(src.contains('X-Firebase-AppCheck'), isFalse, reason: path);
      }
    });

    test('21 release never resolves debug provider', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        final p = FirebaseAppCheckBootstrap.resolveProviders(
          platform: platform,
          isDebugBuild: false,
        );
        expect(p.kind, isNot(FirebaseAppCheckProviderKind.androidDebug));
        expect(p.kind, isNot(FirebaseAppCheckProviderKind.appleDebug));
        if (platform == TargetPlatform.android) {
          expect(p.android, isNot(AndroidProvider.debug));
        }
        if (platform == TargetPlatform.iOS ||
            platform == TargetPlatform.macOS) {
          expect(p.apple, isNot(AppleProvider.debug));
        }
      }
    });

    test('22 no direct manual App Check header', () {
      final life = File(
        'lib/Services/wardrobe_revision_lifecycle_client.dart',
      ).readAsStringSync();
      final auth = File(
        'lib/Services/wardrobe_qualification_authority_client.dart',
      ).readAsStringSync();
      expect(life.contains('X-Firebase-AppCheck'), isFalse);
      expect(life.contains('getToken'), isFalse);
      expect(life.contains('httpsCallable'), isTrue);
      expect(auth.contains('X-Firebase-AppCheck'), isFalse);
      expect(auth.contains('getToken'), isFalse);
      expect(auth.contains('httpsCallable'), isTrue);
    });

    test('23 Firebase initialization ordering in main.dart', () {
      final mainSrc = File('lib/main.dart').readAsStringSync();
      final firebaseInit = mainSrc.indexOf('Firebase.initializeApp()');
      final appCheckInit = mainSrc.indexOf(
        'FirebaseAppCheckBootstrap.instance.ensureInitialized()',
      );
      expect(firebaseInit, greaterThanOrEqualTo(0));
      expect(appCheckInit, greaterThan(firebaseInit));
    });
  });
}
