import 'dart:async';

import 'package:flutter/material.dart';
import 'package:outfitofTheDay/Services/shopping_wishlist_v2_service.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/shopping_ui_feature_flags.dart';
import 'shopping_candidate_ui.dart';

class ShoppingWishlistItemData {
  const ShoppingWishlistItemData({
    required this.wishlistItemId,
    required this.variantId,
    required this.selectedSizes,
    required this.preferredSize,
    required this.targetPrice,
    required this.priceMonitoringEnabled,
    required this.sizeMonitoringEnabled,
    required this.priceState,
    required this.highlightState,
    required this.highlightUnacknowledged,
    required this.lowStockState,
    required this.lifecycleState,
    required this.sortTier,
    required this.sortEventAt,
    required this.updatedAt,
    required this.stale,
    required this.priceVerifiedAt,
    required this.availabilityVerifiedAt,
    required this.candidate,
  });

  final String wishlistItemId;
  final String variantId;
  final Set<String> selectedSizes;
  final String? preferredSize;
  final ShoppingMoneyData targetPrice;
  final bool priceMonitoringEnabled, sizeMonitoringEnabled;
  final String priceState;
  final String highlightState;
  final bool highlightUnacknowledged;
  final String lowStockState;
  final String lifecycleState;
  final int sortTier;
  final int sortEventAt;
  final int updatedAt;
  final bool stale;
  final DateTime? priceVerifiedAt;
  final DateTime? availabilityVerifiedAt;
  final ShoppingCandidateData candidate;

  bool get isGold =>
      highlightState == 'GOLD' || highlightUnacknowledged;

  bool get isLowStock => lowStockState == 'LOW_STOCK';

  bool get isDiscontinued => lifecycleState == 'DISCONTINUED';

  factory ShoppingWishlistItemData.fromServer(Map<String, dynamic> value) {
    final projection = _map(value['currentCatalogProjection']);
    final candidate = _map(projection['candidate']).isNotEmpty
        ? _map(projection['candidate'])
        : projection;
    final tracking = _map(value['tracking']);
    final highlight = _map(tracking['highlight']);
    final freshness = _map(tracking['freshness']);
    final selected = value['selectedSizes'];
    final highlightState = tracking['highlightState']?.toString() ?? 'NONE';
    final lowStock = tracking['lowStockState']?.toString() ?? 'UNKNOWN';
    final sortTier = (tracking['sortTier'] as num?)?.toInt() ??
        (highlightState == 'GOLD' || highlight['state'] == 'UNACKNOWLEDGED'
            ? 0
            : lowStock == 'LOW_STOCK'
            ? 1
            : 2);
    return ShoppingWishlistItemData(
      wishlistItemId: value['wishlistItemId']?.toString() ?? '',
      variantId: value['variantId']?.toString() ?? '',
      selectedSizes: selected is List
          ? selected.map((item) => item.toString()).toSet()
          : const <String>{},
      preferredSize: _text(value['preferredSize']),
      targetPrice: ShoppingMoneyData.fromServer(value['targetPrice']),
      priceMonitoringEnabled: value['priceMonitoringEnabled'] == true,
      sizeMonitoringEnabled: value['sizeMonitoringEnabled'] == true,
      priceState: tracking['evaluatedPriceState']?.toString() ?? 'UNKNOWN',
      highlightState: highlightState,
      highlightUnacknowledged: highlight['state'] == 'UNACKNOWLEDGED',
      lowStockState: lowStock,
      lifecycleState: tracking['lifecycleState']?.toString() ?? 'UNKNOWN',
      sortTier: sortTier,
      sortEventAt: (tracking['sortEventAt'] as num?)?.toInt() ?? 0,
      updatedAt: (value['updatedAt'] as num?)?.toInt() ?? 0,
      stale: freshness['stale'] == true ||
          _map(_map(candidate['primaryOffer'])['freshness'])['stale'] == true,
      priceVerifiedAt: _parseTime(freshness['priceVerifiedAt']),
      availabilityVerifiedAt: _parseTime(freshness['availabilityVerifiedAt']),
      candidate: ShoppingCandidateData.fromServer(candidate),
    );
  }

  ShoppingWishlistIntent get intent => ShoppingWishlistIntent(
    variantId: variantId,
    selectedSizes: selectedSizes,
    preferredSize: preferredSize,
    targetAmountMinor: targetPrice.amountMinor,
    currency: targetPrice.currency,
    priceMonitoringEnabled: priceMonitoringEnabled,
    sizeMonitoringEnabled: sizeMonitoringEnabled,
  );

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};
  static String? _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _parseTime(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}

List<ShoppingWishlistItemData> sortWishlistItemsClientSide(
  Iterable<ShoppingWishlistItemData> items,
) {
  final sorted = items.toList();
  sorted.sort((a, b) {
    final tier = a.sortTier.compareTo(b.sortTier);
    if (tier != 0) return tier;
    final goldRank = (b.isGold ? 1 : 0) - (a.isGold ? 1 : 0);
    if (goldRank != 0) return goldRank;
    final lowRank = (b.isLowStock ? 1 : 0) - (a.isLowStock ? 1 : 0);
    if (lowRank != 0) return lowRank;
    final event = b.sortEventAt.compareTo(a.sortEventAt);
    if (event != 0) return event;
    return b.updatedAt.compareTo(a.updatedAt);
  });
  return sorted;
}

class ShoppingWishlistV2Screen extends StatefulWidget {
  const ShoppingWishlistV2Screen({
    super.key,
    required this.service,
    this.initialWishlistItemId,
    this.initialVariantId,
    @visibleForTesting this.forceCatalogExposure = false,
  });

  final ShoppingWishlistV2Gateway service;
  final String? initialWishlistItemId;
  final String? initialVariantId;

  /// Widget tests cannot set compile-time dart-defines; production stays gated.
  @visibleForTesting
  final bool forceCatalogExposure;

  @override
  State<ShoppingWishlistV2Screen> createState() =>
      _ShoppingWishlistV2ScreenState();
}

class _ShoppingWishlistV2ScreenState extends State<ShoppingWishlistV2Screen> {
  static const _goldBorder = Color(0xFFC8A36A);
  static const _goldFill = Color(0x18C8A36A);

  bool _loading = true;
  bool _refreshing = false;
  bool _ackInFlight = false;
  String? _error;
  List<ShoppingWishlistItemData> _items = const [];
  final Set<String> _sessionSeenGoldIds = <String>{};
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  bool _didScrollToInitial = false;

  bool get _catalogAllowed =>
      widget.forceCatalogExposure ||
      ShoppingUiFeatureFlags.mayExposeWishlistV2;

  @override
  void initState() {
    super.initState();
    if (_catalogAllowed) {
      _reload();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    unawaited(_acknowledgeSessionGold());
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await widget.service.getItems();
      if (!mounted) return;
      final items = sortWishlistItemsClientSide(
        values.map(ShoppingWishlistItemData.fromServer),
      );
      _trackVisibleGold(items);
      setState(() {
        _items = items;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToInitialTarget();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Wishlist sa nepodarilo načítať.';
      });
    }
  }

  void _trackVisibleGold(List<ShoppingWishlistItemData> items) {
    for (final item in items) {
      if (item.isGold && item.wishlistItemId.isNotEmpty) {
        _sessionSeenGoldIds.add(item.wishlistItemId);
      }
    }
  }

  Future<void> _acknowledgeSessionGold() async {
    if (_ackInFlight) return;
    final ids = _sessionSeenGoldIds.toList(growable: false);
    if (ids.isEmpty) return;
    _ackInFlight = true;
    try {
      await widget.service.acknowledge(ids);
      _sessionSeenGoldIds.clear();
    } catch (_) {
      // Best-effort on leave; do not block disposal.
    } finally {
      _ackInFlight = false;
    }
  }

  Future<void> _acknowledgeIds(List<String> ids) async {
    if (ids.isEmpty || _ackInFlight) return;
    _ackInFlight = true;
    try {
      await widget.service.acknowledge(ids);
      _sessionSeenGoldIds.removeAll(ids);
      if (!mounted) return;
      setState(() {
        _items = sortWishlistItemsClientSide(
          _items.map((item) {
            if (!ids.contains(item.wishlistItemId)) return item;
            return ShoppingWishlistItemData(
              wishlistItemId: item.wishlistItemId,
              variantId: item.variantId,
              selectedSizes: item.selectedSizes,
              preferredSize: item.preferredSize,
              targetPrice: item.targetPrice,
              priceMonitoringEnabled: item.priceMonitoringEnabled,
              sizeMonitoringEnabled: item.sizeMonitoringEnabled,
              priceState: item.priceState,
              highlightState: 'NONE',
              highlightUnacknowledged: false,
              lowStockState: item.lowStockState,
              lifecycleState: item.lifecycleState,
              sortTier: item.isLowStock ? 1 : 2,
              sortEventAt: item.sortEventAt,
              updatedAt: item.updatedAt,
              stale: item.stale,
              priceVerifiedAt: item.priceVerifiedAt,
              availabilityVerifiedAt: item.availabilityVerifiedAt,
              candidate: item.candidate,
            );
          }),
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zvýraznenie sa nepodarilo potvrdiť.')),
      );
    } finally {
      _ackInFlight = false;
    }
  }

  Future<void> _refreshAll() async {
    if (_refreshing || !_catalogAllowed) return;
    setState(() => _refreshing = true);
    try {
      await widget.service.refreshAll();
      final values = await widget.service.getItems();
      if (!mounted) return;
      final items = sortWishlistItemsClientSide(
        values.map(ShoppingWishlistItemData.fromServer),
      );
      _trackVisibleGold(items);
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktualizácia wishlistu zlyhala.')),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _scrollToInitialTarget() {
    if (_didScrollToInitial || !mounted) return;
    final wishlistId = widget.initialWishlistItemId?.trim();
    final variantId = widget.initialVariantId?.trim();
    GlobalKey? key;
    if (wishlistId != null && wishlistId.isNotEmpty) {
      key = _itemKeys[wishlistId];
    } else if (variantId != null && variantId.isNotEmpty) {
      for (final item in _items) {
        if (item.variantId == variantId) {
          key = _itemKeys[item.wishlistItemId];
          break;
        }
      }
    }
    final ctx = key?.currentContext;
    if (ctx == null) return;
    _didScrollToInitial = true;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      alignment: 0.1,
    );
  }

  Future<void> _visitStore(ShoppingWishlistItemData item) async {
    final url = item.candidate.primaryOffer?.url;
    if (item.wishlistItemId.isNotEmpty) {
      unawaited(widget.service.refreshItem(item.wishlistItemId));
    }
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return;
    if (ShoppingUiFeatureFlags.fixtureMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixture odkaz bol bezpečne zachytený.')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) unawaited(_acknowledgeSessionGold());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wishlist'),
          actions: [
            if (_catalogAllowed)
              TextButton(
                key: const Key('wishlist_refresh_all'),
                onPressed: _refreshing ? null : _refreshAll,
                child: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Aktualizovať všetko'),
              ),
          ],
        ),
        body: !_catalogAllowed
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Wishlist momentálne nie je dostupný.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : switch ((_loading, _error)) {
                (true, _) => const Center(child: CircularProgressIndicator()),
                (_, final error?) => Center(child: Text(error)),
                _ when _items.isEmpty => const Center(
                  child: Text('Wishlist je zatiaľ prázdny.'),
                ),
                _ => ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) => _item(_items[index]),
                ),
              },
      ),
    );
  }

  Widget _item(ShoppingWishlistItemData item) {
    final key = _itemKeys.putIfAbsent(
      item.wishlistItemId,
      GlobalKey.new,
    );
    final statusLines = _statusLines(item);
    return Card(
      key: key,
      color: item.isGold ? _goldFill : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: item.isGold ? _goldBorder : Colors.transparent,
          width: item.isGold ? 1.4 : 0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.isGold)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Nová zmena',
                  style: TextStyle(
                    color: _goldBorder,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Text(
              item.candidate.isUsable
                  ? item.candidate.title
                  : 'Produkt momentálne nie je v katalógu',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text('Veľkosti: ${item.selectedSizes.join(', ')}'),
            if (item.preferredSize != null)
              Text('Preferovaná: ${item.preferredSize}'),
            Text('Cieľ: ${item.targetPrice.label}'),
            Text('Aktuálny stav ceny: ${_priceState(item.priceState)}'),
            Text(
              'Cena ${item.priceMonitoringEnabled ? 'sledovaná' : 'nesledovaná'} · '
              'veľkosti ${item.sizeMonitoringEnabled ? 'sledované' : 'nesledované'}',
            ),
            for (final line in statusLines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  line,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            ..._freshnessLabels(item).map(
              (line) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(line, style: const TextStyle(fontSize: 12)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (item.isGold)
                  TextButton(
                    onPressed: () => _acknowledgeIds([item.wishlistItemId]),
                    child: const Text('Rozumiem'),
                  ),
                if (item.candidate.primaryOffer?.url != null)
                  TextButton(
                    onPressed: () => _visitStore(item),
                    child: const Text('Navštíviť obchod'),
                  ),
                TextButton(
                  onPressed: item.candidate.isUsable ? () => _edit(item) : null,
                  child: const Text('Upraviť'),
                ),
                TextButton(
                  onPressed: () => _remove(item),
                  child: const Text('Odstrániť'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _statusLines(ShoppingWishlistItemData item) {
    final lines = <String>[];
    if (item.isDiscontinued) {
      lines.add('Produkt už nie je v ponuke.');
    }
    if (item.stale) {
      lines.add('Údaje môžu byť zastarané.');
    }
    if (item.isLowStock) {
      lines.add('Nízky stav skladu.');
    }
    if (item.priceState == 'UNSATISFIED') {
      lines.add('Cena je opäť nad cieľom.');
    }
    final availability = item.candidate.primarySelectedSize?.availability;
    if (availability == 'UNAVAILABLE') {
      lines.add('Momentálne nedostupné.');
    } else if (!item.candidate.isUsable && !item.isDiscontinued) {
      lines.add('Momentálne nedostupné.');
    }
    return lines;
  }

  List<String> _freshnessLabels(ShoppingWishlistItemData item) {
    final lines = <String>[];
    final priceAt = item.priceVerifiedAt ??
        item.candidate.primaryOffer?.priceVerifiedAt;
    final availabilityAt = item.availabilityVerifiedAt ??
        item.candidate.primaryOffer?.availabilityVerifiedAt;
    if (priceAt != null) {
      lines.add('Cena aktualizovaná ${_formatTimestamp(priceAt)}');
    }
    if (availabilityAt != null) {
      lines.add('Dostupnosť aktualizovaná ${_formatTimestamp(availabilityAt)}');
    }
    return lines;
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    return '${local.day}. ${local.month}. $hour:$minute';
  }

  Future<void> _edit(ShoppingWishlistItemData item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ShoppingWishlistEditor(
        candidate: item.candidate,
        initialIntent: item.intent,
        onDismissed: () => Navigator.of(sheetContext).pop(),
        onSave: (intent) async {
          await widget.service.update(intent);
          await _reload();
        },
      ),
    );
  }

  Future<void> _remove(ShoppingWishlistItemData item) async {
    try {
      await widget.service.remove(item.variantId);
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Položku sa nepodarilo odstrániť.')),
      );
    }
  }

  String _priceState(String value) => switch (value) {
    'SATISFIED' => 'cieľ splnený',
    'UNSATISFIED' => 'nad cieľom',
    _ => 'neoverený',
  };
}
