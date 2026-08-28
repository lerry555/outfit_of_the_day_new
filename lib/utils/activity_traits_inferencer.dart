import '../data/activity_traits.dart';
import 'stylist_travel_context.dart';

/// Infers coarse activity traits from generic meaning-bearing word families.
///
/// Proper nouns never carry authority here: no city, country, region,
/// attraction, performer or brand name may make an activity true.
abstract final class ActivityTraitsInferencer {
  static const List<({String stem, String labelSk})> _outdoorTerrainStems = [
    (stem: 'tur', labelSk: 'túra'),
    (stem: 'hor', labelSk: 'hory'),
    (stem: 'ferrat', labelSk: 'feraty'),
    (stem: 'hub', labelSk: 'huby'),
    (stem: 'hrib', labelSk: 'huby'),
    (stem: 'ryb', labelSk: 'rybolov'),
    (stem: 'stan', labelSk: 'stanovanie'),
    (stem: 'safar', labelSk: 'safari'),
    (stem: 'lyz', labelSk: 'lyžovanie'),
    (stem: 'raft', labelSk: 'rafting'),
    (stem: 'plaz', labelSk: 'pláž'),
    (stem: 'kup', labelSk: 'kúpanie'),
    (stem: 'plav', labelSk: 'plávanie'),
    (stem: 'turist', labelSk: 'turistika'),
    (stem: 'trail', labelSk: 'trail'),
    (stem: 'les', labelSk: 'les'),
    (stem: 'kop', labelSk: 'kopce'),
    (stem: 'prirod', labelSk: 'príroda'),
    (stem: 'camp', labelSk: 'kempovanie'),
    (stem: 'bik', labelSk: 'bicykel'),
    (stem: 'cyklo', labelSk: 'cyklistika'),
    (stem: 'behu', labelSk: 'beh'),
    (stem: 'behat', labelSk: 'beh'),
    (stem: 'bezat', labelSk: 'beh'),
    (stem: 'climb', labelSk: 'lezenie'),
    (stem: 'lezen', labelSk: 'lezenie'),
    (stem: 'skal', labelSk: 'skaly'),
    (stem: 'vodopad', labelSk: 'vodopády'),
    (stem: 'kajak', labelSk: 'kajak'),
    (stem: 'surf', labelSk: 'surf'),
    (stem: 'snork', labelSk: 'šnorchlovanie'),
    (stem: 'kanoe', labelSk: 'kanoe'),
    (stem: 'splav', labelSk: 'splav'),
    (stem: 'paddle', labelSk: 'paddleboard'),
    (stem: 'jazero', labelSk: 'jazero'),
    (stem: 'opale', labelSk: 'opálenie'),
    (stem: 'piknik', labelSk: 'piknik'),
    (stem: 'trek', labelSk: 'trek'),
    (stem: 'hiking', labelSk: 'hiking'),
    (stem: 'park', labelSk: 'park'),
    (stem: 'vrch', labelSk: 'výstup'),
    (stem: 'sedlo', labelSk: 'sedlo'),
    (stem: 'hreben', labelSk: 'hrebeň'),
    (stem: 'skialp', labelSk: 'skialp'),
    (stem: 'snowboard', labelSk: 'snowboarding'),
    (stem: 'biatlon', labelSk: 'biatlon'),
    (stem: 'orientac', labelSk: 'orientačný beh'),
    (stem: 'maraton', labelSk: 'maratón'),
  ];

  static const List<({String stem, String labelSk})> _routineLocalStems = [
    (stem: 'prac', labelSk: 'práca'),
    (stem: 'robot', labelSk: 'práca'),
    (stem: 'kancel', labelSk: 'kancelária'),
    (stem: 'skol', labelSk: 'škola'),
    (stem: 'obed', labelSk: 'obed'),
    (stem: 'vecera', labelSk: 'večera'),
    (stem: 'drink', labelSk: 'drink'),
    (stem: 'rande', labelSk: 'rande'),
    (stem: 'kav', labelSk: 'káva'),
    (stem: 'restaur', labelSk: 'reštaurácia'),
    (stem: 'nakup', labelSk: 'nákupy'),
    (stem: 'obchod', labelSk: 'obchod'),
    (stem: 'stretnut', labelSk: 'stretnutie'),
    (stem: 'meet', labelSk: 'meeting'),
    (stem: 'posil', labelSk: 'posilňovňa'),
    (stem: 'fitko', labelSk: 'fitko'),
    (stem: 'fitness', labelSk: 'fitko'),
    (stem: 'gym', labelSk: 'fitko'),
    (stem: 'kader', labelSk: 'kaderník'),
    (stem: 'lekar', labelSk: 'lekár'),
    (stem: 'urad', labelSk: 'úrad'),
  ];

  static const List<({String stem, String labelSk})> _venueBoundStems = [
    (stem: 'kin', labelSk: 'kino'),
    (stem: 'divadl', labelSk: 'divadlo'),
    (stem: 'koncert', labelSk: 'koncert'),
    (stem: 'festival', labelSk: 'festival'),
    (stem: 'klub', labelSk: 'klub'),
    (stem: 'galer', labelSk: 'galéria'),
    (stem: 'muze', labelSk: 'múzeum'),
    (stem: 'balet', labelSk: 'balet'),
    (stem: 'oper', labelSk: 'opera'),
    (stem: 'cinema', labelSk: 'kino'),
  ];

  static const List<({String stem, String labelSk})> _poiStems = [
    (stem: 'zoo', labelSk: 'ZOO'),
    (stem: 'aquap', labelSk: 'aquapark'),
    (stem: 'zabavn', labelSk: 'zábavný park'),
    (stem: 'theme', labelSk: 'theme park'),
    (stem: 'waterpark', labelSk: 'aquapark'),
  ];

  static ActivityTraits infer(String conversation) {
    final norm = _normalize(conversation);
    if (norm.trim().isEmpty) {
      return const ActivityTraits(confidence: 0.0, reason: 'empty');
    }

    String? outdoorLabel;
    var outdoor = false;
    for (final entry in _outdoorTerrainStems) {
      if (_stemMatch(norm, entry.stem)) {
        outdoor = true;
        outdoorLabel ??= entry.labelSk;
      }
    }

    String? routineLabel;
    var routineLocal = false;
    for (final entry in _routineLocalStems) {
      if (_stemMatch(norm, entry.stem)) {
        routineLocal = true;
        routineLabel ??= entry.labelSk;
      }
    }

    String? venueLabel;
    var venueBound = false;
    for (final entry in _venueBoundStems) {
      if (_stemMatch(norm, entry.stem)) {
        venueBound = true;
        venueLabel ??= entry.labelSk;
      }
    }

    String? poiLabel;
    var poiDependent = false;
    for (final entry in _poiStems) {
      if (_stemMatch(norm, entry.stem)) {
        poiDependent = true;
        poiLabel ??= entry.labelSk;
      }
    }

    final travel = StylistTravelContextResolver.resolve(conversation).travelMentioned;
    final requiresTerrain = outdoor &&
        _outdoorTerrainStems.any(
          (entry) =>
              _stemMatch(norm, entry.stem) &&
              const {
                'hor',
                'ferrat',
                'hub',
                'hrib',
                'les',
                'kop',
                'trail',
                'tur',
                'turist',
                'skal',
                'vrch',
                'sedlo',
                'hreben',
                'trek',
                'hiking',
              }.contains(entry.stem),
        );

    final activityLabelSk = outdoorLabel ?? poiLabel ?? venueLabel ?? routineLabel;
    final indoor = routineLocal || venueBound;
    final confidence = outdoor || routineLocal || venueBound || poiDependent || travel
        ? 0.88
        : 0.35;
    final reason = outdoor
        ? 'outdoor_semantic'
        : poiDependent
            ? 'poi_semantic'
            : routineLocal
                ? 'routine_local_semantic'
                : venueBound
                    ? 'venue_bound_semantic'
                    : travel
                        ? 'travel_semantic'
                        : 'no_clear_activity';

    return ActivityTraits(
      outdoor: outdoor,
      indoor: indoor,
      travel: travel,
      requiresTerrain: requiresTerrain,
      routineLocal: routineLocal && !outdoor && !poiDependent && !travel,
      venueBound: venueBound && !outdoor,
      poiDependent: poiDependent,
      activityLabelSk: activityLabelSk,
      confidence: confidence,
      reason: reason,
    );
  }

  static String _normalize(String input) => input
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('č', 'c')
      .replaceAll('ď', 'd')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ľ', 'l')
      .replaceAll('ĺ', 'l')
      .replaceAll('ň', 'n')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ŕ', 'r')
      .replaceAll('š', 's')
      .replaceAll('ť', 't')
      .replaceAll('ú', 'u')
      .replaceAll('ý', 'y')
      .replaceAll('ž', 'z');

  static bool _stemMatch(String normBlob, String stem) {
    if (stem.length < 3) return false;
    return RegExp(
      r'(?:^|[^a-z0-9])' + RegExp.escape(stem),
      caseSensitive: false,
    ).hasMatch(normBlob);
  }
}
