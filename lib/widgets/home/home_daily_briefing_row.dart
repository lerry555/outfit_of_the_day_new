import 'package:flutter/material.dart';

import '../../utils/luxury_weather_emoji.dart';
import 'home_glass_surface.dart';
import 'home_luxury_palette.dart';

/// Sync with hero gaps before grid & `_HeroSegmentedDay` compact height (approx. weather line).
const double _kEmbeddedToggleBand = 42;
const double _kEmbeddedGapAfterToggle = 8;
const double _kEmbeddedGapBeforeGrid = 14;

/// Title „Prehľad dňa“ — rovnaký zlatý token ako Ráno / Poobedie / Večer v embedded briefing.
TextStyle homeUnifiedHeroPrehladTitleStyle() {
  return const TextStyle(
    color: HomeLuxuryPalette.accent,
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.15,
    height: 1.12,
  );
}

const double _kEmbeddedSharedDaypartGap = 8;

/// Prehľad dňa: vľavo zlatý segment, pod ním podmienka (celá šírka ľavého stĺpca); vpravo hore °C + emoji.
class HomeDailyBriefingRow extends StatelessWidget {
  const HomeDailyBriefingRow({
    super.key,
    required this.baseTempC,
    required this.briefingMorningCondition,
    required this.briefingAfternoonCondition,
    required this.briefingEveningCondition,
    this.sideColumn = false,
    this.compact = false,
    this.unifiedEmbedded = false,
    this.unifiedSharedBodyHeight,
    this.briefingMorningTempC,
    this.briefingAfternoonTempC,
    this.briefingEveningTempC,
  });

  final int baseTempC;
  final String briefingMorningCondition;
  final String briefingAfternoonCondition;
  final String briefingEveningCondition;
  final int? briefingMorningTempC;
  final int? briefingAfternoonTempC;
  final int? briefingEveningTempC;
  final bool sideColumn;
  final bool compact;
  final bool unifiedEmbedded;
  final double? unifiedSharedBodyHeight;

  @override
  Widget build(BuildContext context) {
    final useHourly = briefingMorningTempC != null &&
        briefingAfternoonTempC != null &&
        briefingEveningTempC != null;
    final morningT = useHourly ? briefingMorningTempC! : baseTempC - 1;
    final noonT = useHourly ? briefingAfternoonTempC! : baseTempC + 1;
    final eveT = useHourly ? briefingEveningTempC! : baseTempC - 2;

    if (sideColumn && compact) {
      final gap = unifiedEmbedded ? 0.0 : 10.0;
      final morningCard = _DailyBriefingItem(
        label: 'Ráno',
        tempC: morningT,
        caption: briefingMorningCondition,
        compact: true,
        embeddedInUnifiedHero: unifiedEmbedded,
      );
      final noonCard = _DailyBriefingItem(
        label: 'Poobedie',
        tempC: noonT,
        caption: briefingAfternoonCondition,
        compact: true,
        embeddedInUnifiedHero: unifiedEmbedded,
      );
      final eveCard = _DailyBriefingItem(
        label: 'Večer',
        tempC: eveT,
        caption: briefingEveningCondition,
        compact: true,
        embeddedInUnifiedHero: unifiedEmbedded,
      );

      if (unifiedEmbedded) {
        final sharedH = unifiedSharedBodyHeight;
        final column = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            morningCard,
            SizedBox(height: _kEmbeddedSharedDaypartGap),
            noonCard,
            SizedBox(height: _kEmbeddedSharedDaypartGap),
            eveCard,
          ],
        );
        if (sharedH != null) {
          return SizedBox(height: sharedH, child: column);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: _kEmbeddedToggleBand),
            SizedBox(height: _kEmbeddedGapAfterToggle),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Prehľad dňa', style: homeUnifiedHeroPrehladTitleStyle()),
            ),
            SizedBox(height: _kEmbeddedGapBeforeGrid),
            morningCard,
            const _BriefingEmbeddedDivider(),
            noonCard,
            const _BriefingEmbeddedDivider(),
            eveCard,
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          morningCard,
          SizedBox(height: gap),
          noonCard,
          SizedBox(height: gap),
          eveCard,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Denný briefing',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tri momenty dňa — skráť si rozhodovanie.',
          style: TextStyle(
            color: HomeLuxuryPalette.textSecondary.withOpacity(0.88),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),
        HomeGlassSurface(
          borderRadius: 16,
          blurSigma: 14,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DailyBriefingItem(
                label: 'Ráno',
                tempC: morningT,
                caption: briefingMorningCondition,
                sheetRow: true,
              ),
              const _BriefingSheetRowDivider(),
              _DailyBriefingItem(
                label: 'Poobedie',
                tempC: noonT,
                caption: briefingAfternoonCondition,
                sheetRow: true,
              ),
              const _BriefingSheetRowDivider(),
              _DailyBriefingItem(
                label: 'Večer',
                tempC: eveT,
                caption: briefingEveningCondition,
                sheetRow: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BriefingEmbeddedDivider extends StatelessWidget {
  const _BriefingEmbeddedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withOpacity(0.038),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HomeLuxuryPalette.accent.withOpacity(0.42),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withOpacity(0.038),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hairline between rows in the full „Denný briefing“ sheet.
class _BriefingSheetRowDivider extends StatelessWidget {
  const _BriefingSheetRowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        height: 1,
        color: Colors.white.withOpacity(0.045),
      ),
    );
  }
}

class _DailyBriefingItem extends StatelessWidget {
  const _DailyBriefingItem({
    required this.label,
    required this.tempC,
    required this.caption,
    this.compact = false,
    this.embeddedInUnifiedHero = false,
    this.sheetRow = false,
  });

  final String label;
  final int tempC;
  /// Jednoslovný / krátky štítok (Jasno, Dážď, …).
  final String caption;
  final bool compact;
  final bool embeddedInUnifiedHero;
  /// Row inside shared [HomeGlassSurface] — no extra glass, same 2-column editorial layout.
  final bool sheetRow;

  String get _tempLabel => '$tempC°C';

  String get _emoji => LuxuryWeatherEmoji.forConditionSk(caption);

  @override
  Widget build(BuildContext context) {
    final pad = compact
        ? const EdgeInsets.fromLTRB(10, 10, 10, 11)
        : const EdgeInsets.fromLTRB(12, 12, 12, 14);
    final emojiSize = compact ? 13.5 : 15.0;
    final tempSize = compact ? 13.5 : 18.0;
    final titleSize = compact ? 12.0 : 15.0;
    /// Jemne menšie pod „Poobedie“ / „Polooblačno“ bez orezávania.
    final bodySize = compact ? 10.4 : 11.9;

    double colGap() => sheetRow ? 6 : 5;

    double tempEmojiInnerGap() {
      if (sheetRow) return 5;
      if (embeddedInUnifiedHero) return 4;
      return 4.5;
    }

    /// Pravý stĺpec: horný riadok „17°C 🌤️“ (teplota + emoji), nižšie prázdne — podmienka je len vľavo pod segmentom.
    Widget weatherRightColumn({
      required double em,
      required TextStyle tempStyle,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(_tempLabel, style: tempStyle),
              SizedBox(width: tempEmojiInnerGap()),
              Text(
                _emoji,
                style: TextStyle(fontSize: em, height: 1.0),
              ),
            ],
          ),
        ],
      );
    }

    /// Ľavý stĺpec: zlatý segment, pod ním biela podmienka (môže zalomiť). Pravý: °C + emoji v jednom riadku hore.
    Widget compactBriefingRow({
      required TextStyle sectionTitleStyle,
      required TextStyle conditionStyle,
      required TextStyle tempStyle,
      required double em,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: sectionTitleStyle,
                ),
                SizedBox(height: sheetRow ? 5 : 4),
                Text(
                  caption,
                  textAlign: TextAlign.left,
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: conditionStyle,
                ),
              ],
            ),
          ),
          SizedBox(width: colGap()),
          weatherRightColumn(em: em, tempStyle: tempStyle),
        ],
      );
    }

    if (sheetRow) {
      return compactBriefingRow(
        sectionTitleStyle: TextStyle(
          color: HomeLuxuryPalette.accent,
          fontSize: titleSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.15,
          height: 1.15,
        ),
        conditionStyle: TextStyle(
          color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
          fontSize: bodySize,
          height: 1.25,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.02,
        ),
        tempStyle: TextStyle(
          color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
          fontSize: tempSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
          height: 1.12,
        ),
        em: emojiSize + 1,
      );
    }

    if (compact) {
      if (embeddedInUnifiedHero) {
        final tmpSz = tempSize - 0.5;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: compactBriefingRow(
            sectionTitleStyle: TextStyle(
              color: HomeLuxuryPalette.accent,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.15,
              height: 1.12,
            ),
            conditionStyle: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.92),
              fontSize: 10.3,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.02,
            ),
            tempStyle: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
              fontSize: tmpSz,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.35,
              height: 1.12,
            ),
            em: emojiSize + 0.35,
          ),
        );
      }

      final inner = compactBriefingRow(
        sectionTitleStyle: TextStyle(
          color: HomeLuxuryPalette.accent,
          fontSize: 12.0,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.12,
          height: 1.12,
        ),
        conditionStyle: TextStyle(
          color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
          fontSize: bodySize,
          height: 1.22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.02,
        ),
        tempStyle: TextStyle(
          color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
          fontSize: tempSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
          height: 1.12,
        ),
        em: emojiSize + 0.45,
      );

      return HomeGlassSurface(
        borderRadius: 13,
        blurSigma: 12,
        padding: pad,
        child: inner,
      );
    }

    return const SizedBox.shrink();
  }
}
