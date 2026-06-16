import 'package:flutter/foundation.dart';

/// Verbose per-item Home debug logs (layer filter, KB normalization, footwear scores, etc.).
///
/// Set to `true` only when debugging wardrobe normalization or scoring detail.
const bool kVerboseHomeLogs = false;

void logVerboseHome(String message) {
  if (!kVerboseHomeLogs || !kDebugMode) return;
  debugPrint(message);
}

/// Runtime KB-first canonical resolution in [HomeWardrobeNormalizer].
///
/// When `true`, derives `canonical_type` from subCategory/name at normalize time
/// (no Firestore writes). Set to `false` to instantly revert to legacy-only KB gate.
const bool kRuntimeCanonicalResolverEnabled = true;
