/// Internal phases of the AI Stylist pipeline.
///
/// The pipeline can still report detailed phases for diagnostics, but the UI
/// deliberately shows one calm status. Rapidly changing technical labels such
/// as context/weather/wardrobe make a slow response feel like a debug console.
enum StylistChatProgressPhase {
  resolvingContext,
  checkingWeather,
  thinkingWithContext,
  analyzingWardrobe,
  buildingOutfit,
  finalizing,
}

extension StylistChatProgressPhaseUi on StylistChatProgressPhase {
  /// Stable, user-facing copy. Phase detail stays internal/observable only.
  String get labelSk => 'Pripravujem odpoveď…';
}

typedef StylistChatProgressCallback =
    void Function(StylistChatProgressPhase phase);
