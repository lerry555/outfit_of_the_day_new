import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/debug/stylist_location_qa_runner.dart';

void main() {
  group('StylistLocationQaRunner', () {
    test('všetky krajiny → needsCityClarification, všetky mestá → canGenerate',
        () {
      final run = StylistLocationQaRunner.runAll(emitLogs: false);
      expect(run.meta.source, 'runtime_run');
      expect(run.meta.durationMs, greaterThanOrEqualTo(0));
      if (run.summary.failed > 0) {
        // ignore: avoid_print
        print(run.fullText());
      }
      expect(
        run.summary.countryBlocked,
        run.summary.countryTotal,
        reason: 'Nie všetky krajiny/regióny blokujú flow',
      );
      expect(
        run.summary.cityAllowed,
        run.summary.cityTotal,
        reason: 'Nie všetky mestá prepúšťajú flow',
      );
      expect(run.summary.failed, 0, reason: run.fullText());
    });

    test('má aspoň 150 prípadov vrátane M9 kategórií', () {
      expect(StylistLocationQaRunner.countryCases().length, greaterThanOrEqualTo(50));
      expect(StylistLocationQaRunner.cityCases().length, greaterThanOrEqualTo(50));
      expect(StylistLocationQaRunner.allCases().length, greaterThanOrEqualTo(150));
    });
  });
}
