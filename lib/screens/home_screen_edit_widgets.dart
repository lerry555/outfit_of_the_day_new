part of 'home_screen.dart';

/// =======================
/// Ostatné widgety (nezmenené)
/// =======================
class _HeroEditActionSheet extends StatelessWidget {
  const _HeroEditActionSheet({
    required this.onAiSuggest,
    required this.onManualPick,
    required this.onFeedback,
  });

  final VoidCallback onAiSuggest;
  final VoidCallback onManualPick;
  final VoidCallback onFeedback;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + safeBottom),
      child: HomeGlassSurface(
        borderRadius: 20,
        blurSigma: 18,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeroEditSheetAction(
              emoji: '✨',
              title: 'AI navrhne inú',
              onTap: onAiSuggest,
            ),
            const SizedBox(height: 8),
            _HeroEditSheetAction(
              emoji: '👕',
              title: 'Vyberiem si sám',
              onTap: onManualPick,
            ),
            const SizedBox(height: 8),
            _HeroEditSheetAction(
              emoji: '💬',
              title: 'Napíš čo ti vadí',
              onTap: onFeedback,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroEditSheetAction extends StatelessWidget {
  const _HeroEditSheetAction({
    required this.emoji,
    required this.title,
    required this.onTap,
  });
  final String emoji;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: HomeLuxuryPalette.surface.withOpacity(0.5),
            border: Border.all(color: HomeLuxuryPalette.border),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualCategoryOption {
  const _ManualCategoryOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class _EditHelperPanel extends StatelessWidget {
  const _EditHelperPanel({
    this.withGlassBackground = false,
  });

  final bool withGlassBackground;

  @override
  Widget build(BuildContext context) {
    final helperContent = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vyber kúsok na úpravu',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.08,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Môžeš ho zmeniť alebo odstrániť z outfitu.',
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.92),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, right: 6),
        child: withGlassBackground
            ? Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: HomeLuxuryPalette.surfaceSoft.withOpacity(0.26),
                  border: Border.all(
                    color: HomeLuxuryPalette.accent.withOpacity(0.12),
                  ),
                ),
                child: HomeGlassSurface(
                  borderRadius: 16,
                  blurSigma: 10,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: helperContent,
                ),
              )
            : helperContent,
      ),
    );
  }
}

/// SET-019: category chips live in State so overrideGroup survives parent
/// rebuilds. Always visible — no nested modal and no toggle that can drop
/// the selected group.
class _HomeManualSwapSheet extends StatefulWidget {
  const _HomeManualSwapSheet({
    required this.host,
    required this.sheetContext,
    required this.type,
    required this.currentItem,
    required this.user,
  });

  final _HomeScreenState host;
  final BuildContext sheetContext;
  final _HeroWearType type;
  final _HeroOutfitItem? currentItem;
  final User user;

  @override
  State<_HomeManualSwapSheet> createState() => _HomeManualSwapSheetState();
}

class _HomeManualSwapSheetState extends State<_HomeManualSwapSheet> {
  String? overrideGroup;

  _HomeScreenState get host => widget.host;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.56,
      maxChildSize: 0.9,
      builder: (_, controller) {
        return HomeGlassSurface(
          borderRadius: 22,
          blurSigma: 16,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: host._wardrobeStream(widget.user.uid),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? const [];
              final allNormalized = docs
                  .map((d) {
                    final m = Map<String, dynamic>.from(d.data());
                    m['id'] = d.id;
                    return host._normalizedWardrobeMapForHome(m);
                  })
                  .toList(growable: false);
              final defaultGroup = host._manualDefaultGroupForCurrentItem(
                widget.type,
                widget.currentItem,
              );
              final activeGroup = overrideGroup ?? defaultGroup;
              var filtered = allNormalized
                  .where(
                    (raw) => host._matchesManualGroup(
                      raw,
                      activeGroup,
                      widget.type,
                    ),
                  )
                  .toList();
              if (widget.type == _HeroWearType.shoes &&
                  filtered.isNotEmpty) {
                filtered = host._applyFootwearGuidanceToSwapCandidates(
                  candidates: filtered,
                  wardrobeForInventory: allNormalized,
                );
              }
              if (widget.type == _HeroWearType.bottom &&
                  filtered.isNotEmpty) {
                filtered = host._applyBottomGuidanceToSwapCandidates(
                  candidates: filtered,
                  wardrobeForInventory: allNormalized,
                );
              }
              final overrideOptions = host._manualOverrideOptions(
                widget.type,
              );
              final matching = overrideOptions
                  .where((o) => o.id == activeGroup)
                  .toList();
              final activeLabel = matching.isEmpty
                  ? null
                  : matching.first.label;
              debugPrint(
                '[HOME_SWAP_CATEGORY] type=${widget.type.name} activeGroup=$activeGroup '
                'filtered=${filtered.length} '
                'ids=${filtered.map(OutfitGenerationService.wardrobeItemId).join(",")}',
              );
              return CustomScrollView(
                controller: controller,
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Čím chceš nahradiť tento kúsok?',
                          style: TextStyle(
                            color: HomeLuxuryPalette.textPrimary.withOpacity(
                              0.96,
                            ),
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Použiť inú kategóriu',
                          style: TextStyle(
                            color: HomeLuxuryPalette.accent.withOpacity(0.96),
                            fontSize: 12.6,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.08,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final option in overrideOptions)
                              Semantics(
                                button: true,
                                label: option.label,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () {
                                      setState(() => overrideGroup = option.id);
                                      debugPrint(
                                        '[HOME_SWAP_CATEGORY] overrideGroup=${option.id} '
                                        'label=${option.label} type=${widget.type.name}',
                                      );
                                    },
                                    child: Ink(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        color: activeGroup == option.id
                                            ? HomeLuxuryPalette.accent
                                                .withOpacity(0.28)
                                            : HomeLuxuryPalette.surface
                                                .withOpacity(0.56),
                                        border: Border.all(
                                          color: activeGroup == option.id
                                              ? HomeLuxuryPalette.accent
                                                  .withOpacity(0.72)
                                              : HomeLuxuryPalette.border,
                                        ),
                                      ),
                                      child: Text(
                                        option.label,
                                        style: TextStyle(
                                          color: HomeLuxuryPalette.textPrimary
                                              .withOpacity(0.94),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (activeLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Text(
                              activeLabel,
                              style: TextStyle(
                                color: HomeLuxuryPalette.textSecondary
                                    .withOpacity(0.86),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            widget.type == _HeroWearType.shoes
                                ? 'Pre dnešné počasie nemáš vhodnejšiu obuv na výmenu.'
                                : widget.type == _HeroWearType.bottom
                                ? 'Pre dnešnú teplotu nemáš vhodnejší spodný diel na výmenu.'
                                : 'V tejto kategórii zatiaľ nemáš ďalší kúsok.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: HomeLuxuryPalette.textSecondary
                                  .withOpacity(0.88),
                              fontSize: 14,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.76,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final raw = filtered[i];
                          final label = host._heroLabelForWardrobeItem(
                            raw,
                            fallback: host._heroFallbackLabelForType(
                              widget.type,
                            ),
                          );
                          final item = host._heroItemFromWardrobe(
                            raw: raw,
                            type: widget.type,
                          );
                          final current = widget.currentItem;
                          final isCurrent =
                              current != null &&
                              current.label == item.label &&
                              current.type == item.type;
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              final currentOutfit = List<_HeroOutfitItem>.from(
                                host._editedOutfitByDay[host._dayIndex] ??
                                    const [],
                              );
                              final idx = currentOutfit.indexWhere(
                                (it) => it.type == widget.type,
                              );
                              final oldId = idx >= 0
                                  ? (currentOutfit[idx].wardrobeItemId ?? '')
                                      .trim()
                                  : '';
                              final replaced =
                                  idx >= 0 ? currentOutfit[idx] : null;
                              if (idx >= 0) {
                                currentOutfit[idx] = item;
                              } else {
                                currentOutfit.add(item);
                              }
                              final newId = (item.wardrobeItemId ?? '').trim();
                              host._commitHomeOutfitItemReplacement(
                                wearType: widget.type,
                                newItem: item,
                                updatedOutfit: currentOutfit,
                                replacedItem: replaced,
                              );
                              if (newId.isNotEmpty) {
                                host._swapLastSuggestedItemIdByTypeByDay
                                        .putIfAbsent(
                                      host._dayIndex,
                                      () => {},
                                    )[widget.type] =
                                    newId;
                              }
                              debugPrint(
                                '[HOME_SWAP] accept replacement oldId=$oldId newId=$newId',
                              );
                              debugPrint(
                                '[HOME_SWAP] marked_manual_edit=true',
                              );
                              debugPrint(
                                '[HOME_SWAP] prevented_ai_restore=true',
                              );
                              debugPrint(
                                '[HOME_TEST_A] locked_slot=${widget.type.name} itemId=$newId label=$label group=$activeGroup',
                              );
                              Navigator.of(widget.sheetContext).pop();
                            },
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: HomeLuxuryPalette.surface.withOpacity(
                                  0.56,
                                ),
                                border: Border.all(
                                  color: isCurrent
                                      ? HomeLuxuryPalette.accent.withOpacity(
                                          0.46,
                                        )
                                      : HomeLuxuryPalette.border,
                                ),
                                boxShadow: [
                                  if (isCurrent)
                                    BoxShadow(
                                      color: HomeLuxuryPalette.accent
                                          .withOpacity(0.18),
                                      blurRadius: 16,
                                      spreadRadius: 0,
                                    ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(11),
                                      child: ColoredBox(
                                        color: HomeLuxuryPalette.bgMid
                                            .withOpacity(0.34),
                                        child: _HeroOutfitImageView(
                                          heroDayKey: 'manual_picker',
                                          imageUrl: item.imageUrl,
                                          fallbackIcon: item.icon,
                                          wearType: item.type,
                                          compact: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  Expanded(
                                    child: Text(
                                      label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: HomeLuxuryPalette.textPrimary
                                            .withOpacity(0.92),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
