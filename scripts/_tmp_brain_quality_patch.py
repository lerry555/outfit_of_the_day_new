from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def insert_before_final_brace(path: str, block: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    marker = "\n}\n"
    idx = text.rfind(marker)
    if idx < 0:
        raise SystemExit(f"{path}: final brace not found")
    p.write_text(text[:idx] + "\n" + block.rstrip() + text[idx:], encoding="utf-8")


def append_block(path: str, block: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    block = block.strip()
    if block in text:
        raise SystemExit(f"{path}: block already present")
    p.write_text(text.rstrip() + "\n\n" + block + "\n", encoding="utf-8")


replace_once(
    "lib/screens/stylist_chat_screen.dart",
    """    if (lower.contains('bude prša') ||
        lower.contains('bude prsa') ||
        lower.contains('bude dáž') ||
        lower.contains('bude daz')) {
      return true;
    }
    return false;
  }
""",
    """    if (lower.contains('bude prša') ||
        lower.contains('bude prsa') ||
        lower.contains('bude dáž') ||
        lower.contains('bude daz')) {
      return true;
    }
    // Generic questions such as „aké hlásia počasie?“ must use the same
    // Open-Meteo snapshot as the rest of the app instead of free-form model
    // prose, otherwise a daily maximum can be mistaken for the current temp.
    if (lower.contains('počas') ||
        lower.contains('pocas') ||
        lower.contains('predpove') ||
        lower.contains('hlásia') ||
        lower.contains('hlasia') ||
        lower.contains('weather')) {
      return true;
    }
    return false;
  }
""",
)

replace_once(
    "lib/screens/stylist_chat_screen.dart",
    """        requestedSwap: swapRequest,
        // Pri spodku s konkrétnou rodinou necháme aj fallback generovanie
        // rešpektovať voľbu, ak by sa swap nepodaril.
""",
    """        // „Daj mi radšej kraťasy“ is a constrained re-compose: changing
        // the bottom may legitimately require a different top/shoes for a good
        // outfit. Keep strict one-piece swap only when no family was requested.
        requestedSwap: swapRequest.bottomFamily == null ? swapRequest : null,
        // Pri spodku s konkrétnou rodinou necháme generovanie rešpektovať voľbu.
""",
)

replace_once(
    "lib/utils/stylist_weather_tip.dart",
    """    final hour = eventHour;
    final temp = _tempForHour(snapshot, hour);
    final place = (locationLabel ?? snapshot.cityName).split(',').first.trim();
    final buffer = StringBuffer();

    if (hour != null) {
      if (place.isNotEmpty) {
        buffer.write('V $place okolo $hour:00 bude približne $temp °C');
      } else {
        buffer.write('Okolo $hour:00 bude približne $temp °C');
      }
    } else if (snapshot.morningTempC != null) {
      buffer.write('Ráno bude okolo ${snapshot.morningTempC} °C');
      if (place.isNotEmpty) buffer.write(' v $place');
    } else {
      buffer.write('Teplota bude okolo $temp °C');
      if (place.isNotEmpty) buffer.write(' v $place');
    }
""",
    """    final hour = eventHour;
    final temp = _tempForHour(snapshot, hour);
    final place = (locationLabel ?? snapshot.cityName).split(',').first.trim();
    final placePhrase = place.isNotEmpty ? SlovakCityLocative.inCity(place) : '';
    final now = DateTime.now();
    final isToday = snapshot.date.year == now.year &&
        snapshot.date.month == now.month &&
        snapshot.date.day == now.day;
    final buffer = StringBuffer();

    if (hour != null) {
      if (placePhrase.isNotEmpty) {
        buffer.write('$placePhrase okolo $hour:00 bude približne $temp °C');
      } else {
        buffer.write('Okolo $hour:00 bude približne $temp °C');
      }
    } else if (isToday) {
      if (placePhrase.isNotEmpty) {
        buffer.write('$placePhrase je teraz okolo ${snapshot.mainChipTempC} °C');
      } else {
        buffer.write('Teraz je okolo ${snapshot.mainChipTempC} °C');
      }
    } else if (snapshot.morningTempC != null) {
      buffer.write('Ráno bude okolo ${snapshot.morningTempC} °C');
      if (placePhrase.isNotEmpty) buffer.write(' $placePhrase');
    } else {
      buffer.write('Teplota bude okolo $temp °C');
      if (placePhrase.isNotEmpty) buffer.write(' $placePhrase');
    }
""",
)

replace_once(
    "lib/domain/wardrobe_v2/outfit_suitability_policy_v2.dart",
    """      if (isShorts(type) && tempC <= 10) score += strongPenalty;
      if (isOpenFootwear(type) && tempC <= 8) score += majorPenalty;
""",
    """      if (isShorts(type)) {
        if (tempC <= 10) {
          score += strongPenalty;
        } else if (tempC >= 28) {
          score += 3.0;
        } else if (tempC >= 25) {
          score += 1.5;
        }
      }
      // Jeans are still valid in warm weather, but at real heat they should
      // not beat a suitable shorts option merely on generic style scoring.
      if (tempC >= 28 &&
          item.bodySlots.contains('lower_body') &&
          (type.contains('jean') || type.contains('denim'))) {
        score += lightPenalty;
      }
      if (isOpenFootwear(type) && tempC <= 8) score += majorPenalty;
""",
)

replace_once(
    "lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart",
    """    final repeatedPrimary = primary.toSet().length < primary.length;
    final accentEcho = accent.any(primary.contains);
""",
    """    final primaryCounts = <String, int>{};
    for (final family in primary) {
      final key = family.trim().toLowerCase();
      if (key.isEmpty || key == 'unknown') continue;
      primaryCounts[key] = (primaryCounts[key] ?? 0) + 1;
    }
    const neutralFamilies = <String>{
      'black', 'white', 'gray', 'grey', 'beige', 'cream', 'brown', 'navy',
    };
    final repeatedNonNeutralPrimary = primaryCounts.entries.any(
      (entry) => entry.value > 1 && !neutralFamilies.contains(entry.key),
    );
    final accentEcho = accent.any(primary.contains);
""",
)
replace_once(
    "lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart",
    """      'primaryColorHarmony': repeatedPrimary ? 0.8 : 0,
""",
    """      'primaryColorHarmony': repeatedNonNeutralPrimary ? -1.2 : 0,
""",
)

insert_before_final_brace(
    "test/stylist_semantic_activity_test.dart",
    """  test('plain city outing uses local semantics while a real trip stays remote', () {
    const local = 'ahoj idem von do mesta, poraď mi s outfitom';
    expect(StylistSemanticActivity.resolveExplicit(local), 'city_walk');
    expect(StylistSemanticActivity.looksLikeGenericTrip(local), isFalse);
    expect(StylistSemanticActivity.looksRemotePlan(local), isFalse);
    expect(
      StylistSemanticActivity.looksRemotePlan('zajtra idem na výlet'),
      isTrue,
    );
  });
""",
)

append_block(
    "functions/stylist/outfit_decision_known_location.test.js",
    """test(\"non-remote city walk uses GPS instead of asking destination\", () => {
  const state = {
    groundingStatus: \"sufficient\",
    unresolvedMaterialFields: [],
    gpsDefaultCity: \"Martin\",
    routineLocalOutfit: false,
    remoteActivityPlanned: false,
    activityLocationKnown: false,
    activityHint: \"city_walk\",
    clarifiedMaterialFields: [],
  };

  assert.equal(
    resolveOutfitAction(\"clarify\", {impactFields: [\"location\"]}, state),
    \"generate_outfit\",
  );
});
""",
)

insert_before_final_brace(
    "test/brain_v1_v2_offline_bundle_test.dart",
    """  test('manual chat regressions keep local weather and quality guardrails', () {
    final screen = _read('lib/screens/stylist_chat_screen.dart');
    final weatherTip = _read('lib/utils/stylist_weather_tip.dart');
    final policy = _read(
      'lib/domain/wardrobe_v2/outfit_suitability_policy_v2.dart',
    );
    final matrix = _read(
      'lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart',
    );

    expect(screen, contains(\"lower.contains('počas')\"));
    expect(
      screen,
      contains('requestedSwap: swapRequest.bottomFamily == null ? swapRequest : null'),
    );
    expect(weatherTip, contains('snapshot.mainChipTempC'));
    expect(policy, contains('tempC >= 28'));
    expect(policy, contains(\"type.contains('jean') || type.contains('denim')\"));
    expect(matrix, contains('repeatedNonNeutralPrimary'));
    expect(
      matrix,
      isNot(contains(\"'primaryColorHarmony': repeatedPrimary ? 0.8 : 0\")),
    );
  });
""",
)
