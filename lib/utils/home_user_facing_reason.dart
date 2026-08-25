/// Home "Prečo tento outfit?" copy. Internal pipeline labels must never reach UI.
abstract final class HomeUserFacingReason {
  static const _internalExact = <String>{
    'v2_rule_score_fallback',
    'v2_flexible_selection',
    'ai_failed_or_fallback',
    'invalid_response_shape',
    'invalid_selected_index',
    'invalid_json_shape',
    'openai_error',
    'empty_candidates',
    'local_fallback_applied',
    'server_fallback_marker',
  };

  static bool isInternal(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();
    if (_internalExact.contains(lower)) return true;
    if (lower.startsWith('v2 ')) return true;
    if (lower.contains('v2_rule_score_fallback')) return true;
    if (lower.contains('v2_flexible_selection')) return true;
    if (RegExp(r'core=(true|false)').hasMatch(lower)) return true;
    if (RegExp(r'^[a-z0-9_]+$').hasMatch(lower) && lower.contains('_')) {
      return true;
    }
    return false;
  }

  /// Returns [raw] when it is already a human sentence; otherwise null.
  static String? forDisplay(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty || isInternal(text)) return null;
    return text;
  }

  static String fromLocalSelection({
    required int tempC,
    required bool isRainy,
    required bool isWindy,
    required List<String> garmentLabels,
    String? outerwearLabel,
  }) {
    final pieces = garmentLabels
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (pieces.isEmpty) {
      return 'Outfit som zložil podľa dnešného počasia a tvojho šatníka.';
    }
    final listed = _joinSk(pieces.map(_lowerFirst).toList(growable: false));
    final buffer = StringBuffer('Pri $tempC°C som zvolil $listed');
    if (isRainy) {
      buffer.write(', aby kombinácia zvládla aj vlhkejšie počasie');
    } else if (outerwearLabel != null &&
        outerwearLabel.trim().isNotEmpty &&
        tempC <= 12) {
      buffer.write(
        ', pretože pri tejto teplote je ${_lowerFirst(outerwearLabel)} vhodnejšia než ísť bez nej',
      );
    } else if (tempC >= 22 &&
        (outerwearLabel == null || outerwearLabel.trim().isEmpty)) {
      buffer.write(', pretože pri dnešnej teplote stačí ľahšia kombinácia');
    } else if (isWindy) {
      buffer.write(', aby outfit zvládol aj vietor');
    }
    var out = buffer.toString().trim();
    if (!out.endsWith('.')) out = '$out.';
    return out;
  }

  static String _joinSk(List<String> parts) {
    if (parts.length == 1) return parts.first;
    if (parts.length == 2) return '${parts[0]} a ${parts[1]}';
    return '${parts.sublist(0, parts.length - 1).join(', ')} a ${parts.last}';
  }

  static String _lowerFirst(String text) {
    final t = text.trim();
    if (t.isEmpty) return t;
    return t[0].toLowerCase() + t.substring(1);
  }
}
