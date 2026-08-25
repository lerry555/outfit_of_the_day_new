import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/wardrobe_qualification_authority_client.dart';
import 'package:outfitofTheDay/Services/wardrobe_revision_lifecycle_client.dart';
import 'package:outfitofTheDay/debug/wardrobe_authority_disabled_smoke.dart';
import 'package:cloud_functions/cloud_functions.dart';

void main() {
  test('smoke harness is debug-define gated and inactive by default', () {
    expect(WardrobeAuthorityDisabledSmoke.enabled, isFalse);
  });

  test('clients soft-defer deployed disabled failed-precondition', () async {
    final life = WardrobeRevisionLifecycleClient(
      transport: (name, data) async {
        expect(name, kWardrobeRevisionLifecycleCallableName);
        expect(data['operationKind'], kLifecycleOpSameImageReanalysis);
        expect(data.containsKey('uid'), isFalse);
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'wardrobe_authority_mode_disabled',
        );
      },
    );
    final auth = WardrobeQualificationAuthorityClient(
      transport: (name, data) async {
        expect(name, kWardrobeQualificationAuthorityCallableName);
        expect(data['action'], kAuthorityActionAnalyzeCurrentSource);
        expect(data.containsKey('uid'), isFalse);
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'wardrobe_authority_mode_disabled',
        );
      },
    );

    final lifeResult = await life.callOperation(
      operationKind: kLifecycleOpSameImageReanalysis,
      itemId: 'item-smoke',
    );
    final authResult = await auth.analyzeCurrentSource(itemId: 'item-smoke');

    expect(lifeResult.status, WardrobeLifecycleCallStatus.deferredUntilExport);
    expect(lifeResult.reasonCode, 'failed-precondition');
    expect(lifeResult.ok, isTrue);
    expect(authResult.status, WardrobeLifecycleCallStatus.deferredUntilExport);
    expect(authResult.reasonCode, 'failed-precondition');
    expect(authResult.ok, isTrue);
  });

  test('callable region remains us-east1', () {
    expect(kWardrobeLifecycleCallableRegion, 'us-east1');
    expect(kDebugMode, isTrue); // unit tests run in debug
  });
}
