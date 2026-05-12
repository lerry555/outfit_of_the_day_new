import 'dart:math' as math;

/// Longer stylist copy for „Prečo tento outfit?“ only (segment microcopy lives in [HomeDailyBriefingRow]).
class DayWeatherUxCopy {
  const DayWeatherUxCopy({required this.outfitWhyWeatherNote});
  final String outfitWhyWeatherNote;
}

int _salt(DateTime date, int segment, {int extra = 0}) {
  return date.year * 400 + date.month * 40 + date.day + segment * 17 + extra * 3;
}

String _pick(List<String> xs, int salt) {
  if (xs.isEmpty) return '';
  return xs[math.max(0, salt.abs()) % xs.length];
}

String _outfitWhyWeatherNote({
  required DateTime date,
  required bool isTomorrow,
  required int mt,
  required int at,
  required int et,
  required int mainChipTempC,
  required int? minTempC,
  required int? maxTempC,
  required bool willRain,
  required bool morningRain,
  required bool afternoonRain,
  required bool eveningRain,
  required bool isWindy,
  required bool windMorning,
  required bool windAfternoon,
  required bool windEvening,
}) {
  final dayWord = isTomorrow ? 'Zajtra' : 'Dnes';
  final s1 = _salt(date, 50, extra: isTomorrow ? 11 : 0);
  final s2 = _salt(date, 51, extra: isTomorrow ? 11 : 0);
  final range = (minTempC != null && maxTempC != null) ? '$minTempC–$maxTempC' : null;
  final arc = at > mt + 2
      ? 'poobedie prinesie teplejší vzduch'
      : (mt > at + 2 ? 'poobede sa ochladzuje' : 'teploty držia mierny rozdiel');

  String rainHint() {
    if (!willRain) return '';
    if (afternoonRain) return 'vlhkejšie poobedie';
    if (morningRain) return 'vlhkejšie ráno';
    if (eveningRain) return 'vlhkejší večer';
    return 'premenlivejší vzduch';
  }

  String windHint() {
    if (!isWindy && !windMorning && !windAfternoon && !windEvening) return '';
    if (windAfternoon) return 'veterné poobedie';
    if (windMorning) return 'veterné ráno';
    if (windEvening) return 'veterný večer';
    return 'výraznejší vietor';
  }

  final rh = rainHint();
  final wh = windHint();

  final firstVariants = <String>[
    if (range != null)
      '$dayWord sa pohybuje približne v rozmedzí $range °C; $arc.'
    else
      '$dayWord ráno okolo $mt °C, cez deň okolo $at °C a večer okolo $et °C (okolo $mainChipTempC °C na outfite).',
    '$dayWord začína okolo $mt °C, cez deň sa drží okolo $at °C a večer okolo $et °C.',
  ];

  final secondVariants = <String>[
    if (rh.isNotEmpty && wh.isNotEmpty)
      'Oplatí sa vrstvenie a praktickejší vrchný kúsok kvôli $rh a $wh.'
    else if (rh.isNotEmpty)
      'Pre komfort zvoľ materiál, čo znesie $rh, a nechaj outfit pripravený na zmenu.'
    else if (wh.isNotEmpty)
      'Kvôli $wh drž líniu čistú a siahni po strihu, čo drží tvar.'
    else
      'Outfit môže zostať pohodlný, ale stále čitateľný vo vrstvení.',
    if (at - mt >= 3)
      'Cez deň sa oteplí, takže ťažká bunda nemusí byť stredobodom.'
    else if (at - et >= 3)
      'Po západe prichádza chladnejší vzduch, preto má zmysel mať po ruke teplejší kúsok.'
    else
      'Drž vrstvy rozumné — komfort je dôležitejší než prehnaná dekorácia.',
  ];

  final a = _pick(firstVariants, s1);
  final b = _pick(secondVariants, s2);
  return '$a $b'.trim();
}

DayWeatherUxCopy buildDayWeatherUx({
  required DateTime date,
  required bool isTomorrow,
  required int morningTempC,
  required int afternoonTempC,
  required int eveningTempC,
  required int mainChipTempC,
  required int? minTempC,
  required int? maxTempC,
  required bool willRain,
  required bool morningRain,
  required bool afternoonRain,
  required bool eveningRain,
  required bool isWindy,
  required bool windMorning,
  required bool windAfternoon,
  required bool windEvening,
}) {
  final mt = morningTempC;
  final at = afternoonTempC;
  final et = eveningTempC;

  final outfitWhyWeatherNote = _outfitWhyWeatherNote(
    date: date,
    isTomorrow: isTomorrow,
    mt: mt,
    at: at,
    et: et,
    mainChipTempC: mainChipTempC,
    minTempC: minTempC,
    maxTempC: maxTempC,
    willRain: willRain,
    morningRain: morningRain,
    afternoonRain: afternoonRain,
    eveningRain: eveningRain,
    isWindy: isWindy,
    windMorning: windMorning,
    windAfternoon: windAfternoon,
    windEvening: windEvening,
  );

  return DayWeatherUxCopy(outfitWhyWeatherNote: outfitWhyWeatherNote);
}
