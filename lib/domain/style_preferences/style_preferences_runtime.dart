import 'package:flutter/foundation.dart';

import 'style_preference_taste.dart';
import 'styling_presentation.dart';
import 'user_style_preferences.dart';

/// Developer/test gate for *consuming* saved style taste at runtime.
///
/// Does not write or delete `users/{uid}/stylePreferences/main`.
/// Default is off so a development/test build can use an existing wardrobe
/// as a no-taste baseline. Enable with:
/// `--dart-define=STYLE_PREFERENCES_RUNTIME_ENABLED=true`.
abstract final class StylePreferencesRuntime {
  StylePreferencesRuntime._();

  static const enabledDefine = bool.fromEnvironment(
    'STYLE_PREFERENCES_RUNTIME_ENABLED',
    defaultValue: false,
  );

  static const disabledConsumptionFingerprint =
      'tasteRuntime=off:p=no_preference';

  static bool? _debugOverride;

  static bool get enabled => _debugOverride ?? enabledDefine;

  @visibleForTesting
  static void debugOverrideEnabled(bool? value) {
    _debugOverride = value;
  }

  /// Home cache / generation fingerprint. Disabled mode is one stable value
  /// regardless of what is stored in Firestore.
  static String consumptionFingerprint(UserStylePreferences stored) {
    final presentation = stored.stylingPresentation.wireName;
    if (!enabled) return 'tasteRuntime=off:p=$presentation';
    return 'tasteRuntime=on:${stored.homeTasteFingerprint}|p=$presentation';
  }

  /// Outfit-presentation is an explicit composition authority, not a taste
  /// experiment. It remains active independently of the soft-taste rollout.
  static StylingPresentation effectivePresentation(
    UserStylePreferences stored,
  ) => stored.stylingPresentation;

  static UserStylePreferences effectivePreferences(
    UserStylePreferences stored,
  ) {
    return enabled ? stored : UserStylePreferences.empty;
  }

  static StylePreferenceTaste effectiveTaste(UserStylePreferences stored) {
    return StylePreferenceTaste.fromPreferences(effectivePreferences(stored));
  }

  static Map<String, dynamic>? stylistPayload(UserStylePreferences stored) {
    if (enabled) return stored.toStylistPayload();
    if (stored.stylingPresentation == StylingPresentation.noPreference) {
      return null;
    }
    return <String, dynamic>{
      'stylingPresentation': stored.stylingPresentation.wireName,
    };
  }
}
