import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

void main() {
  group('Wardrobe profile contract', () {
    test('wire names are stable and evidence source round-trips', () {
      for (final source in EvidenceSource.values) {
        expect(EvidenceSource.fromWireName(source.wireName), same(source));
      }

      expect(WardrobeLayerRole.baseLayer.wireName, 'base_layer');
      expect(WardrobeLayerRole.outerLayer.wireName, 'outer_layer');
      expect(CapabilityLevel.unknown.wireName, 'unknown');
      expect(RainSuitability.unknown.wireName, 'unknown');
      expect(CapabilityLevel.veryLow.wireName, 'very_low');
      expect(CapabilityLevel.veryHigh.wireName, 'very_high');
    });

    test('profile evidence map serialization preserves provenance', () {
      final createdAt = DateTime.utc(2026, 7, 26, 12, 30);
      final evidence = ProfileEvidence(
        id: 'evidence-1',
        property: WardrobeProfileProperty.canonicalType,
        value: 'softshell',
        source: EvidenceSource.userCorrection,
        nature: EvidenceNature.observed,
        confidence: 1,
        verified: true,
        method: 'manual_edit',
        createdAt: createdAt,
        supersedesEvidenceId: 'evidence-0',
        dependsOnCanonicalType: 'hoodie',
      );

      final restored = ProfileEvidence.fromMap(evidence.toMap());

      expect(restored.id, evidence.id);
      expect(restored.property, WardrobeProfileProperty.canonicalType);
      expect(restored.value, 'softshell');
      expect(restored.source, EvidenceSource.userCorrection);
      expect(restored.nature, EvidenceNature.observed);
      expect(restored.confidence, 1);
      expect(restored.verified, isTrue);
      expect(restored.isUserCorrection, isTrue);
      expect(restored.createdAt, createdAt);
      expect(restored.supersedesEvidenceId, 'evidence-0');
      expect(restored.dependsOnCanonicalType, 'hoodie');
    });

    test('unknown is explicit and carries no neutral default', () {
      const unknownWarmth = ResolvedField<int>.unknown();

      expect(unknownWarmth.isKnown, isFalse);
      expect(unknownWarmth.value, isNull);
      expect(unknownWarmth.confidence, 0);
      expect(unknownWarmth.winningSource, isNull);
      expect(unknownWarmth.nature, isNull);
      expect(unknownWarmth.toMap()['value'], isNull);
      expect(unknownWarmth.state, ResolvedFieldState.unknown);
      expect(unknownWarmth.isNotApplicable, isFalse);
    });

    test('not applicable is distinct from known and unknown', () {
      const traction = ResolvedField<CapabilityLevel>.notApplicable(
        nature: EvidenceNature.observed,
        winningSource: EvidenceSource.userCorrection,
        confidence: 1,
        resolutionReason: 'user_marked_not_applicable',
        winningEvidenceIds: ['user-1'],
        userCorrected: true,
      );

      final restored = ResolvedField<CapabilityLevel>.fromMap(
        Map<String, dynamic>.from(traction.toMap()),
        decodeValue: (value) => CapabilityLevel.fromWireName(value.toString()),
      );

      expect(traction.isKnown, isFalse);
      expect(traction.isUnknown, isFalse);
      expect(traction.isNotApplicable, isTrue);
      expect(traction.value, isNull);
      expect(traction.toMap()['state'], 'not_applicable');
      expect(restored.isNotApplicable, isTrue);
      expect(restored.userCorrected, isTrue);
    });

    test('legacy resolved field map remains readable without state', () {
      final restored = ResolvedField<int>.fromMap(<String, dynamic>{
        'value': 6,
        'isKnown': true,
        'nature': 'observed',
        'winningSource': 'visual_observation',
        'confidence': 0.8,
        'resolutionReason': 'legacy_fixture',
      }, decodeValue: (value) => value as int);

      expect(restored.state, ResolvedFieldState.known);
      expect(restored.value, 6);
    });

    test('known field preserves authority and conflict information', () {
      const field = ResolvedField<String>.known(
        value: 'softshell',
        nature: EvidenceNature.observed,
        winningSource: EvidenceSource.verifiedProductMetadata,
        confidence: 0.96,
        resolutionReason: 'verified_product_over_ai',
        winningEvidenceIds: ['product-1'],
        conflictingEvidenceIds: ['ai-1'],
      );

      expect(field.isKnown, isTrue);
      expect(field.value, 'softshell');
      expect(field.hasConflict, isTrue);
      expect(field.userCorrected, isFalse);
      expect(field.toMap()['winningSource'], 'verified_product_metadata');
    });

    test('new profile leaves unsupported capabilities unknown', () {
      const profile = ResolvedWardrobeItemProfile(itemId: 'item-1');

      expect(profile.metadata.schemaVersion, WardrobeProfileVersions.schema);
      expect(profile.capabilities.warmth.isKnown, isFalse);
      expect(profile.capabilities.mobility.isKnown, isFalse);
      expect(profile.capabilities.rainSuitability.isKnown, isFalse);
      expect(profile.capabilities.rainProtection.isKnown, isFalse);
      expect(profile.capabilities.walkingComfort.isKnown, isFalse);
      expect(profile.capabilities.traction.isKnown, isFalse);
      expect(profile.capabilities.supportedLayerRoles.isKnown, isFalse);
      expect(profile.visual.coverage.isKnown, isFalse);
      expect(profile.suitability.activities.isKnown, isFalse);
      expect(profile.evidence, isEmpty);
    });
  });
}
