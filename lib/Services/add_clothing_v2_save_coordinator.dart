import 'package:flutter/foundation.dart';

typedef AddClothingSaveTelemetry =
    void Function(String stage, Map<String, Object?> metadata);

class AddClothingV2PayloadValidation {
  const AddClothingV2PayloadValidation(this.errors);
  final List<String> errors;
  bool get isValid => errors.isEmpty;
}

AddClothingV2PayloadValidation validateAddClothingV2Payload(
  Map<String, dynamic> payload,
) {
  const required = <String>[
    'canonicalType',
    'canonicalFamily',
    'bodySlots',
    'layerPosition',
    'colorProfile',
    'formality',
    'warmth',
    'styles',
    'occasionFit',
    'attributes',
    'fieldSources',
    'fieldConfidence',
    'ontologyVersion',
    'taxonomyVersion',
    'kbVersion',
    'analyzerProvenance',
  ];
  final errors = <String>[];
  for (final key in required) {
    if (!payload.containsKey(key) || payload[key] == null) {
      errors.add('missing:$key');
    }
  }
  if (payload['bodySlots'] is! List || (payload['bodySlots'] as List).isEmpty) {
    errors.add('invalid:bodySlots');
  }
  return AddClothingV2PayloadValidation(errors);
}

/// Enforces the persistence lifecycle used by Add Clothing:
/// validate -> build -> write -> post-write -> navigate.
/// A failed write never navigates and can be retried without analyzer work.
class AddClothingV2SaveCoordinator {
  AddClothingV2SaveCoordinator({AddClothingSaveTelemetry? telemetry})
    : _telemetry = telemetry ?? _defaultTelemetry;

  final AddClothingSaveTelemetry _telemetry;
  bool _inFlight = false;
  bool get inFlight => _inFlight;

  static void _defaultTelemetry(String stage, Map<String, Object?> metadata) {
    debugPrint('[ADD_CLOTHING_V2_SAVE][$stage] $metadata');
  }

  Future<String> persist({
    required Map<String, dynamic> v2Payload,
    required Future<String> Function() write,
    required Future<void> Function(String itemId) afterWrite,
    required void Function(String itemId) navigateAfterSave,
  }) async {
    if (_inFlight) throw StateError('add_clothing_save_already_in_flight');
    _inFlight = true;
    final started = DateTime.now();
    _telemetry('save_started', const {});
    try {
      final validation = validateAddClothingV2Payload(v2Payload);
      if (!validation.isValid) {
        _telemetry('save_validation_failed', {'errors': validation.errors});
        throw StateError(
          'invalid_wardrobe_v2_payload:${validation.errors.join(',')}',
        );
      }
      _telemetry('save_validation_passed', {
        'canonicalType': v2Payload['canonicalType'],
        'fieldCount': v2Payload.length,
      });
      _telemetry('v2_write_builder_passed', {
        'hasStoragePath': v2Payload['storagePath'] != null,
      });
      _telemetry('firestore_write_started', const {});
      final itemId = await write();
      _telemetry('firestore_write_success', {
        'itemId': itemId,
        'latencyMs': DateTime.now().difference(started).inMilliseconds,
      });
      await afterWrite(itemId);
      _telemetry('navigation_after_save', {'itemId': itemId});
      navigateAfterSave(itemId);
      return itemId;
    } catch (error) {
      _telemetry('firestore_write_failed', {
        'errorType': error.runtimeType.toString(),
        'latencyMs': DateTime.now().difference(started).inMilliseconds,
      });
      rethrow;
    } finally {
      _inFlight = false;
    }
  }
}
