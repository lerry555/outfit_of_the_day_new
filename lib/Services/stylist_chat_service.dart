import 'package:cloud_functions/cloud_functions.dart';

class StylistChatService {
  Future<Map<String, dynamic>> sendMessage(
    String message, {
    List<Map<String, String>> history = const [],
    Map<String, dynamic>? weatherContext,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-east1',
      ).httpsCallable('stylistChat');
      final result = await callable.call(<String, dynamic>{
        'message': message,
        'history': history,
        'weatherContext': weatherContext,
      });

      final data = result.data;
      if (data is Map) {
        final reply = data['reply'];
        final suggestedItems = data['suggestedItems'];
        return <String, dynamic>{
          'reply': reply is String
              ? reply
              : 'Niečo sa pokazilo 😅 Skús to prosím ešte raz.',
          'suggestedItems': suggestedItems is List
              ? suggestedItems.whereType<Map>().toList(growable: false)
              : const <Map>[],
        };
      }
    } catch (_) {
      return <String, dynamic>{
        'reply': 'Niečo sa pokazilo 😅 Skús to prosím ešte raz.',
        'suggestedItems': const <Map>[],
      };
    }

    return <String, dynamic>{
      'reply': 'Niečo sa pokazilo 😅 Skús to prosím ešte raz.',
      'suggestedItems': const <Map>[],
    };
  }
}
