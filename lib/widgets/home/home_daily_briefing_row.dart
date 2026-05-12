import 'package:flutter/material.dart';

import 'home_glass_surface.dart';
import 'home_luxury_palette.dart';

/// Sync with hero gaps before grid & `_HeroSegmentedDay` compact height (approx. weather line).
const double _kEmbeddedToggleBand = 42;
const double _kEmbeddedGapAfterToggle = 8;
const double _kEmbeddedGapBeforeGrid = 14;

/// Title style next to `_HeroInlineWeather` in unified hero (single [Row], same cross-axis center).
TextStyle homeUnifiedHeroPrehladTitleStyle() {
  return TextStyle(
    color: HomeLuxuryPalette.accent.withOpacity(0.80),
    fontSize: 12.5,
    fontWeight: FontWeight.lerp(
      FontWeight.w600,
      FontWeight.w700,
      0.42,
    ),
    letterSpacing: 0.32,
    height: 1.22,
  );
}

const double _kEmbeddedSharedDaypartGap = 7;

/// Ráno / Poobedie / Večer — krátke štítky počasia (nie stylistický komentár).
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
    final morningRange = useHourly ? '7–9' : '6–12';
    final noonRange = useHourly ? '12–15' : '12–18';
    final eveRange = useHourly ? '18–21' : '18–23';

    if (sideColumn && compact) {
      final gap = unifiedEmbedded ? 0.0 : 9.0;
      final morningCard = _DailyBriefingItem(
        icon: Icons.wb_twilight_rounded,
        label: 'Ráno',
        timeRange: morningRange,
        tempC: morningT,
        shortPhrase: briefingMorningCondition,
        compact: true,
        embeddedInUnifiedHero: unifiedEmbedded,
      );
      final noonCard = _DailyBriefingItem(
        icon: Icons.wb_sunny_outlined,
        label: 'Poobedie',
        timeRange: noonRange,
        tempC: noonT,
        shortPhrase: briefingAfternoonCondition,
        compact: true,
        embeddedInUnifiedHero: unifiedEmbedded,
      );
      final eveCard = _DailyBriefingItem(
        icon: Icons.nights_stay_outlined,
        label: 'Večer',
        timeRange: eveRange,
        tempC: eveT,
        shortPhrase: briefingEveningCondition,
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
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 340;
            if (narrow) {
              return Column(
                children: [
                  _DailyBriefingItem(
                    icon: Icons.wb_twilight_rounded,
                    label: 'Ráno',
                    timeRange: '6:00 — 12:00',
                    tempC: morningT,
                    shortPhrase: briefingMorningCondition,
                  ),
                  const SizedBox(height: 10),
                  _DailyBriefingItem(
                    icon: Icons.wb_sunny_outlined,
                    label: 'Poobedie',
                    timeRange: '12:00 — 18:00',
                    tempC: noonT,
                    shortPhrase: briefingAfternoonCondition,
                  ),
                  const SizedBox(height: 10),
                  _DailyBriefingItem(
                    icon: Icons.nights_stay_outlined,
                    label: 'Večer',
                    timeRange: '18:00 — 23:00',
                    tempC: eveT,
                    shortPhrase: briefingEveningCondition,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _DailyBriefingItem(
                    icon: Icons.wb_twilight_rounded,
                    label: 'Ráno',
                    timeRange: '6 — 12',
                    tempC: morningT,
                    shortPhrase: briefingMorningCondition,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DailyBriefingItem(
                    icon: Icons.wb_sunny_outlined,
                    label: 'Poobedie',
                    timeRange: '12 — 18',
                    tempC: noonT,
                    shortPhrase: briefingAfternoonCondition,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DailyBriefingItem(
                    icon: Icons.nights_stay_outlined,
                    label: 'Večer',
                    timeRange: '18 — 23',
                    tempC: eveT,
                    shortPhrase: briefingEveningCondition,
                  ),
                ),
              ],
            );
          },
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

class _DailyBriefingItem extends StatelessWidget {
  const _DailyBriefingItem({
    required this.icon,
    required this.label,
    required this.timeRange,
    required this.tempC,
    required this.shortPhrase,
    this.compact = false,
    this.embeddedInUnifiedHero = false,
  });

  final IconData icon;
  final String label;
  final String timeRange;
  final int tempC;
  final String shortPhrase;
  final bool compact;
  final bool embeddedInUnifiedHero;

  String get _tempLabel => '$tempC°C';

  @override
  Widget build(BuildContext context) {
    final pad = compact
        ? const EdgeInsets.fromLTRB(9, 9, 9, 10)
        : const EdgeInsets.fromLTRB(12, 12, 12, 14);
    final iconBox = compact ? 8.0 : 7.0;
    final iconSize = compact ? 17.0 : 18.0;
    final tempSize = compact ? 13.0 : 17.0;
    final titleSize = compact ? 11.5 : 14.0;
    final timeSize = compact ? 9.5 : 11.0;
    final bodySize = compact ? 10.0 : 12.0;

    Widget phraseLine(TextStyle style) {
      return Text(
        shortPhrase,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    if (compact) {
      if (embeddedInUnifiedHero) {
        final titleStyle = TextStyle(
          color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          height: 1.12,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: iconSize + 0.5,
                      color: HomeLuxuryPalette.accent.withOpacity(0.85),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tempLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
                        fontSize: tempSize - 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.35,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: titleStyle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeRange,
                      style: TextStyle(
                        color:
                            HomeLuxuryPalette.textSecondary.withOpacity(0.72),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.15,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    phraseLine(
                      TextStyle(
                        color: HomeLuxuryPalette.textSecondary.withOpacity(0.90),
                        fontSize: 9,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.04,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      final inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(iconBox),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: HomeLuxuryPalette.accent.withOpacity(0.08),
                  border: Border.all(
                    color: HomeLuxuryPalette.accent.withOpacity(0.22),
                  ),
                ),
                child: Icon(icon, size: iconSize, color: HomeLuxuryPalette.accent),
              ),
              const Spacer(),
              Text(
                _tempLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary,
                  fontSize: tempSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.35,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '$label · $timeRange',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.12,
            ),
          ),
          const SizedBox(height: 4),
          phraseLine(
            TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.90),
              fontSize: bodySize,
              height: 1.22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.04,
            ),
          ),
        ],
      );

      return HomeGlassSurface(
        borderRadius: 13,
        blurSigma: 12,
        padding: pad,
        child: inner,
      );
    }

    return HomeGlassSurface(
      borderRadius: 16,
      blurSigma: 14,
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(iconBox),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: HomeLuxuryPalette.accent.withOpacity(0.14),
                  border: Border.all(
                    color: HomeLuxuryPalette.accent.withOpacity(0.32),
                  ),
                ),
                child: Icon(icon, size: iconSize, color: HomeLuxuryPalette.accent),
              ),
              const Spacer(),
              Text(
                _tempLabel,
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary,
                  fontSize: tempSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.35,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 10),
          Text(
            label,
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary,
              fontSize: titleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 1 : 2),
          Text(
            timeRange,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.85),
              fontSize: timeSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: compact ? 4 : 8),
          phraseLine(
            TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.92),
              fontSize: bodySize,
              height: compact ? 1.22 : 1.28,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.05,
            ),
          ),
        ],
      ),
    );
  }
}
