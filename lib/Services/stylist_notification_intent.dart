import 'package:flutter/foundation.dart';

/// Context from a `stylist_reply` FCM tap.
class StylistNotificationIntent {
  const StylistNotificationIntent({this.jobId, this.chatId});

  final String? jobId;
  final String? chatId;

  String get dedupeKey => 'stylist_reply|${jobId ?? ''}|${chatId ?? ''}';
}

/// Last delivered Stylist notification context for the open Stylist tab.
class StylistNotificationIntentStore extends ChangeNotifier {
  StylistNotificationIntentStore._();
  static final StylistNotificationIntentStore instance =
      StylistNotificationIntentStore._();

  StylistNotificationIntent? _current;
  final Set<String> _handledHydrationKeys = <String>{};

  StylistNotificationIntent? get current => _current;

  void replace(StylistNotificationIntent intent) {
    _current = intent;
    notifyListeners();
  }

  bool wasHydrationHandled(String dedupeKey) =>
      _handledHydrationKeys.contains(dedupeKey);

  void markHydrationHandled(String dedupeKey) {
    _handledHydrationKeys.add(dedupeKey);
  }

  void clear() {
    _current = null;
    _handledHydrationKeys.clear();
  }

  @visibleForTesting
  void resetForTest() {
    clear();
  }
}
