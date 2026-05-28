import 'package:flutter/foundation.dart';

class ColorMatch {
  const ColorMatch({
    required this.displayName,
    required this.baseColor,
    required this.hex,
  });

  final String displayName;
  final String baseColor;
  final String hex;
}

const List<String> wardrobeBaseColors = <String>[
  'biela',
  'čierna',
  'sivá',
  'béžová',
  'hnedá',
  'modrá',
  'tmavomodrá',
  'svetlomodrá',
  'červená',
  'bordová',
  'ružová',
  'fialová',
  'zelená',
  'khaki',
  'žltá',
  'oranžová',
  'zlatá',
  'strieborná',
];

class ColorNamingService {
  ColorNamingService._();
  static final ColorNamingService instance = ColorNamingService._();

  static const Map<String, String> _hexByDisplay = <String, String>{
    'biela': '#FFFFFF',
    'čierna': '#000000',
    'sivá': '#808080',
    'béžová': '#F5F5DC',
    'hnedá': '#8B4513',
    'modrá': '#0000FF',
    'tmavomodrá': '#000080',
    'svetlomodrá': '#87CEEB',
    'červená': '#FF0000',
    'bordová': '#800020',
    'ružová': '#FFC0CB',
    'fialová': '#800080',
    'zelená': '#008000',
    'khaki': '#C3B091',
    'žltá': '#FFFF00',
    'oranžová': '#FFA500',
    'zlatá': '#FFD700',
    'strieborná': '#C0C0C0',
  };

  static const Map<String, String> _aliases = <String, String>{
    'black': 'čierna',
    'white': 'biela',
    'grey': 'sivá',
    'gray': 'sivá',
    'beige': 'béžová',
    'brown': 'hnedá',
    'blue': 'modrá',
    'navy': 'tmavomodrá',
    'light blue': 'svetlomodrá',
    'red': 'červená',
    'burgundy': 'bordová',
    'pink': 'ružová',
    'purple': 'fialová',
    'green': 'zelená',
    'olive': 'khaki',
    'yellow': 'žltá',
    'orange': 'oranžová',
    'gold': 'zlatá',
    'silver': 'strieborná',
    'cierna': 'čierna',
    'siva': 'sivá',
    'seda': 'sivá',
    'zelena': 'zelená',
    'modra': 'modrá',
  };

  Future<void> load() async {
    if (kDebugMode) debugPrint('[COLOR_NAMING] ready');
  }

  List<String> get baseColorNames => wardrobeBaseColors;

  String? normalizeDisplayColor(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    for (final c in wardrobeBaseColors) {
      if (c.toLowerCase() == lower) return c;
    }
    return _aliases[lower];
  }

  List<String> normalizeDisplayColors(List<String> input) {
    final out = <String>[];
    for (final raw in input) {
      final normalized = normalizeDisplayColor(raw);
      if (normalized != null && !out.contains(normalized)) out.add(normalized);
    }
    return out;
  }

  ColorMatch? matchByName(String? raw) {
    final normalized = normalizeDisplayColor(raw);
    if (normalized == null) return null;
    return ColorMatch(
      displayName: normalized,
      baseColor: normalized,
      hex: _hexByDisplay[normalized] ?? '#808080',
    );
  }

  List<String> chipColorOptions(List<String> selected) {
    final out = <String>[...wardrobeBaseColors];
    for (final s in normalizeDisplayColors(selected)) {
      if (!out.contains(s)) out.add(s);
    }
    return out;
  }

  List<String> detectColorsInText(String text) {
    final lower = text.toLowerCase();
    final found = <String>[];
    for (final c in wardrobeBaseColors) {
      if (lower.contains(c.toLowerCase()) && !found.contains(c)) found.add(c);
    }
    for (final a in _aliases.entries) {
      if (lower.contains(a.key) && !found.contains(a.value)) found.add(a.value);
    }
    return found;
  }
}
