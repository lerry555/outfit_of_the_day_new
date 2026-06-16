import '../Services/color_naming_service.dart';

/// Review status for wardrobe reanalyze dry-run.
enum WardrobeReanalyzeReviewStatus {
  improved,
  unchanged,
  suspicious,
}

/// Heuristics for dry-run quality review (no Firestore side effects).
abstract final class WardrobeReanalyzeInspector {
  static const int lowConfidenceThreshold = 70;

  static const List<String> _qualifierTokens = [
    'fashion',
    'sportove',
    'sportové',
    'športové',
    'sport',
    'skinny',
    'wide',
    'bezeck',
    'bežeck',
    'treningov',
    'tréningov',
    'klasick',
    'klasická',
    'oversize',
    'dlhym',
    'dlhým',
    'kratkim',
    'krátkym',
    'bomber',
    'cargo',
    'pleten',
    'flisov',
    'flísov',
    'zimn',
    'zimná',
    'prechodn',
    'mom',
    'chelsea',
    'oxford',
  ];

  static WardrobeReanalyzeReviewStatus classifyStatus({
    required bool fieldsChanged,
    required String oldName,
    required String newName,
    required String oldCanonical,
    required String newCanonical,
    required List<String> detectedColors,
    int? analyzerConfidence,
    bool kbMatched = false,
  }) {
    if (!fieldsChanged) return WardrobeReanalyzeReviewStatus.unchanged;

    final reasons = suspiciousReasons(
      oldName: oldName,
      newName: newName,
      oldCanonical: oldCanonical,
      newCanonical: newCanonical,
      detectedColors: detectedColors,
      analyzerConfidence: analyzerConfidence,
      kbMatched: kbMatched,
    );
    if (reasons.isNotEmpty) return WardrobeReanalyzeReviewStatus.suspicious;
    return WardrobeReanalyzeReviewStatus.improved;
  }

  static List<String> suspiciousReasons({
    required String oldName,
    required String newName,
    required String oldCanonical,
    required String newCanonical,
    required List<String> detectedColors,
    int? analyzerConfidence,
    bool kbMatched = false,
  }) {
    final reasons = <String>[];

    if (detectedColorChangedInName(
      oldName: oldName,
      newName: newName,
      detectedColors: detectedColors,
    )) {
      reasons.add('detected color changed');
    }
    if (specificityDecreased(oldName, newName)) {
      reasons.add('specificity decreased');
    }
    if (lowAnalyzerConfidence(analyzerConfidence, kbMatched: kbMatched)) {
      reasons.add('low analyzer confidence');
    }
    if (canonicalChangedDrastically(oldCanonical, newCanonical)) {
      reasons.add('canonical type changed drastically');
    }

    return reasons;
  }

  static bool detectedColorChangedInName({
    required String oldName,
    required String newName,
    required List<String> detectedColors,
  }) {
    final oldColor = _colorTokenInText(oldName);
    final newColor = _colorTokenInText(newName);
    if (oldColor != null && newColor != null && oldColor != newColor) {
      return true;
    }

    if (detectedColors.isEmpty) return false;
    final detected = _normalizeColorToken(detectedColors.first);
    if (detected.isEmpty) return false;

    if (oldColor != null && oldColor != detected) return true;
    if (newColor != null && newColor != detected && oldColor == null) {
      return false;
    }
    return false;
  }

  static bool specificityDecreased(String oldName, String newName) {
    final oldN = _norm(oldName);
    final newN = _norm(newName);
    if (oldN.isEmpty || newN.isEmpty) return false;
    if (oldN == newN) return false;

    for (final q in _qualifierTokens) {
      final qn = _norm(q);
      if (oldN.contains(qn) && !newN.contains(qn)) return true;
    }

    final oldWords =
        oldN.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    final newWords =
        newN.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    if (oldWords.length > newWords.length &&
        newWords.isNotEmpty &&
        newWords.every(oldWords.contains)) {
      return true;
    }

    return false;
  }

  static bool lowAnalyzerConfidence(int? confidence, {bool kbMatched = false}) {
    if (kbMatched && (confidence == null || confidence >= 55)) return false;
    if (confidence == null) return true;
    return confidence < lowConfidenceThreshold;
  }

  static bool canonicalChangedDrastically(String oldC, String newC) {
    final o = oldC.trim().toLowerCase();
    final n = newC.trim().toLowerCase();
    if (o.isEmpty || n.isEmpty || o == n) return false;

    final oldFamily = _canonicalFamily(o);
    final newFamily = _canonicalFamily(n);
    if (oldFamily.isEmpty || newFamily.isEmpty) return false;
    return oldFamily != newFamily;
  }

  static String _canonicalFamily(String canonical) {
    const footwear = {
      'sneakers',
      'sneaker',
      'boots',
      'shoes',
      'loafers',
      'sandals',
    };
    const bottoms = {
      'pants',
      'jeans',
      'shorts',
      'skirt',
      'trousers',
    };
    const tops = {
      'tshirt',
      't_shirt',
      'shirt',
      'blouse',
      'polo',
      'tank',
      'undershirt',
      'sweater',
      'hoodie',
      'sweatshirt',
    };
    const outer = {
      'jacket',
      'coat',
      'blazer',
      'vest',
      'parka',
    };
    const accessory = {
      'hat',
      'scarf',
      'belt',
      'glasses',
      'bag',
    };

    if (footwear.contains(canonical)) return 'footwear';
    if (bottoms.contains(canonical)) return 'bottom';
    if (tops.contains(canonical)) return 'top';
    if (outer.contains(canonical)) return 'outer';
    if (accessory.contains(canonical)) return 'accessory';

    if (canonical.contains('shoe') ||
        canonical.contains('sneaker') ||
        canonical.contains('boot')) {
      return 'footwear';
    }
    if (canonical.contains('pant') ||
        canonical.contains('jean') ||
        canonical.contains('short')) {
      return 'bottom';
    }
    if (canonical.contains('shirt') ||
        canonical.contains('tee') ||
        canonical.contains('hoodie') ||
        canonical.contains('sweater')) {
      return 'top';
    }
    if (canonical.contains('jacket') ||
        canonical.contains('coat') ||
        canonical.contains('blazer')) {
      return 'outer';
    }
    return canonical;
  }

  static String? _colorTokenInText(String text) {
    final n = _norm(text);
    for (final base in wardrobeBaseColors) {
      final token = _normalizeColorToken(base);
      if (n.contains(token)) return token;
      final adjNeuter = token.endsWith('a')
          ? '${token.substring(0, token.length - 1)}e'
          : token;
      final adjMasc = token.endsWith('a')
          ? '${token.substring(0, token.length - 1)}y'
          : token;
      if (n.contains(adjNeuter) || n.contains(adjMasc)) return token;
    }
    return null;
  }

  static String _normalizeColorToken(String color) => _norm(color);

  static String _norm(String s) {
    var out = s.trim().toLowerCase();
    const repl = {
      'á': 'a',
      'ä': 'a',
      'č': 'c',
      'ď': 'd',
      'é': 'e',
      'í': 'i',
      'ĺ': 'l',
      'ľ': 'l',
      'ň': 'n',
      'ó': 'o',
      'ô': 'o',
      'ŕ': 'r',
      'š': 's',
      'ť': 't',
      'ú': 'u',
      'ý': 'y',
      'ž': 'z',
    };
    for (final e in repl.entries) {
      out = out.replaceAll(e.key, e.value);
    }
    return out;
  }
}
