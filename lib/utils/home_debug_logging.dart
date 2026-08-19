import 'package:flutter/foundation.dart';

/// Verbose per-item Home debug logs (layer filter, KB normalization, footwear scores, etc.).
///
/// Set to `true` only when debugging wardrobe normalization or scoring detail.
const bool kVerboseHomeLogs = false;

void logVerboseHome(String message) {
  if (!kVerboseHomeLogs || !kDebugMode) return;
  debugPrint(message);
}

/// M11.0 resolved wardrobe pipeline running next to Home production data.
///
/// Debug-only and read-only. Default is off: comparing the full wardrobe on
/// the UI isolate caused Home ANRs. Set to `true` only when debugging
/// profile-vs-legacy drift.
const bool kHomeWardrobeProfileShadowEnabled = false;

/// Controlled M11.0 Home read-path authority.
///
/// Wardrobe V2 is the post-retirement production default. Setting the define
/// explicitly to false is a time-bounded rollback/debug switch.
const bool kUseResolvedWardrobeProfilesInHome = bool.fromEnvironment(
  'USE_RESOLVED_WARDROBE_PROFILES_HOME',
  defaultValue: true,
);

/// Controlled M11.0 AI Stylist Chat read-path authority.
///
/// Wardrobe V2 is the post-retirement production default. False is retained
/// only as an explicit rollback/debug switch.
const bool kUseResolvedWardrobeProfilesInChat = bool.fromEnvironment(
  'USE_RESOLVED_WARDROBE_PROFILES_CHAT',
  defaultValue: true,
);

/// Set by the checked-in release wrapper. A production build fails at startup
/// if either V2 authority flag is accidentally disabled.
const bool kOotdProductionBuild = bool.fromEnvironment(
  'OOTD_PRODUCTION_BUILD',
  defaultValue: false,
);

void verifyWardrobeV2ProductionFlags() {
  if (kOotdProductionBuild &&
      (!kUseResolvedWardrobeProfilesInHome ||
          !kUseResolvedWardrobeProfilesInChat)) {
    throw StateError('production_wardrobe_v2_flags_disabled');
  }
  debugPrint(
    '[WARDROBE_V2_BUILD_FLAGS] production=$kOotdProductionBuild '
    'home=$kUseResolvedWardrobeProfilesInHome '
    'stylist=$kUseResolvedWardrobeProfilesInChat '
    'set016=on shadow=$kHomeWardrobeProfileShadowEnabled',
  );
}

/// Runtime KB-first canonical resolution in [HomeWardrobeNormalizer].
///
/// When `true`, derives `canonical_type` from subCategory/name at normalize time
/// (no Firestore writes). Set to `false` to instantly revert to legacy-only KB gate.
const bool kRuntimeCanonicalResolverEnabled = true;
