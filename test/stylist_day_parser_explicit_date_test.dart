import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/utils/stylist_day_parser.dart';

void main() {
  final now = DateTime(2026, 8, 28, 17, 48);

  test('resolves generic European and ISO date syntax', () {
    expect(
      StylistDayParser.resolveDate('12.12. mám svadbu', now: now),
      DateTime(2026, 12, 12),
    );
    expect(
      StylistDayParser.resolveDate('12/12 mám svadbu', now: now),
      DateTime(2026, 12, 12),
    );
    expect(
      StylistDayParser.resolveDate('12.12.2027 mám svadbu', now: now),
      DateTime(2027, 12, 12),
    );
    expect(
      StylistDayParser.resolveDate('2027-12-12 mám svadbu', now: now),
      DateTime(2027, 12, 12),
    );
  });

  test('yearless past date rolls to its next occurrence', () {
    expect(
      StylistDayParser.resolveDate('15.2. idem na oslavu', now: now),
      DateTime(2027, 2, 15),
    );
  });

  test('invalid calendar dates never normalize into another date', () {
    expect(
      StylistDayParser.resolveDate('31.2. mám svadbu', now: now),
      isNull,
    );
    expect(
      StylistDayParser.resolveDate('29.2.2027 mám svadbu', now: now),
      isNull,
    );
    expect(
      StylistDayParser.resolveDate('29.2.2028 mám svadbu', now: now),
      DateTime(2028, 2, 29),
    );
  });

  test('latest explicit temporal correction wins across syntax types', () {
    expect(
      StylistDayParser.resolveDate(
        'Najprv som myslel zajtra, ale svadba je 12.12.',
        now: now,
      ),
      DateTime(2026, 12, 12),
    );
    expect(
      StylistDayParser.resolveDate(
        'Pôvodne 12.12., nie, až v sobotu.',
        now: now,
      ),
      DateTime(2026, 8, 29),
    );
  });

  test('date parser is event-name agnostic', () {
    for (final event in <String>[
      'svadbu',
      'pohreb',
      'konferenciu',
      'výstavu',
      'XYZ udalosť',
    ]) {
      expect(
        StylistDayParser.resolveDate('5.11. idem na $event', now: now),
        DateTime(2026, 11, 5),
        reason: event,
      );
    }
  });
}
