import 'stylist_semantic_activity.dart';

class StylistDestinationMention {
  final String evidence;
  final String query;
  final bool bareReply;

  const StylistDestinationMention({
    required this.evidence,
    required this.query,
    this.bareReply = false,
  });
}

/// Extracts a destination *mention* without deciding what geographic thing it
/// is. Country/city/region truth belongs to a geocoder/provider, not to a Dart
/// whitelist.
abstract final class StylistDestinationMentionExtractor {
  static StylistDestinationMention? extract(
    String input, {
    bool allowBareReply = false,
  }) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    // Prefer an explicit travel verb followed by a location preposition. This
    // keeps "čo si obliecť do lietadla" from being mistaken for a destination.
    final travel = RegExp(
      r'(?:^|\s)(?:let[ií]m|let[ií]me|polet[ií]m|polet[ií]me|cestuj\w*|'
      r'idem|ideme|p[oô]jdem|p[oô]jdeme|chyst\w*)\s+(?:sa\s+)?'
      r'(?:do|v|vo|na|k|ku)\s+(.+)',
      caseSensitive: false,
    ).allMatches(raw).toList(growable: false);
    for (final match in travel.reversed) {
      final candidate = _trimCandidate(match.group(1) ?? '');
      if (_usable(candidate)) {
        return StylistDestinationMention(evidence: candidate, query: candidate);
      }
    }

    // Follow-up after a destination question can naturally be just "Londýn".
    if (allowBareReply) {
      final candidate = _trimCandidate(raw);
      final words = candidate.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
      if (words.length <= 5 && _usable(candidate)) {
        return StylistDestinationMention(
          evidence: candidate,
          query: candidate,
          bareReply: true,
        );
      }
    }
    return null;
  }

  static List<String> providerQueryVariants(String query) {
    final clean = _trimCandidate(query);
    if (clean.isEmpty) return const [];
    final variants = <String>[clean];
    final words = clean.split(RegExp(r'\s+')).toList();
    if (words.isNotEmpty) {
      final last = words.last;
      final normalizedLast = StylistSemanticActivity.normalize(last);
      String? replacement;
      if (normalizedLast.length >= 5 && normalizedLast.endsWith('ska')) {
        replacement = '${last.substring(0, last.length - 1)}o';
      } else if (normalizedLast.length >= 6 &&
          (normalizedLast.endsWith('u') ||
              normalizedLast.endsWith('e') ||
              normalizedLast.endsWith('i') ||
              normalizedLast.endsWith('a'))) {
        replacement = last.substring(0, last.length - 1);
      }
      if (replacement != null && replacement.trim().isNotEmpty) {
        variants.add([...words.take(words.length - 1), replacement].join(' '));
      }
    }
    return variants.toSet().toList(growable: false);
  }

  static String _trimCandidate(String value) {
    var out = value.trim();
    final sentenceCut = RegExp(r'[,;.!?\n]');
    final cut = sentenceCut.firstMatch(out);
    if (cut != null) out = out.substring(0, cut.start).trim();

    final clauseCut = RegExp(
      r'\s+(?:a\s+(?:ja|my|neviem|potrebujem|chcem|chceme|budem|budeme)\b|'
      r'ale\b|lebo\b|preto\b|potrebujem\b|chcem\b|chceme\b|neviem\b|'
      r'budem\b|budeme\b|aby\b)',
      caseSensitive: false,
    ).firstMatch(out);
    if (clauseCut != null) out = out.substring(0, clauseCut.start).trim();
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _usable(String candidate) {
    if (candidate.length < 2) return false;
    final normalized = StylistSemanticActivity.normalize(candidate);
    if (normalized.isEmpty) return false;

    // A common-noun activity/environment after "do/na/v" is not geographic
    // evidence. Proper-name casing still allows real places that happen to
    // share such a word to reach the provider, which then decides what they are.
    final hasProperNameSignal = RegExp(r'[A-ZÁÄČĎÉÍĽĹŇÓÔŔŠŤÚÝŽ]').hasMatch(candidate);
    if (!hasProperNameSignal &&
        (StylistSemanticActivity.resolveExplicit(candidate) != null ||
            StylistSemanticActivity.looksLikeGenericTrip(candidate) ||
            RegExp(
              r'^(?:hor\w*|les\w*|prirod\w*|park\w*|plaz\w*|centrum\w*|mesto\w*)$',
              caseSensitive: false,
            ).hasMatch(normalized))) {
      return false;
    }

    if (RegExp(
      r'^(?:lietadl\w*|letisk\w*|vlak\w*|auto\w*|autobus\w*|bus\w*|'
      r'praca\w*|robot\w*|skol\w*|kino\w*|koncert\w*|restaur\w*|'
      r'fitko\w*|gym\w*|vylet\w*|cest\w*|presun\w*)$',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return false;
    }
    return true;
  }
}
