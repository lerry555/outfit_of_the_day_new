abstract final class StylistKnownCityTypoResolver {
  static String? resolve(
    String text,
    Map<String, String> knownCities, {
    Set<String> exclude = const <String>{},
  }) {
    final excluded = exclude.map((value) => value.toLowerCase().trim()).toSet();
    final tokens = RegExp(r'[a-záäčďéíĺľňóôřšťúýž]{6,}', caseSensitive: false)
        .allMatches(text)
        .map((match) => _asciiFold(match.group(0)!.toLowerCase()))
        .toSet();
    if (tokens.isEmpty) return null;

    String? winner;
    var winnerDistance = 1 << 20;
    var runnerUpDistance = 1 << 20;
    for (final token in tokens) {
      for (final value in knownCities.values.toSet()) {
        if (excluded.contains(value.toLowerCase().trim())) continue;
        final core = _asciiFold(value.split(',').first.trim().toLowerCase());
        if (core.contains(' ') || core.length < 6) continue;
        if (!token.startsWith(core.substring(0, 2))) continue;
        final maxLength = token.length > core.length
            ? token.length
            : core.length;
        if ((token.length - core.length).abs() > 3) continue;
        final distance = _editDistance(token, core);
        final allowed = maxLength >= 9 ? 4 : 2;
        if (distance > allowed || distance / maxLength > 0.40) continue;
        if (distance < winnerDistance) {
          runnerUpDistance = winnerDistance;
          winnerDistance = distance;
          winner = value;
        } else if (value != winner && distance < runnerUpDistance) {
          runnerUpDistance = distance;
        }
      }
    }
    if (winner == null || runnerUpDistance <= winnerDistance + 1) return null;
    return winner;
  }

  static int _editDistance(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 1; i <= left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0)..[0] = i;
      for (var j = 1; j <= right.length; j++) {
        final substitution =
            previous[j - 1] +
            (left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        current[j] = substitution < deletion
            ? (substitution < insertion ? substitution : insertion)
            : (deletion < insertion ? deletion : insertion);
      }
      previous = current;
    }
    return previous.last;
  }

  static String _asciiFold(String value) => value
      .replaceAll(RegExp('[áä]'), 'a')
      .replaceAll('č', 'c')
      .replaceAll('ď', 'd')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[ĺľ]'), 'l')
      .replaceAll('ň', 'n')
      .replaceAll(RegExp('[óô]'), 'o')
      .replaceAll('ř', 'r')
      .replaceAll('š', 's')
      .replaceAll('ť', 't')
      .replaceAll('ú', 'u')
      .replaceAll('ý', 'y')
      .replaceAll('ž', 'z');
}
