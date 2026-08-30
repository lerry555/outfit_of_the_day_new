/// User-visible phases for the AI Stylist pipeline.
///
/// This is deliberately phase/progress streaming rather than token streaming:
/// every phase must correspond to real work that has actually started. The
/// frozen candidate selector and deterministic validator remain authoritative;
/// progress updates never carry outfit choices or mutable facts.
enum StylistChatProgressPhase {
  resolvingContext,
  checkingWeather,
  thinkingWithContext,
  analyzingWardrobe,
  buildingOutfit,
  finalizing,
}

extension StylistChatProgressPhaseUi on StylistChatProgressPhase {
  String get labelSk => switch (this) {
    StylistChatProgressPhase.resolvingContext => 'Rozumiem zadaniu…',
    StylistChatProgressPhase.checkingWeather => 'Kontrolujem počasie…',
    StylistChatProgressPhase.thinkingWithContext => 'Vyhodnocujem kontext…',
    StylistChatProgressPhase.analyzingWardrobe => 'Prechádzam tvoj šatník…',
    StylistChatProgressPhase.buildingOutfit => 'Skladám vhodné kombinácie…',
    StylistChatProgressPhase.finalizing => 'Kontrolujem finálny výber…',
  };
}

typedef StylistChatProgressCallback = void Function(
  StylistChatProgressPhase phase,
);
