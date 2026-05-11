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

/// Tight vertical rhythm between Ráno / Poobedie / Večer in the shared hero body.
const double _kEmbeddedSharedDaypartGap = 7;

/// Day-part briefing (Ráno / Poobedie / Večer) — display-only microcopy from [baseTempC].
class HomeDailyBriefingRow extends StatelessWidget {
  const HomeDailyBriefingRow({
    super.key,
    required this.baseTempC,
    required this.isRainy,
    required this.isWindy,
    this.sideColumn = false,
    this.compact = false,
    this.unifiedEmbedded = false,
    /// When set with [unifiedEmbedded], day-part cards fill this height and use [MainAxisAlignment.spaceBetween].
    this.unifiedSharedBodyHeight,
  });

  final int baseTempC;
  final bool isRainy;
  final bool isWindy;

  /// Next to outfit card: stacked column, compact cards.
  final bool sideColumn;

  /// Shorter copy and tighter padding.
  final bool compact;

  /// Inside unified hero: no per-card glass shells — subtle fills only.
  final bool unifiedEmbedded;

  /// Shared hero body (bounded); pairs with [_UnifiedHeroSurface] outfit area height.
  final double? unifiedSharedBodyHeight;

  @override
  Widget build(BuildContext context) {
    final morningT = baseTempC - 1;
    final noonT = baseTempC + 1;
    final eveT = baseTempC - 2;

    /// Practical side-column copy (embedded + glass compact).
    String practicalMorning() => 'Ráno bude chladno.';

    String practicalNoon() => 'Okolo 16:00 môže pršať.';

    String practicalEvening() => 'Večer sa ochladí.';

    if (sideColumn && compact) {
      final gap = unifiedEmbedded ? 0.0 : 9.0;

      final morningCard = _DaypartCard(
        icon: Icons.wb_twilight_rounded,
        title: 'Ráno',
        timeLabel: '6–12',
        tempLabel: '$morningT°C',
        body: practicalMorning(),
        compact: true,
        embeddedInUnifiedHero: unifiedEmbedded,
      );
      final noonCard = _DaypartCard(
        icon: Icons.wb_sunny_outlined,
        title: 'Poobedie',
        timeLabel: '12–18',
        tempLabel: '$noonT°C',
        body: practicalNoon(),
        compact: true,
        embeddedInUnifiedHero: unifiedEmbedded,
      );
      final eveCard = _DaypartCard(
        icon: Icons.nights_stay_outlined,
        title: 'Večer',
        timeLabel: '18–23',
        tempLabel: '$eveT°C',
        body: practicalEvening(),
        compact: true,
        embeddedInUnifiedHero: unifiedEmbedded,
      );

      if (unifiedEmbedded) {
        final sharedH = unifiedSharedBodyHeight;
        final daypartColumn = Column(
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
          // Header + "Prehľad dňa" live in [_UnifiedHeroSurface] same row as weather; only cards here.
          return SizedBox(
            height: sharedH,
            child: daypartColumn,
          );
        }
        final prehladAndGap = <Widget>[
          SizedBox(height: _kEmbeddedToggleBand),
          SizedBox(height: _kEmbeddedGapAfterToggle),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Prehľad dňa', style: homeUnifiedHeroPrehladTitleStyle()),
          ),
          SizedBox(height: _kEmbeddedGapBeforeGrid),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ...prehladAndGap,
            morningCard,
            _BriefingEmbeddedDivider(),
            noonCard,
            _BriefingEmbeddedDivider(),
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

    String weatherHint() {
      if (isRainy) return 'Ber dáždnik — elegantná vrstva.';
      if (isWindy) return 'Jemný vietor — drž strih čistý.';
      return 'Prirodzený lesk materiálov.';
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
                  _DaypartCard(
                    icon: Icons.wb_twilight_rounded,
                    title: 'Ráno',
                    timeLabel: '6:00 — 12:00',
                    tempLabel: '$morningT°C',
                    body:
                        'Ľahší štart dňa. ${weatherHint()} Zvoľ čistú siluetu a neutrál.',
                  ),
                  const SizedBox(height: 10),
                  _DaypartCard(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Poobedie',
                    timeLabel: '12:00 — 18:00',
                    tempLabel: '$noonT°C',
                    body:
                        'Najdynamickejší blok. Vrstvy vieš upraviť podľa stretnutí.',
                  ),
                  const SizedBox(height: 10),
                  _DaypartCard(
                    icon: Icons.nights_stay_outlined,
                    title: 'Večer',
                    timeLabel: '18:00 — 23:00',
                    tempLabel: '$eveT°C',
                    body:
                        'Teplejší tón svetla — zjemni kontrast a pridaj textúru.',
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _DaypartCard(
                    icon: Icons.wb_twilight_rounded,
                    title: 'Ráno',
                    timeLabel: '6 — 12',
                    tempLabel: '$morningT°C',
                    body:
                        'Ľahší štart. ${weatherHint()} Čistá silueta, neutrál.',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DaypartCard(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Poobedie',
                    timeLabel: '12 — 18',
                    tempLabel: '$noonT°C',
                    body: 'Najdynamickejší blok. Vrstvy podľa dňa.',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DaypartCard(
                    icon: Icons.nights_stay_outlined,
                    title: 'Večer',
                    timeLabel: '18 — 23',
                    tempLabel: '$eveT°C',
                    body: 'Zjemni kontrast, viac textúry.',
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

/// Hairline + micro gold accent — separates embedded hero day-parts without card chrome.
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

class _DaypartCard extends StatelessWidget {
  const _DaypartCard({
    required this.icon,
    required this.title,
    required this.timeLabel,
    required this.tempLabel,
    required this.body,
    this.compact = false,
    this.embeddedInUnifiedHero = false,
  });

  final IconData icon;
  final String title;
  final String timeLabel;
  final String tempLabel;
  final String body;
  final bool compact;
  final bool embeddedInUnifiedHero;

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
    final maxBodyLines = compact ? 2 : 4;

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
                      tempLabel,
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
                          title,
                          maxLines: 1,
                          softWrap: false,
                          style: titleStyle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeLabel,
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
                    Text(
                      body,
                      softWrap: true,
                      style: TextStyle(
                        color:
                            HomeLuxuryPalette.textSecondary.withOpacity(0.90),
                        fontSize: 10.5,
                        height: 1.38,
                        fontWeight: FontWeight.w500,
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
                tempLabel,
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
            '$title · $timeLabel',
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
          Text(
            body,
            maxLines: maxBodyLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.88),
              fontSize: bodySize,
              height: 1.28,
              fontWeight: FontWeight.w500,
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
                tempLabel,
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
            title,
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary,
              fontSize: titleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 1 : 2),
          Text(
            timeLabel,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.85),
              fontSize: timeSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: compact ? 4 : 8),
          Text(
            body,
            maxLines: maxBodyLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.9),
              fontSize: bodySize,
              height: compact ? 1.25 : 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
