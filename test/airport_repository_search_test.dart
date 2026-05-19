import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'package:outfitofTheDay/Services/airport_repository.dart';
import 'package:outfitofTheDay/Services/airport_record.dart';
import 'package:outfitofTheDay/Services/flight_arrival_estimator.dart';
import 'package:outfitofTheDay/Services/flight_duration_estimator.dart';
import 'package:outfitofTheDay/Services/trip_flight_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    tzdata.initializeTimeZones();
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
