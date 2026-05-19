import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'package:outfitofTheDay/Services/airport_repository.dart';
import 'package:outfitofTheDay/Services/airport_record.dart';
import 'package:outfitofTheDay/Services/destination_airport_matcher.dart';
import 'package:outfitofTheDay/Services/flight_arrival_estimator.dart';
import 'package:outfitofTheDay/Services/flight_duration_estimator.dart';
import 'package:outfitofTheDay/Services/trip_flight_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  group('DestinationAirportMatcher', () {
    test('Miami, Florida, USA prefers MIA over unrelated airports', () async {
      final best = await DestinationAirportMatcher.matchBest(
        displayName: 'Miami, Florida, Spojené štáty americké',
        cityName: 'Miami',
        adminRegion: 'Florida',
        countryName: 'Spojené štáty americké',
      );
      expect(best, isNotNull);
      expect(best!.iata, anyOf('MIA', 'FLL'));
      expect(best.iata, isNot('AAC'));
    });

    test('Hurghada, Al-Bahr al-Ahmar, Egypt returns HRG', () async {
      final best = await DestinationAirportMatcher.matchBest(
        displayName: 'Hurghada, Al-Bahr al-Ahmar, Egypt',
        cityName: 'Hurghada',
        adminRegion: 'Al-Bahr al-Ahmar',
        countryName: 'Egypt',
      );
      expect(best?.iata, 'HRG');
    });

    test('Hurgada (SK geocoding spelling) returns HRG', () async {
      final best = await DestinationAirportMatcher.matchBest(
        displayName: 'Hurgada, Al-Bahr al-Ahmar, Egypt',
        cityName: 'Hurgada',
        adminRegion: 'Al-Bahr al-Ahmar',
        countryName: 'Egypt',
      );
      expect(best?.iata, 'HRG');
    });

    test('Malmotion, Malmotion country destination returns MLE', () async {
      final best = await DestinationAirportMatcher.matchBest(
        displayName: 'Maldivy, Maldivy',
        cityName: 'Malmotion',
        countryName: 'Malmotion',
      );
      expect(best?.iata, 'MLE');
    });

    test('Iceland country fallback returns KEF', () async {
      final best = await DestinationAirportMatcher.matchBest(
        displayName: 'Islandsko, Islandsko',
        cityName: 'Islandsko',
        countryName: 'Islandsko',
      );
      expect(best?.iata, 'KEF');
    });

    test('Zilina prefers BTS or VIE over ILZ', () async {
      final best = await DestinationAirportMatcher.matchBest(
        displayName: 'Žilina, Slovakia',
        cityName: 'Žilina',
        countryName: 'Slovakia',
        latitude: 49.2237,
        longitude: 18.7394,
      );
      expect(best, isNotNull);
      expect(best!.iata, isIn(['BTS', 'VIE']));
      expect(best.iata, isNot('ILZ'));
    });

    test('partial Kos uses country hub not Kosice', () async {
      final best = await DestinationAirportMatcher.matchBest(
        displayName: 'Koš, Slovakia',
        cityName: 'Koš',
        countryName: 'Slovakia',
      );
      expect(best?.iata, isIn(['BTS', 'VIE', 'TAT']));
    });

    test('Cyprus country fallback returns LCA', () async {
      final best = await DestinationAirportMatcher.matchBest(
        displayName: 'Cyprus, Cyprus',
        cityName: 'Cyprus',
        countryName: 'Cyprus',
      );
      expect(best?.iata, 'LCA');
    });
  });

  group('AirportRepository.search', () {
    test('London returns LHR, LGW, STN, LTN among suggestions', () async {
      final r = await AirportRepository.search('London', limit: 14);
      final iatas = r.map((e) => e.iata).toSet();
      expect(iatas, containsAll(['LHR', 'LGW', 'STN', 'LTN']),
          reason: 'got: ${r.map((e) => e.iata).join(", ")}');
    });

    test('"brat" includes BTS (Bratislava)', () async {
      final r = await AirportRepository.search('brat', limit: 14);
      expect(r.map((e) => e.iata), contains('BTS'));
    });

    test('"bratislava" includes BTS', () async {
      final r = await AirportRepository.search('bratislava', limit: 14);
      expect(r.map((e) => e.iata), contains('BTS'));
    });

    test('"bts" includes BTS', () async {
      final r = await AirportRepository.search('bts', limit: 14);
      expect(r.map((e) => e.iata), contains('BTS'));
    });

    test('"Hurghada" returns HRG', () async {
      final r = await AirportRepository.search('Hurghada', limit: 14);
      expect(r.map((e) => e.iata), contains('HRG'));
    });

    test('"HRG" returns HRG', () async {
      final r = await AirportRepository.search('HRG', limit: 14);
      expect(r.map((e) => e.iata), contains('HRG'));
    });
  });

  group('Flight estimates (smoke)', () {
    late AirportRecord bts;
    late AirportRecord hrg;
    late AirportRecord mia;

    setUp(() async {
      await AirportRepository.ensureLoaded();
      bts = AirportRepository.byIata('BTS')!;
      hrg = AirportRepository.byIata('HRG')!;
      mia = AirportRepository.byIata('MIA')!;
    });

    test('BTS -> HRG duration band and Hurghada/Cairo timezone', () {
      final dur = FlightDurationEstimator.estimate(from: bts, to: hrg);
      expect(dur.distanceKm, greaterThan(800));
      expect(dur.distanceKm, lessThan(3500));
      // ~3h50 block (heuristic); not a fake 2h30 short-haul
      expect(dur.estimatedDurationMinutes, greaterThan(200));
      expect(dur.estimatedDurationMinutes, lessThan(280));
      expect(dur.confidence, FlightEstimateConfidence.medium);

      final dep = DateTime(2026, 6, 1, 15, 0);
      final arr = FlightArrivalEstimator.estimate(from: bts, to: hrg, departureWallClock: dep);
      expect(arr.estimatedArrivalTimezoneIana, 'Africa/Cairo');
      expect(arr.timezoneConfidence, TripTimezoneConfidence.known);
      expect(arr.estimatedArrivalLocalNaive, isNotNull);
    });

    test('BTS -> MIA is long-haul with low confidence and connection warning', () {
      final dur = FlightDurationEstimator.estimate(from: bts, to: mia);
      expect(dur.distanceKm, greaterThan(8000));
      expect(dur.estimatedDurationMinutes, greaterThan(150)); // not 150 (2h30)
      expect(dur.confidence, FlightEstimateConfidence.low);
      expect(dur.warningText, isNotNull);
      expect(dur.warningText, contains('prestupom'));
    });
  });
}
