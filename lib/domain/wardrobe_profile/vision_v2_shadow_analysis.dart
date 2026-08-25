import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/clothing_knowledge_base.dart';
import 'canonical_observation_consistency_validator.dart';
import 'observation_absence_qualifier.dart';
import 'vision_family_identity.dart';
import 'vision_framing_attestation.dart';
import 'vision_observation_evidence_provider.dart';
import 'vision_subject_safety.dart';
import 'vision_visibility_trust.dart';
import 'wardrobe_capability_inference_provider.dart';
import 'wardrobe_knowledge_base_prior_provider.dart';
import 'wardrobe_profile_contract.dart';
import 'wardrobe_profile_resolver.dart';

const String visionV2ShadowEndpoint =
    'https://us-east1-outfitoftheday-4d401.cloudfunctions.net/'
    'analyzeClothingImageV2Shadow';

class VisionV2IdentityCandidate {
  const VisionV2IdentityCandidate({
    required this.canonicalType,
    required this.confidence,
    this.definingObservations = const [],
    this.supportingObservations = const [],
  });

  final String canonicalType;
  final double confidence;
  final List<String> definingObservations;
  final List<String> supportingObservations;

  Map<String, Object?> toMap() => {
    'canonicalType': canonicalType,
    'confidence': confidence,
    'definingObservations': definingObservations,
    'supportingObservations': supportingObservations,
  };
}

class VisionV2Diagnostics {
  const VisionV2Diagnostics({
    required this.latencyMs,
    required this.modelCallCount,
    required this.inputPayloadBytes,
    required this.outputPayloadBytes,
    required this.observationFieldCount,
  });

  final int latencyMs;
  final int modelCallCount;
  final int inputPayloadBytes;
  final int outputPayloadBytes;
  final int observationFieldCount;

  factory VisionV2Diagnostics.fromMap(Map<String, dynamic> map) =>
      VisionV2Diagnostics(
        latencyMs: _nonNegativeInt(map['latencyMs'], 'latencyMs'),
        modelCallCount: _nonNegativeInt(
          map['modelCallCount'],
          'modelCallCount',
        ),
        inputPayloadBytes: _nonNegativeInt(
          map['inputPayloadBytes'],
          'inputPayloadBytes',
        ),
        outputPayloadBytes: _nonNegativeInt(
          map['outputPayloadBytes'],
          'outputPayloadBytes',
        ),
        observationFieldCount: _nonNegativeInt(
          map['observationFieldCount'],
          'observationFieldCount',
        ),
      );

  Map<String, Object?> toMap() => {
    'latencyMs': latencyMs,
    'modelCallCount': modelCallCount,
    'inputPayloadBytes': inputPayloadBytes,
    'outputPayloadBytes': outputPayloadBytes,
    'observationFieldCount': observationFieldCount,
  };
}

enum VisionIdentityState {
  confirmed,
  supported,
  ambiguous,
  insufficientEvidence,
  conflicting;

  String get wireName => switch (this) {
    VisionIdentityState.insufficientEvidence => 'insufficient_evidence',
    _ => name,
  };
}

class VisionIdentityCandidateQualification {
  const VisionIdentityCandidateQualification({
    required this.canonicalType,
    required this.rawConfidence,
    required this.qualifiedConfidence,
    required this.state,
    required this.usedDefiningSupports,
    required this.usedSupportingObservations,
    required this.modelDeclaredDefining,
    required this.modelDeclaredSupporting,
    required this.rejectedSupportingObservations,
    required this.rejectedDefiningObservations,
    required this.missingDefiningEvidence,
    required this.missingSignatureCoverage,
    required this.reasonCodes,
  });

  final String canonicalType;
  final double rawConfidence;
  final double qualifiedConfidence;
  final VisionIdentityState state;
  final List<String> usedDefiningSupports;
  final List<String> usedSupportingObservations;
  final List<String> modelDeclaredDefining;
  final List<String> modelDeclaredSupporting;
  final List<String> rejectedSupportingObservations;
  final List<String> rejectedDefiningObservations;
  final List<String> missingDefiningEvidence;
  final bool missingSignatureCoverage;
  final List<String> reasonCodes;

  Map<String, Object?> toMap() => {
    'canonicalType': canonicalType,
    'rawConfidence': rawConfidence,
    'qualifiedConfidence': qualifiedConfidence,
    'state': state.wireName,
    'usedDefiningSupports': usedDefiningSupports,
    'usedSupportingObservations': usedSupportingObservations,
    'modelDeclaredDefining': modelDeclaredDefining,
    'modelDeclaredSupporting': modelDeclaredSupporting,
    'rejectedSupportingObservations': rejectedSupportingObservations,
    'rejectedDefiningObservations': rejectedDefiningObservations,
    'missingDefiningEvidence': missingDefiningEvidence,
    'missingSignatureCoverage': missingSignatureCoverage,
    'reasonCodes': reasonCodes,
  };
}

class VisionIdentityQualificationReport {
  const VisionIdentityQualificationReport({
    required this.state,
    required this.selectedCanonicalType,
    required this.topMargin,
    required this.candidates,
  });

  final VisionIdentityState state;
  final String? selectedCanonicalType;
  final double? topMargin;
  final List<VisionIdentityCandidateQualification> candidates;

  Map<String, Object?> toMap() => {
    'state': state.wireName,
    'selectedCanonicalType': selectedCanonicalType,
    'topMargin': topMargin,
    'candidates': candidates.map((item) => item.toMap()).toList(),
  };
}

class VisionV2ShadowResponse {
  const VisionV2ShadowResponse({
    required this.schemaVersion,
    required this.inputAssessment,
    required this.subjectAssessment,
    this.framingAttestations,
    required this.observations,
    required this.identityCandidates,
    required this.validationErrors,
    required this.diagnostics,
  });

  final int schemaVersion;
  final VisionInputAssessment inputAssessment;
  final VisionSubjectAssessment subjectAssessment;
  final VisionFramingAttestations? framingAttestations;
  final ClothingObservationBundle observations;
  final List<VisionV2IdentityCandidate> identityCandidates;
  final List<String> validationErrors;
  final VisionV2Diagnostics diagnostics;

  factory VisionV2ShadowResponse.fromJson(
    String source, {
    required Set<String> allowedCanonicalTypes,
  }) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Vision v2 root must be an object');
    }
    return VisionV2ShadowResponse.fromMap(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
      allowedCanonicalTypes: allowedCanonicalTypes,
    );
  }

  factory VisionV2ShadowResponse.fromMap(
    Map<String, dynamic> map, {
    required Set<String> allowedCanonicalTypes,
  }) {
    final schemaVersion = map['schemaVersion'];
    if (schemaVersion < 2 || schemaVersion > 9) {
      throw const FormatException('Unsupported Vision v2 schemaVersion');
    }
    final candidatesRaw = map['identityCandidates'];
    if (candidatesRaw is! List) {
      throw const FormatException('identityCandidates must be a list');
    }
    final candidates = <VisionV2IdentityCandidate>[];
    for (final raw in candidatesRaw) {
      final candidate = _map(raw, 'identity candidate');
      final canonicalType = candidate['canonicalType'];
      final confidence = candidate['confidence'];
      final definingRaw = candidate['definingObservations'];
      final supportingRaw = candidate['supportingObservations'];
      if (canonicalType is! String ||
          !allowedCanonicalTypes.contains(canonicalType)) {
        throw FormatException('Unknown canonical candidate: $canonicalType');
      }
      if (confidence is! num ||
          !confidence.isFinite ||
          confidence < 0 ||
          confidence > 1) {
        throw FormatException('Invalid confidence for $canonicalType');
      }
      if (schemaVersion >= 3 &&
          (supportingRaw is! List ||
              supportingRaw.any((value) => value is! String))) {
        throw FormatException(
          'Invalid supporting observations for $canonicalType',
        );
      }
      if (schemaVersion >= 5 &&
          (definingRaw is! List ||
              definingRaw.any((value) => value is! String))) {
        throw FormatException(
          'Invalid defining observations for $canonicalType',
        );
      }
      final parsedDefining = definingRaw is List
          ? (definingRaw.cast<String>().toSet().toList()..sort())
          : <String>[];
      final supporting = supportingRaw is List
          ? (supportingRaw.cast<String>().toSet().toList()..sort())
          : <String>[];
      final defining = schemaVersion >= 5
          ? parsedDefining
          : List<String>.from(supporting);
      candidates.add(
        VisionV2IdentityCandidate(
          canonicalType: canonicalType,
          confidence: confidence.toDouble(),
          definingObservations: List.unmodifiable(defining),
          supportingObservations: List.unmodifiable(supporting),
        ),
      );
    }
    if (candidates.length > 3) {
      throw const FormatException('Too many identity candidates');
    }

    final observationMap = <String, dynamic>{
      'analysisId': map['analysisId'],
      'modelVersion': map['modelVersion'],
      'sourceReference': map['sourceReference'],
      'observedAt': map['observedAt'],
      'quality': map['quality'],
      ..._map(map['observations'], 'observations'),
    };
    final errorsRaw = map['validationErrors'];
    if (errorsRaw is! List || errorsRaw.any((value) => value is! String)) {
      throw const FormatException('validationErrors must be strings');
    }
    final subjectMap = schemaVersion >= 8
        ? _map(map['subjectAssessment'], 'subjectAssessment')
        : const <String, dynamic>{};
    return VisionV2ShadowResponse(
      schemaVersion: schemaVersion as int,
      inputAssessment: schemaVersion >= 7
          ? VisionInputAssessment.fromWireName(
              map['inputAssessment']?.toString() ?? '',
            )
          : VisionInputAssessment.validSingleItem,
      subjectAssessment: schemaVersion >= 8
          ? VisionSubjectAssessment.fromMap(subjectMap)
          : const VisionSubjectAssessment(
              subjectCountEstimate: 1,
              cardinality: VisionSubjectCardinality.singleItemSupported,
              primarySubjectPresent: true,
              sameItemConsistency: VisionSameItemConsistency.sameItemSupported,
              subjectDomain: VisionSubjectDomain.unknown,
              framing: VisionFramingClass.fullItem,
              reasonCodes: ['legacy_schema_subject_unknown'],
            ),
      framingAttestations: schemaVersion >= 9
          ? VisionFramingAttestations.fromMap(
              _map(subjectMap['framingAttestations'], 'framingAttestations'),
            )
          : null,
      observations: ClothingObservationBundle.fromMap(observationMap),
      identityCandidates: List.unmodifiable(candidates),
      validationErrors: List.unmodifiable(errorsRaw.cast<String>()..sort()),
      diagnostics: VisionV2Diagnostics.fromMap(
        _map(map['diagnostics'], 'diagnostics'),
      ),
    );
  }
}

class VisionV2ShadowClient {
  const VisionV2ShadowClient({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<VisionV2ShadowResponse> analyze(
    String imageUrl, {
    required String idToken,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final client = _client ?? http.Client();
    final ownsClient = _client == null;
    try {
      final canonicalTypes =
          ClothingKnowledgeBase.allItems
              .map((item) => item.canonicalType)
              .toList()
            ..sort();
      final response = await client
          .post(
            Uri.parse(visionV2ShadowEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'imageUrl': imageUrl,
              'canonicalTypes': canonicalTypes,
            }),
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw FormatException(
          'Vision v2 shadow HTTP ${response.statusCode}: ${response.body}',
        );
      }
      return VisionV2ShadowResponse.fromJson(
        response.body,
        allowedCanonicalTypes: canonicalTypes.toSet(),
      );
    } finally {
      if (ownsClient) client.close();
    }
  }
}

class VisionV2ShadowAnalysis {
  const VisionV2ShadowAnalysis({
    required this.response,
    required this.observationEvidence,
    required this.identityEvidence,
    required this.qualifiedIdentityEvidence,
    required this.identityQualification,
    required this.framingQualification,
    required this.negativeClaimCorroboration,
    required this.visibilityQualification,
    required this.applicabilityQualification,
    required this.multiPhotoConsistency,
    required this.multiPhotoAssessment,
    required this.observationQualification,
    required this.familyIdentity,
    required this.capabilityEvidence,
    required this.knowledgeBaseEvidence,
    required this.consistency,
    required this.resolvedProfile,
    required this.v1Summary,
  });

  final VisionV2ShadowResponse response;
  final List<ProfileEvidence> observationEvidence;
  final List<ProfileEvidence> identityEvidence;
  final List<ProfileEvidence> qualifiedIdentityEvidence;
  final VisionIdentityQualificationReport identityQualification;
  final List<VisionFramingAttestationReport> framingQualification;
  final List<NegativeClaimCorroborationReport> negativeClaimCorroboration;
  final List<VisionVisibilityTrustReport> visibilityQualification;
  final List<VisionApplicabilityReport> applicabilityQualification;
  final VisionMultiPhotoConsistency multiPhotoConsistency;
  final VisionMultiPhotoConsistencyAssessment multiPhotoAssessment;
  final ObservationAbsenceQualificationReport? observationQualification;
  final VisionFamilyIdentityReport familyIdentity;
  final List<ProfileEvidence> capabilityEvidence;
  final List<ProfileEvidence> knowledgeBaseEvidence;
  final CanonicalConsistencyReport consistency;
  final ResolvedWardrobeItemProfile resolvedProfile;
  final Map<String, Object?> v1Summary;

  List<ProfileEvidence> get allEvidence => List.unmodifiable([
    ...observationEvidence,
    ...qualifiedIdentityEvidence,
    ...capabilityEvidence,
    ...knowledgeBaseEvidence,
  ]);

  Map<String, Object?> toMap() => {
    'schemaVersion': response.schemaVersion,
    'analysisId': response.observations.analysisId,
    'quality': response.observations.quality.toMap(),
    'observations': response.observations.toMap(),
    'identityCandidates': response.identityCandidates
        .map((item) => item.toMap())
        .toList(),
    'identityQualification': qualifiedIdentityEvidence
        .map((item) => item.toMap())
        .toList(),
    'identityQualificationReport': identityQualification.toMap(),
    'inputAssessment': response.inputAssessment.wireName,
    'subjectAssessment': response.subjectAssessment.toMap(),
    'framingQualification': framingQualification
        .map((item) => item.toMap())
        .toList(),
    'negativeClaimCorroboration': negativeClaimCorroboration
        .map((item) => item.toMap())
        .toList(),
    'multiPhotoConsistency': multiPhotoConsistency.name,
    'multiPhotoAssessment': multiPhotoAssessment.toMap(),
    'applicabilityQualification': applicabilityQualification
        .map((item) => item.toMap())
        .toList(),
    'visibilityQualification': visibilityQualification
        .map((item) => item.toMap())
        .toList(),
    if (observationQualification != null)
      'observationQualification': observationQualification!.toMap(),
    'familyIdentity': familyIdentity.toMap(),
    'capabilityEvidence': capabilityEvidence
        .map((item) => item.toMap())
        .toList(),
    'consistency': consistency.toMap(),
    'resolvedProfile': _resolvedProfileSummary(resolvedProfile),
    'validationErrors': response.validationErrors,
    'diagnostics': response.diagnostics.toMap(),
    'v1Summary': Map.unmodifiable(v1Summary),
  };
}

/// Passive diagnostic boundary for deterministic provider-oracle tests.
///
/// Production callers leave this unset. Implementations must observe only:
/// changing either value would change qualification semantics.
abstract interface class VisionObservationEvidenceTraceSink {
  void beforeInvocation(ClothingObservationBundle input);

  void afterInvocation(
    ClothingObservationBundle input,
    List<ProfileEvidence> output,
  );
}

/// Passive diagnostic boundary for deterministic framing-attestor oracles.
///
/// Production callers leave this unset. The sink observes the exact typed
/// arguments and return value without participating in qualification.
abstract interface class VisionFramingAttestationTraceSink {
  void beforeInvocation({
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment subject,
    required ObservationImageQuality quality,
    required VisionFramingAttestations? attestations,
  });

  void afterInvocation({
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment subject,
    required ObservationImageQuality quality,
    required VisionFramingAttestations? attestations,
    required VisionFramingAttestationReport output,
  });
}

/// Passive diagnostic boundary for applicability-provider oracle capture.
abstract interface class VisionApplicabilityTraceSink {
  void beforeInvocation({
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
  });

  void afterInvocation({
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
    required VisionApplicabilityReport output,
  });
}

/// Passive diagnostic boundary for visibility-trust oracle capture.
abstract interface class VisionVisibilityTrustTraceSink {
  void beforeInvocation({
    required ClothingObservationBundle bundle,
    required VisionInputAssessment inputAssessment,
    required int viewCount,
    required Map<String, Set<ObservationVisualRegion>> complementaryRegions,
  });

  void afterInvocation({
    required ClothingObservationBundle bundle,
    required VisionInputAssessment inputAssessment,
    required int viewCount,
    required Map<String, Set<ObservationVisualRegion>> complementaryRegions,
    required VisionVisibilityTrustReport output,
  });
}

/// Passive diagnostic boundary for canonical-consistency oracle capture.
abstract interface class CanonicalConsistencyTraceSink {
  void beforeInvocation({
    required List<ProfileEvidence> identityEvidence,
    required List<ProfileEvidence> observationEvidence,
  });

  void afterInvocation({
    required List<ProfileEvidence> identityEvidence,
    required List<ProfileEvidence> observationEvidence,
    required CanonicalConsistencyReport output,
  });
}

/// Passive diagnostic boundary for negative-claim provider oracles.
///
/// Production callers leave this unset. The sink observes the exact prepared
/// arguments and return value without participating in qualification.
abstract interface class VisionNegativeClaimCorroborationTraceSink {
  void beforeInvocation({
    required int viewIndex,
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
    required VisionFramingAttestationReport framing,
    required int viewCount,
    required bool sameItemViews,
    required Map<String, Set<ObservationVisualRegion>> complementaryRegions,
    required Set<String> conflictingPositiveProperties,
  });

  void afterInvocation({
    required int viewIndex,
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
    required VisionFramingAttestationReport framing,
    required int viewCount,
    required bool sameItemViews,
    required Map<String, Set<ObservationVisualRegion>> complementaryRegions,
    required Set<String> conflictingPositiveProperties,
    required NegativeClaimCorroborationReport output,
  });
}

/// Passive diagnostic boundary for observation-absence provider oracles.
///
/// Production callers leave this unset. The sink observes the exact prepared
/// corroboration-qualified bundles and the absence-qualifier return value
/// immediately before VisionObservationEvidenceProvider.
abstract interface class ObservationAbsenceQualificationTraceSink {
  void beforeInvocation({required List<ClothingObservationBundle> bundles});

  void afterInvocation({
    required List<ClothingObservationBundle> bundles,
    required ObservationAbsenceQualificationReport output,
  });
}

/// Passive diagnostic boundary for identity-qualification stage oracles.
///
/// Production callers leave this unset. The sink observes the exact prepared
/// arguments and return value immediately before VisionFamilyIdentityResolver.
abstract interface class VisionIdentityQualificationTraceSink {
  void beforeInvocation({
    required List<ProfileEvidence> identityEvidence,
    required CanonicalConsistencyReport consistency,
    required Map<String, ({List<String> defining, List<String> supporting})>
    declaredByEvidenceId,
    required bool inputIsValid,
  });

  void afterInvocation({
    required List<ProfileEvidence> identityEvidence,
    required CanonicalConsistencyReport consistency,
    required Map<String, ({List<String> defining, List<String> supporting})>
    declaredByEvidenceId,
    required bool inputIsValid,
    required List<ProfileEvidence> qualifiedIdentityEvidence,
    required VisionIdentityQualificationReport report,
  });
}

/// Passive diagnostic boundary for family-identity resolver oracles.
///
/// Production callers leave this unset. The sink observes the exact prepared
/// arguments and return value immediately before KB prior / profile resolver.
abstract interface class VisionFamilyIdentityTraceSink {
  void beforeInvocation({
    required List<VisionFamilyIdentityInput> identityCandidates,
    required ClothingObservationBundle observations,
    required String? resolvedCanonicalSubtype,
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment? subjectAssessment,
    required bool hasWholeItemSilhouette,
  });

  void afterInvocation({
    required List<VisionFamilyIdentityInput> identityCandidates,
    required ClothingObservationBundle observations,
    required String? resolvedCanonicalSubtype,
    required VisionInputAssessment inputAssessment,
    required VisionSubjectAssessment? subjectAssessment,
    required bool hasWholeItemSilhouette,
    required VisionFamilyIdentityReport output,
  });
}

/// Passive diagnostic boundary for wardrobe KB prior provider oracles.
///
/// Production callers leave this unset. The sink observes the exact prepared
/// arguments and return value immediately before WardrobeProfileResolver.
abstract interface class WardrobeKnowledgeBasePriorTraceSink {
  void beforeInvocation({
    required Map<String, dynamic> document,
    required List<ProfileEvidence> existingEvidence,
  });

  void afterInvocation({
    required Map<String, dynamic> document,
    required List<ProfileEvidence> existingEvidence,
    required List<ProfileEvidence> output,
  });
}

/// Passive diagnostic boundary for wardrobe profile resolver oracles.
///
/// Production callers leave this unset. The sink observes the exact prepared
/// arguments and return value immediately before QualifiedVisionPersistenceMapper.
abstract interface class WardrobeProfileResolverTraceSink {
  void beforeInvocation({
    required String itemId,
    required List<ProfileEvidence> evidence,
  });

  void afterInvocation({
    required String itemId,
    required List<ProfileEvidence> evidence,
    required ResolvedWardrobeItemProfile output,
  });
}

final class VisionV2ShadowOrchestrator {
  const VisionV2ShadowOrchestrator();

  VisionV2ShadowAnalysis analyze({
    required String itemId,
    required VisionV2ShadowResponse response,
    Iterable<VisionV2ShadowResponse> additionalResponses = const [],
    VisionMultiViewSubjectBinding multiViewSubjectBinding =
        VisionMultiViewSubjectBinding.undeclared,
    Map<String, Object?> v1Summary = const {},
    VisionObservationEvidenceTraceSink? observationEvidenceTraceSink,
    VisionFramingAttestationTraceSink? framingAttestationTraceSink,
    VisionApplicabilityTraceSink? applicabilityTraceSink,
    VisionVisibilityTrustTraceSink? visibilityTrustTraceSink,
    CanonicalConsistencyTraceSink? canonicalConsistencyTraceSink,
    VisionNegativeClaimCorroborationTraceSink?
    negativeClaimCorroborationTraceSink,
    ObservationAbsenceQualificationTraceSink?
    observationAbsenceQualificationTraceSink,
    VisionIdentityQualificationTraceSink? identityQualificationTraceSink,
    VisionFamilyIdentityTraceSink? familyIdentityTraceSink,
    WardrobeKnowledgeBasePriorTraceSink? knowledgeBasePriorTraceSink,
    WardrobeProfileResolverTraceSink? wardrobeProfileResolverTraceSink,
  }) {
    final responses = [response, ...additionalResponses];
    final framingQualification = <VisionFramingAttestationReport>[];
    for (final item in responses) {
      framingAttestationTraceSink?.beforeInvocation(
        inputAssessment: item.inputAssessment,
        subject: item.subjectAssessment,
        quality: item.observations.quality,
        attestations: item.framingAttestations,
      );
      final output = const VisionFramingAttestor().attest(
        inputAssessment: item.inputAssessment,
        subject: item.subjectAssessment,
        quality: item.observations.quality,
        attestations: item.framingAttestations,
      );
      framingAttestationTraceSink?.afterInvocation(
        inputAssessment: item.inputAssessment,
        subject: item.subjectAssessment,
        quality: item.observations.quality,
        attestations: item.framingAttestations,
        output: output,
      );
      framingQualification.add(output);
    }
    final systemSubjects = List.generate(
      responses.length,
      (index) => framingQualification[index].applyTo(
        responses[index].subjectAssessment,
      ),
    );
    final combinedInputAssessment =
        responses.every((item) => item.inputAssessment.isValid)
        ? VisionInputAssessment.validSingleItem
        : responses
              .map((item) => item.inputAssessment)
              .firstWhere((item) => !item.isValid);
    final declaredByEvidenceId =
        <String, ({List<String> defining, List<String> supporting})>{};
    final complementaryRegions = _complementaryRegions(
      responses.map((item) => item.observations),
    );
    final conflictingPositiveProperties = _negativePositiveConflicts(
      responses.map((item) => item.observations),
    );
    final multiPhotoAssessment = assessMultiPhotoConsistency(
      systemSubjects,
      binding: multiViewSubjectBinding,
    );
    final multiPhotoConsistency = multiPhotoAssessment.physicalIdentity;
    final applicabilityQualification = <VisionApplicabilityReport>[];
    if (responses.every((item) => item.schemaVersion >= 8)) {
      for (var index = 0; index < responses.length; index++) {
        final bundle = responses[index].observations;
        final subject = systemSubjects[index];
        applicabilityTraceSink?.beforeInvocation(
          bundle: bundle,
          subject: subject,
        );
        final output = const VisionPropertyApplicabilityQualifier().qualify(
          bundle: bundle,
          subject: subject,
        );
        applicabilityTraceSink?.afterInvocation(
          bundle: bundle,
          subject: subject,
          output: output,
        );
        applicabilityQualification.add(output);
      }
    }
    final applicabilityQualifiedBundles = applicabilityQualification.isEmpty
        ? responses.map((item) => item.observations).toList()
        : applicabilityQualification
              .map((item) => item.qualifiedBundle)
              .toList();
    final visibilityQualification = <VisionVisibilityTrustReport>[];
    if (responses.every((item) => item.schemaVersion >= 7)) {
      for (var index = 0; index < responses.length; index++) {
        final bundle = applicabilityQualifiedBundles[index];
        final inputAssessment = responses[index].inputAssessment;
        visibilityTrustTraceSink?.beforeInvocation(
          bundle: bundle,
          inputAssessment: inputAssessment,
          viewCount: responses.length,
          complementaryRegions: complementaryRegions,
        );
        final output = const VisionVisibilityTrustQualifier().qualify(
          bundle: bundle,
          inputAssessment: inputAssessment,
          viewCount: responses.length,
          complementaryRegions: complementaryRegions,
        );
        visibilityTrustTraceSink?.afterInvocation(
          bundle: bundle,
          inputAssessment: inputAssessment,
          viewCount: responses.length,
          complementaryRegions: complementaryRegions,
          output: output,
        );
        visibilityQualification.add(output);
      }
    }
    final visibilityQualifiedBundles = visibilityQualification.isEmpty
        ? responses.map((item) => item.observations)
        : visibilityQualification.map((item) => item.qualifiedBundle);
    final negativeClaimCorroboration = <NegativeClaimCorroborationReport>[];
    if (responses.every((item) => item.schemaVersion >= 9)) {
      for (var index = 0; index < responses.length; index++) {
        final bundle = visibilityQualifiedBundles.elementAt(index);
        final subject = systemSubjects[index];
        final framing = framingQualification[index];
        final sameItemViews = multiPhotoAssessment.sameItemViews;
        negativeClaimCorroborationTraceSink?.beforeInvocation(
          viewIndex: index,
          bundle: bundle,
          subject: subject,
          framing: framing,
          viewCount: responses.length,
          sameItemViews: sameItemViews,
          complementaryRegions: complementaryRegions,
          conflictingPositiveProperties: conflictingPositiveProperties,
        );
        final output = const VisionNegativeClaimCorroborator().qualify(
          bundle: bundle,
          subject: subject,
          framing: framing,
          viewCount: responses.length,
          sameItemViews: sameItemViews,
          complementaryRegions: complementaryRegions,
          conflictingPositiveProperties: conflictingPositiveProperties,
        );
        negativeClaimCorroborationTraceSink?.afterInvocation(
          viewIndex: index,
          bundle: bundle,
          subject: subject,
          framing: framing,
          viewCount: responses.length,
          sameItemViews: sameItemViews,
          complementaryRegions: complementaryRegions,
          conflictingPositiveProperties: conflictingPositiveProperties,
          output: output,
        );
        negativeClaimCorroboration.add(output);
      }
    }
    final List<ClothingObservationBundle> corroborationQualifiedBundles =
        (negativeClaimCorroboration.isEmpty
                ? visibilityQualifiedBundles
                : negativeClaimCorroboration.map(
                    (item) => item.qualifiedBundle,
                  ))
            .toList(growable: false);
    ObservationAbsenceQualificationReport? observationQualification;
    if (responses.every((item) => item.schemaVersion >= 6)) {
      observationAbsenceQualificationTraceSink?.beforeInvocation(
        bundles: corroborationQualifiedBundles,
      );
      final output = const ObservationAbsenceQualifier().qualifyBundles(
        corroborationQualifiedBundles,
      );
      observationAbsenceQualificationTraceSink?.afterInvocation(
        bundles: corroborationQualifiedBundles,
        output: output,
      );
      observationQualification = output;
    }
    final qualifiedObservationBundles = observationQualification == null
        ? responses.map((item) => item.observations)
        : [observationQualification.qualifiedBundle];
    final observationEvidence = <ProfileEvidence>[];
    for (final input in qualifiedObservationBundles) {
      observationEvidenceTraceSink?.beforeInvocation(input);
      final output = const VisionObservationEvidenceProvider().provide(input);
      observationEvidenceTraceSink?.afterInvocation(input, output);
      observationEvidence.addAll(output);
    }
    observationEvidence.sort((left, right) => left.id.compareTo(right.id));
    final identityEvidence = responses.expand((item) {
      return item.identityCandidates.map((candidate) {
        final evidenceId =
            'vision-identity:${item.observations.analysisId}:'
            '${candidate.canonicalType}';
        declaredByEvidenceId[evidenceId] = (
          defining: List.unmodifiable(
            candidate.definingObservations.toSet().toList()..sort(),
          ),
          supporting: List.unmodifiable(
            candidate.supportingObservations.toSet().toList()..sort(),
          ),
        );
        return ProfileEvidence(
          id: evidenceId,
          property: WardrobeProfileProperty.canonicalType,
          value: candidate.canonicalType,
          source: EvidenceSource.aiInference,
          nature: EvidenceNature.inferred,
          confidence: candidate.confidence,
          method: 'vision_v2_identity_candidate',
          createdAt: item.observations.observedAt,
          modelVersion: item.observations.modelVersion,
          sourceReference: item.observations.sourceReference,
        );
      });
    }).toList()..sort((left, right) => left.id.compareTo(right.id));
    canonicalConsistencyTraceSink?.beforeInvocation(
      identityEvidence: identityEvidence,
      observationEvidence: observationEvidence,
    );
    final consistency = const CanonicalObservationConsistencyValidator()
        .validate(
          identityEvidence: identityEvidence,
          observationEvidence: observationEvidence,
        );
    canonicalConsistencyTraceSink?.afterInvocation(
      identityEvidence: identityEvidence,
      observationEvidence: observationEvidence,
      output: consistency,
    );
    final inputIsValid =
        responses.every(
          (item) =>
              item.inputAssessment.isValid &&
              (item.schemaVersion < 8 ||
                  systemSubjects[responses.indexOf(item)].permitsCanonical &&
                      framingQualification[responses.indexOf(item)]
                          .hasWholeItemSilhouette),
        ) &&
        multiPhotoAssessment.permitsIdentityPromotion;
    identityQualificationTraceSink?.beforeInvocation(
      identityEvidence: identityEvidence,
      consistency: consistency,
      declaredByEvidenceId: declaredByEvidenceId,
      inputIsValid: inputIsValid,
    );
    final qualification = const VisionIdentityQualifier().qualify(
      identityEvidence,
      consistency,
      declaredByEvidenceId,
      inputIsValid: inputIsValid,
    );
    identityQualificationTraceSink?.afterInvocation(
      identityEvidence: identityEvidence,
      consistency: consistency,
      declaredByEvidenceId: declaredByEvidenceId,
      inputIsValid: inputIsValid,
      qualifiedIdentityEvidence: qualification.evidence,
      report: qualification.report,
    );
    final qualifiedIdentity = qualification.evidence;
    final familyCandidates = responses
        .expand(
          (item) => item.identityCandidates.map(
            (candidate) => VisionFamilyIdentityInput(
              canonicalType: candidate.canonicalType,
              confidence: candidate.confidence,
            ),
          ),
        )
        .toList(growable: false);
    final familyInputAssessment = multiPhotoAssessment.permitsIdentityPromotion
        ? combinedInputAssessment
        : VisionInputAssessment.ambiguousSubject;
    final familySubjectAssessment = response.schemaVersion >= 8
        ? systemSubjects.first
        : null;
    final familyHasWholeItemSilhouette =
        response.schemaVersion < 9 ||
        framingQualification.first.hasWholeItemSilhouette;
    familyIdentityTraceSink?.beforeInvocation(
      identityCandidates: familyCandidates,
      observations: response.observations,
      resolvedCanonicalSubtype: qualification.report.selectedCanonicalType,
      inputAssessment: familyInputAssessment,
      subjectAssessment: familySubjectAssessment,
      hasWholeItemSilhouette: familyHasWholeItemSilhouette,
    );
    final familyIdentity = const VisionFamilyIdentityResolver().resolve(
      identityCandidates: familyCandidates,
      // Family identity intentionally consumes the raw, typed observation
      // bundle. Its tier policy can use partial positive silhouette/
      // construction evidence without promoting it into subtype evidence.
      // Invalid inputs are still rejected through [combinedInputAssessment].
      observations: response.observations,
      resolvedCanonicalSubtype: qualification.report.selectedCanonicalType,
      inputAssessment: familyInputAssessment,
      subjectAssessment: familySubjectAssessment,
      hasWholeItemSilhouette: familyHasWholeItemSilhouette,
    );
    familyIdentityTraceSink?.afterInvocation(
      identityCandidates: familyCandidates,
      observations: response.observations,
      resolvedCanonicalSubtype: qualification.report.selectedCanonicalType,
      inputAssessment: familyInputAssessment,
      subjectAssessment: familySubjectAssessment,
      hasWholeItemSilhouette: familyHasWholeItemSilhouette,
      output: familyIdentity,
    );
    final capabilityEvidence = const WardrobeCapabilityInferenceProvider()
        .infer(
          inferenceId: response.observations.analysisId,
          evidence: observationEvidence,
          createdAt: response.observations.observedAt,
        );
    final initialEvidence = <ProfileEvidence>[
      ...observationEvidence,
      ...qualifiedIdentity,
      ...capabilityEvidence,
    ];
    const kbDocument = <String, dynamic>{};
    knowledgeBasePriorTraceSink?.beforeInvocation(
      document: kbDocument,
      existingEvidence: initialEvidence,
    );
    final kbEvidence = const WardrobeKnowledgeBasePriorProvider().provide(
      document: kbDocument,
      existingEvidence: initialEvidence,
    );
    knowledgeBasePriorTraceSink?.afterInvocation(
      document: kbDocument,
      existingEvidence: initialEvidence,
      output: kbEvidence,
    );
    final allEvidence = [...initialEvidence, ...kbEvidence];
    wardrobeProfileResolverTraceSink?.beforeInvocation(
      itemId: itemId,
      evidence: allEvidence,
    );
    final resolvedProfile = const WardrobeProfileResolver().resolve(
      itemId: itemId,
      evidence: allEvidence,
    );
    wardrobeProfileResolverTraceSink?.afterInvocation(
      itemId: itemId,
      evidence: allEvidence,
      output: resolvedProfile,
    );
    return VisionV2ShadowAnalysis(
      response: response,
      observationEvidence: observationEvidence,
      identityEvidence: List.unmodifiable(identityEvidence),
      qualifiedIdentityEvidence: qualifiedIdentity,
      identityQualification: qualification.report,
      framingQualification: List.unmodifiable(framingQualification),
      negativeClaimCorroboration: List.unmodifiable(negativeClaimCorroboration),
      visibilityQualification: List.unmodifiable(visibilityQualification),
      applicabilityQualification: List.unmodifiable(applicabilityQualification),
      multiPhotoConsistency: multiPhotoConsistency,
      multiPhotoAssessment: multiPhotoAssessment,
      observationQualification: observationQualification,
      familyIdentity: familyIdentity,
      capabilityEvidence: capabilityEvidence,
      knowledgeBaseEvidence: kbEvidence,
      consistency: consistency,
      resolvedProfile: resolvedProfile,
      v1Summary: Map.unmodifiable(Map<String, Object?>.from(v1Summary)),
    );
  }
}

/// Pure identity-qualification stage extracted from the shadow orchestrator.
///
/// Behavior-neutral helper used by production orchestration and oracle export.
final class VisionIdentityQualifier {
  const VisionIdentityQualifier();

  ({List<ProfileEvidence> evidence, VisionIdentityQualificationReport report})
  qualify(
    List<ProfileEvidence> candidates,
    CanonicalConsistencyReport report,
    Map<String, ({List<String> defining, List<String> supporting})>
    declaredByEvidenceId, {
    required bool inputIsValid,
  }) {
    const validator = CanonicalObservationConsistencyValidator();
    final byId = {
      for (final result in report.results) result.identityEvidenceId: result,
    };
    final assessments = candidates.map((item) {
      final result = byId[item.id];
      final level =
          result?.compatibilityLevel ?? CanonicalCompatibilityLevel.uncertain;
      final compatibilityCap = switch (level) {
        CanonicalCompatibilityLevel.strong => 0.85,
        CanonicalCompatibilityLevel.compatible => 0.65,
        CanonicalCompatibilityLevel.uncertain => 0.35,
        CanonicalCompatibilityLevel.conflicting => 0.0,
      };
      final declared =
          declaredByEvidenceId[item.id] ??
          (defining: const <String>[], supporting: const <String>[]);
      final definingSupports = result?.definingEvidence ?? const [];
      final acceptedSupporting =
          (result?.supportingOnlyEvidence ?? const <String>[])
              .where(
                (path) => declared.supporting.contains(_observationName(path)),
              )
              .toList()
            ..sort();
      final acceptedDefining =
          definingSupports
              .where(
                (path) => declared.defining.contains(_observationName(path)),
              )
              .toList()
            ..sort();
      final rejectedSupporting =
          declared.supporting
              .where(
                (name) =>
                    !(result?.supportingOnlyEvidence.any(
                          (path) => _observationName(path) == name,
                        ) ??
                        false),
              )
              .toList()
            ..sort();
      final rejectedDefining =
          declared.defining
              .where(
                (name) => !definingSupports.any(
                  (path) => _observationName(path) == name,
                ),
              )
              .toList()
            ..sort();
      final minimumDefining = validator.minimumDefiningSupportsFor(
        item.value as String,
      );
      final hasRequiredDefining = acceptedDefining.length >= minimumDefining;
      final semanticCap = hasRequiredDefining ? 1.0 : 0.49;
      final totalDeclared = {
        ...declared.defining,
        ...declared.supporting,
      }.length;
      final declaredSupportCap = item.confidence > 0.70 && totalDeclared < 2
          ? 0.60
          : 1.0;
      final cap = [
        compatibilityCap,
        semanticCap,
        declaredSupportCap,
      ].reduce((left, right) => left < right ? left : right);
      final confidence = item.confidence < cap ? item.confidence : cap;
      final state = switch (level) {
        CanonicalCompatibilityLevel.conflicting =>
          VisionIdentityState.conflicting,
        CanonicalCompatibilityLevel.uncertain =>
          VisionIdentityState.insufficientEvidence,
        _ when !hasRequiredDefining => VisionIdentityState.insufficientEvidence,
        CanonicalCompatibilityLevel.strong when confidence >= 0.70 =>
          VisionIdentityState.confirmed,
        _ when confidence >= 0.50 => VisionIdentityState.supported,
        _ => VisionIdentityState.insufficientEvidence,
      };
      final reasons = <String>[
        'consistency:${level.wireName}',
        'semantic_defining:${acceptedDefining.length}/$minimumDefining',
        if (rejectedSupporting.isNotEmpty)
          'rejected_declared_supports:${rejectedSupporting.length}',
        if (rejectedDefining.isNotEmpty)
          'rejected_declared_defining:${rejectedDefining.length}',
        if (result?.reasonCodes.contains('missing_signature_coverage') ?? false)
          'missing_signature_coverage',
        if (!hasRequiredDefining) 'missing_required_defining_support',
      ]..sort();
      return (
        evidence: item,
        confidence: confidence,
        state: state,
        supporting: List<String>.unmodifiable(acceptedSupporting),
        defining: List<String>.unmodifiable(acceptedDefining),
        declaredDefining: List<String>.unmodifiable(declared.defining),
        declaredSupporting: List<String>.unmodifiable(declared.supporting),
        rejectedSupporting: List<String>.unmodifiable(rejectedSupporting),
        rejectedDefining: List<String>.unmodifiable(rejectedDefining),
        missing: result?.missingDefiningEvidence ?? const <String>[],
        missingSignature:
            result?.reasonCodes.contains('missing_signature_coverage') ?? false,
        reasons: List<String>.unmodifiable(reasons),
      );
    }).toList();

    final viable =
        assessments
            .where(
              (item) =>
                  inputIsValid &&
                  (item.state == VisionIdentityState.confirmed ||
                      item.state == VisionIdentityState.supported),
            )
            .toList()
          ..sort((left, right) {
            final state = _identityStateRank(
              right.state,
            ).compareTo(_identityStateRank(left.state));
            if (state != 0) return state;
            final defining = right.defining.length.compareTo(
              left.defining.length,
            );
            if (defining != 0) return defining;
            final confidence = right.confidence.compareTo(left.confidence);
            if (confidence != 0) return confidence;
            return (left.evidence.value as String).compareTo(
              right.evidence.value as String,
            );
          });
    final topMargin = viable.length >= 2
        ? viable[0].confidence - viable[1].confidence
        : null;
    final ambiguous =
        viable.length >= 2 &&
        viable[0].evidence.value != viable[1].evidence.value &&
        _identityStateRank(viable[0].state) ==
            _identityStateRank(viable[1].state) &&
        topMargin! < 0.10;
    final selected = ambiguous || viable.isEmpty ? null : viable.first;
    final overallState = !inputIsValid
        ? VisionIdentityState.insufficientEvidence
        : ambiguous
        ? VisionIdentityState.ambiguous
        : selected?.state ??
              (assessments.any(
                    (item) => item.state == VisionIdentityState.conflicting,
                  )
                  ? VisionIdentityState.conflicting
                  : VisionIdentityState.insufficientEvidence);

    final qualified = assessments.map((assessment) {
      final active =
          inputIsValid &&
          selected != null &&
          selected.evidence.id == assessment.evidence.id;
      return ProfileEvidence(
        id: '${assessment.evidence.id}:qualified',
        property: assessment.evidence.property,
        value: assessment.evidence.value,
        source: assessment.evidence.source,
        nature: assessment.evidence.nature,
        confidence: assessment.confidence,
        active: active,
        method:
            '${assessment.evidence.method}:'
            'consistency_${byId[assessment.evidence.id]?.compatibilityLevel.wireName ?? 'uncertain'}:'
            'support_${{...assessment.supporting, ...assessment.defining}.length}:'
            '${active ? 'qualified' : 'deactivated'}:'
            'semantic_${assessment.state.wireName}:'
            'defining_${assessment.defining.length}:'
            'safe_identity_v1',
        createdAt: assessment.evidence.createdAt,
        modelVersion: assessment.evidence.modelVersion,
        sourceReference: assessment.evidence.id,
      );
    }).toList()..sort((left, right) => left.id.compareTo(right.id));
    final candidateReports =
        assessments
            .map(
              (item) => VisionIdentityCandidateQualification(
                canonicalType: item.evidence.value as String,
                rawConfidence: item.evidence.confidence,
                qualifiedConfidence: item.confidence,
                state:
                    ambiguous &&
                        (item.state == VisionIdentityState.confirmed ||
                            item.state == VisionIdentityState.supported)
                    ? VisionIdentityState.ambiguous
                    : item.state,
                usedDefiningSupports: item.defining,
                usedSupportingObservations: item.supporting,
                modelDeclaredDefining: item.declaredDefining,
                modelDeclaredSupporting: item.declaredSupporting,
                rejectedSupportingObservations: item.rejectedSupporting,
                rejectedDefiningObservations: item.rejectedDefining,
                missingDefiningEvidence: item.missing,
                missingSignatureCoverage: item.missingSignature,
                reasonCodes: item.reasons,
              ),
            )
            .toList()
          ..sort(
            (left, right) => left.canonicalType.compareTo(right.canonicalType),
          );
    return (
      evidence: List.unmodifiable(qualified),
      report: VisionIdentityQualificationReport(
        state: overallState,
        selectedCanonicalType: selected?.evidence.value as String?,
        topMargin: topMargin,
        candidates: List.unmodifiable(candidateReports),
      ),
    );
  }
}

int _identityStateRank(VisionIdentityState state) => switch (state) {
  VisionIdentityState.confirmed => 2,
  VisionIdentityState.supported => 1,
  _ => 0,
};

String _observationName(String propertyPath) => propertyPath.split('.').last;

Map<String, Set<ObservationVisualRegion>> _complementaryRegions(
  Iterable<ClothingObservationBundle> bundles,
) {
  final result = <String, Set<ObservationVisualRegion>>{};
  void add<T>(String property, ObservationValue<T>? value) {
    if (value == null) return;
    result.putIfAbsent(property, () => {}).addAll(value.visibleRegions);
  }

  for (final item in bundles) {
    add('coverage', item.coverage);
    add('hasHood', item.hasHood);
    add('frontClosure', item.frontClosure);
    add('visibleBulk', item.visibleBulk);
    add('necklineShape', item.necklineShape);
    add('visiblePocketStructure', item.visiblePocketStructure);
    add('visibleStretchCue', item.visibleStretchCue);
    add('footwearConstruction', item.footwearConstruction);
    add('footwearFastening', item.footwearFastening);
    add('soleProfile', item.soleProfile);
    add('visibleTread', item.visibleTread);
    add('footwearUpperHeight', item.footwearUpperHeight);
  }
  return result.map(
    (property, regions) => MapEntry(property, Set.unmodifiable(regions)),
  );
}

Set<String> _negativePositiveConflicts(
  Iterable<ClothingObservationBundle> bundles,
) {
  final items = bundles.toList();
  bool conflict<T>(
    ObservationValue<T>? Function(ClothingObservationBundle item) read,
    bool Function(T value) negative,
  ) {
    final values = items
        .map(read)
        .where((value) => value?.isObserved ?? false)
        .map((value) => value!.value as T)
        .toList();
    return values.any(negative) && values.any((value) => !negative(value));
  }

  return {
    if (conflict(
      (item) => item.frontClosure,
      (value) => value == FrontClosure.none,
    ))
      'frontClosure',
    if (conflict(
      (item) => item.visiblePocketStructure,
      (value) => value == VisiblePocketStructure.none,
    ))
      'visiblePocketStructure',
    if (conflict((item) => item.hasHood, (value) => value == false)) 'hasHood',
    if (conflict((item) => item.visibleStretchCue, (value) => value == false))
      'visibleStretchCue',
  };
}

Map<String, dynamic> _map(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

int _nonNegativeInt(Object? value, String label) {
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('$label must be a non-negative number');
  }
  return value.toInt();
}

Map<String, Object?> _resolvedProfileSummary(
  ResolvedWardrobeItemProfile profile,
) => {
  'itemId': profile.itemId,
  'canonicalType': profile.identity.canonicalType.toMap(),
  'warmth': profile.capabilities.warmth.toMap(),
  'formality': profile.capabilities.formality.toMap(),
  'layerRole': profile.capabilities.layerRole.toMap(
    encodeValue: (value) => value.wireName,
  ),
  'supportedLayerRoles': profile.capabilities.supportedLayerRoles.toMap(
    encodeValue: (value) => value.map((role) => role.wireName).toList()..sort(),
  ),
  'mobility': profile.capabilities.mobility.toMap(
    encodeValue: (value) => value.wireName,
  ),
  'breathability': profile.capabilities.breathability.toMap(
    encodeValue: (value) => value.wireName,
  ),
  'windProtection': profile.capabilities.windProtection.toMap(
    encodeValue: (value) => value.wireName,
  ),
  'rainProtection': profile.capabilities.rainProtection.toMap(
    encodeValue: (value) => value.wireName,
  ),
  'walkingComfort': profile.capabilities.walkingComfort.toMap(
    encodeValue: (value) => value.wireName,
  ),
  'traction': profile.capabilities.traction.toMap(
    encodeValue: (value) => value.wireName,
  ),
  'metadata': profile.metadata.toMap(),
};
