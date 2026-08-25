import 'stylist_activity_terrain.dart';

/// Úpravy surovej teploty z Open-Meteo (2 m nad morom v meste) podľa aktivity.
///
/// API dáva teplotu pre súradnice mesta (napr. Martin). V lese/kopcoch/hore
/// skoro ráno býva o pár stupňov chladnejšie — bližšie Google / pocit v teréne.
class StylistWeatherAdjustment {
  const StylistWeatherAdjustment._();

  static int adjustActivityTempC({
    required int rawTempC,
    required StylistActivityTerrain terrain,
    int? hourLocal,
  }) {
    if (terrain != StylistActivityTerrain.wetGround) return rawTempC;
    var delta = 1;
    if (hourLocal != null && hourLocal < 9) delta += 2;
    if (hourLocal != null && hourLocal <= 5) delta += 1;
    return (rawTempC - delta).clamp(-30, 45);
  }
}
