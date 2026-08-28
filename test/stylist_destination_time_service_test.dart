import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/Services/stylist_destination_time_service.dart';

void main() {
  group('StylistDestinationTimeService', () {
    test('evaluates destination offset at the travel instant, including DST', () {
      final summer = DateTime.utc(2026, 8, 31, 12);
      final winter = DateTime.utc(2026, 1, 15, 12);

      expect(
        StylistDestinationTimeService.offsetMinutesForTimeZoneId(
          'Europe/Bratislava',
          summer,
        ),
        120,
      );
      expect(
        StylistDestinationTimeService.offsetMinutesForTimeZoneId(
          'Europe/London',
          summer,
        ),
        60,
      );
      expect(
        StylistDestinationTimeService.offsetMinutesForTimeZoneId(
          'Europe/London',
          winter,
        ),
        0,
      );
    });

    test('supports large positive and negative global timezone shifts', () {
      final instant = DateTime.utc(2026, 8, 31, 12);
      final auckland = StylistDestinationTimeService.offsetMinutesForTimeZoneId(
        'Pacific/Auckland',
        instant,
      );
      final losAngeles = StylistDestinationTimeService.offsetMinutesForTimeZoneId(
        'America/Los_Angeles',
        instant,
      );

      expect(auckland, isNotNull);
      expect(losAngeles, isNotNull);
      expect(auckland!, greaterThan(0));
      expect(losAngeles!, lessThan(0));
      expect(auckland - losAngeles, greaterThanOrEqualTo(18 * 60));
    });

    test('invalid timezone ids fail closed instead of inventing an offset', () {
      expect(
        StylistDestinationTimeService.offsetMinutesForTimeZoneId(
          'Not/A_Real_Timezone',
          DateTime.utc(2026, 8, 31, 12),
        ),
        isNull,
      );
    });
  });
}
