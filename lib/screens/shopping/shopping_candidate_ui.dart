import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _bg = Color(0xFF26262C);
const _surface = Color(0xFF1B1B1F);
const _gold = Color(0xFFC8A36A);
const _text = Color(0xFFF1F0EC);
const _muted = Color(0xFFAAA59B);

class ShoppingMoneyData {
  const ShoppingMoneyData({required this.amountMinor, required this.currency});
  final int amountMinor;
  final String currency;

  factory ShoppingMoneyData.fromServer(dynamic value) {
    final map = ShoppingCandidateData._map(value);
    return ShoppingMoneyData(
      amountMinor: (map['amountMinor'] as num?)?.toInt() ?? 0,
      currency: map['currency']?.toString() ?? '',
    );
  }

  String get label {
    final symbol = currency == 'EUR' ? '€' : currency;
    return '${NumberFormat('#,##0.00', 'sk_SK').format(amountMinor / 100)} $symbol';
  }
}

class ShoppingSizeEvidenceData {
  const ShoppingSizeEvidenceData({
    required this.key,
    required this.label,
    required this.availability,
    required this.preferred,
    this.reliableQuantity,
    this.verifiedAt,
  });
  final String key, label, availability;
  final bool preferred;
  final int? reliableQuantity;
  final DateTime? verifiedAt;

  factory ShoppingSizeEvidenceData.fromServer(dynamic value) {
    final map = ShoppingCandidateData._map(value);
    return ShoppingSizeEvidenceData(
      key: map['normalizedSizeKey']?.toString() ?? '',
      label: (map['displayLabel'] ?? map['normalizedSizeKey'] ?? '').toString(),
      availability: map['availability']?.toString() ?? 'UNKNOWN',
      preferred: map['preferred'] == true,
      reliableQuantity: (map['reliableQuantity'] as num?)?.toInt(),
      verifiedAt: DateTime.tryParse(
        map['availabilityVerifiedAt']?.toString() ?? '',
      ),
    );
  }
}

class ShoppingOfferData {
  const ShoppingOfferData({
    required this.offerId,
    required this.storeName,
    required this.regularPrice,
    required this.effectivePrice,
    required this.selectedSizes,
    required this.stale,
    this.salePrice,
    this.couponCode,
    this.url,
    this.priceVerifiedAt,
    this.availabilityVerifiedAt,
  });
  final String offerId, storeName;
  final ShoppingMoneyData regularPrice, effectivePrice;
  final ShoppingMoneyData? salePrice;
  final String? couponCode, url;
  final List<ShoppingSizeEvidenceData> selectedSizes;
  final bool stale;
  final DateTime? priceVerifiedAt, availabilityVerifiedAt;

  factory ShoppingOfferData.fromServer(dynamic value) {
    final map = ShoppingCandidateData._map(value);
    final effective = ShoppingCandidateData._map(map['effectivePrice']);
    final freshness = ShoppingCandidateData._map(map['freshness']);
    final rawSizes = map['selectedSizes'];
    return ShoppingOfferData(
      offerId: map['offerId']?.toString() ?? '',
      storeName:
          ShoppingCandidateData._map(map['store'])['displayName']?.toString() ??
          '',
      regularPrice: ShoppingMoneyData.fromServer(map['regularPrice']),
      salePrice: map['salePrice'] is Map
          ? ShoppingMoneyData.fromServer(map['salePrice'])
          : null,
      effectivePrice: ShoppingMoneyData.fromServer(
        effective['price'] ?? effective,
      ),
      couponCode: ShoppingCandidateData._nullable(effective['couponCode']),
      url: ShoppingCandidateData._nullable(map['url']),
      selectedSizes: rawSizes is List
          ? rawSizes
                .map(ShoppingSizeEvidenceData.fromServer)
                .toList(growable: false)
          : const [],
      stale: freshness['stale'] == true,
      priceVerifiedAt: DateTime.tryParse(
        freshness['priceVerifiedAt']?.toString() ?? '',
      ),
      availabilityVerifiedAt: DateTime.tryParse(
        freshness['availabilityVerifiedAt']?.toString() ?? '',
      ),
    );
  }
}

class ShoppingCandidateData {
  const ShoppingCandidateData._({
    required this.variantId,
    required this.title,
    required this.brand,
    required this.color,
    required this.priceMinor,
    required this.currency,
    required this.couponCode,
    required this.sizeLabel,
    required this.freshnessLabel,
    required this.isStale,
    required this.primaryOffer,
    required this.alternativeOffers,
    required this.raw,
  });

  final String variantId;
  final String title;
  final String brand;
  final String color;
  final int? priceMinor;
  final String currency;
  final String? couponCode;
  final String sizeLabel;
  final String freshnessLabel;
  final bool isStale;
  final ShoppingOfferData? primaryOffer;
  final List<ShoppingOfferData> alternativeOffers;
  final Map<String, dynamic> raw;

  bool get isUsable => variantId.isNotEmpty;
  ShoppingSizeEvidenceData? get primarySelectedSize =>
      primaryOffer != null && primaryOffer!.selectedSizes.isNotEmpty
      ? primaryOffer!.selectedSizes.first
      : null;

  /// Parses only the server-authoritative candidate DTO attachment.
  /// Unknown/malformed pricing is displayed as unknown, never as a client guess.
  factory ShoppingCandidateData.fromServer(Map<String, dynamic> value) {
    final primaryMap = _map(value['primaryOffer']);
    final primary = primaryMap.isEmpty
        ? null
        : ShoppingOfferData.fromServer(primaryMap);
    final rawAlternatives = value['alternativeOffers'];
    final alternatives = rawAlternatives is List
        ? rawAlternatives
              .map(ShoppingOfferData.fromServer)
              .toList(growable: false)
        : const <ShoppingOfferData>[];
    final effective = _map(value['effectivePublicPrice']);
    final price = _map(effective['price']).isNotEmpty
        ? _map(effective['price'])
        : effective;
    final evidence = primary == null
        ? _map(value['selectedSizeEvidence'])
        : const <String, dynamic>{};
    final freshness = primary == null
        ? _map(value['freshnessEvidence'])
        : const <String, dynamic>{};
    final amount = primary?.effectivePrice.amountMinor ?? price['amountMinor'];
    final available = evidence['purchasableForSelectedSize'];
    final selected = primary != null && primary.selectedSizes.isNotEmpty
        ? primary.selectedSizes.first
        : null;
    final selectedSize =
        selected?.label ??
        (evidence['selectedSizeKey'] ?? evidence['preferredSizeKey'] ?? '')
            .toString()
            .trim();
    final stale = primary?.stale ?? freshness['stale'] == true;
    final availabilityValue = selected?.availability;
    final availability = availabilityValue == 'AVAILABLE' || available == true
        ? 'skladom'
        : availabilityValue == 'UNAVAILABLE' || available == false
        ? 'momentálne nedostupná'
        : 'neoverená dostupnosť';
    return ShoppingCandidateData._(
      variantId: value['variantId']?.toString() ?? '',
      title:
          (value['displayName'] ?? value['canonicalType'] ?? 'Overený produkt')
              .toString(),
      brand: (value['brand'] ?? '').toString(),
      color: (value['exactColorName'] ?? '').toString(),
      priceMinor: amount is num ? amount.toInt() : null,
      currency:
          primary?.effectivePrice.currency ??
          (price['currency'] ?? '').toString(),
      couponCode: primary?.couponCode ?? _nullable(effective['couponCode']),
      sizeLabel: selectedSize.isEmpty
          ? 'Veľkosť nebola overená'
          : '$selectedSize — $availability',
      freshnessLabel: _freshnessLabel(primary, stale),
      isStale: stale,
      primaryOffer: primary,
      alternativeOffers: alternatives,
      raw: Map<String, dynamic>.unmodifiable(value),
    );
  }

  ShoppingCandidateData withDetail(Map<String, dynamic> value) {
    final candidateMap = _map(value['candidate']);
    return ShoppingCandidateData.fromServer({
      ...raw,
      ...candidateMap,
      if (value['primaryOffer'] != null) 'primaryOffer': value['primaryOffer'],
      if (value['alternativeOffers'] != null)
        'alternativeOffers': value['alternativeOffers'],
    });
  }

  String get priceLabel {
    if (priceMinor == null || currency.isEmpty) {
      return 'Cena sa nepodarila overiť';
    }
    final amount = priceMinor! / 100;
    final symbol = currency == 'EUR' ? '€' : currency;
    return '${NumberFormat('#,##0.00', 'sk_SK').format(amount)} $symbol';
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};
  static String? _nullable(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String _freshnessLabel(ShoppingOfferData? offer, bool stale) {
    if (stale) return 'Údaje môžu byť staršie';
    final price = offer?.priceVerifiedAt;
    final availability = offer?.availabilityVerifiedAt;
    if (price == null && availability == null) return 'Overené údaje katalógu';
    if (price != null &&
        availability != null &&
        price.isAtSameMomentAs(availability)) {
      return 'Cena a dostupnosť overené ${_formatTimestamp(price)}';
    }
    return [
      if (price != null) 'Cena ${_formatTimestamp(price)}',
      if (availability != null) 'Dostupnosť ${_formatTimestamp(availability)}',
    ].join(' · ');
  }

  static String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    return '${local.day}. ${local.month}. $hour:$minute';
  }
}

class ShoppingCandidateCard extends StatelessWidget {
  const ShoppingCandidateCard({
    super.key,
    required this.candidate,
    this.rank,
    this.onTap,
    this.onWishlist,
  });

  final ShoppingCandidateData candidate;
  final int? rank;
  final VoidCallback? onTap;
  final VoidCallback? onWishlist;

  @override
  Widget build(BuildContext context) {
    final rankLabel = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    return Semantics(
      button: onTap != null,
      label:
          '${candidate.title}, ${candidate.priceLabel}, ${candidate.sizeLabel}',
      child: Card(
        color: _bg,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _gold.withValues(alpha: .45)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: _surface,
                      child: Icon(Icons.checkroom_outlined, color: _gold),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        candidate.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (rankLabel != null)
                      Chip(
                        label: Text(rankLabel),
                        visualDensity: VisualDensity.compact,
                        labelStyle: const TextStyle(color: _text, fontSize: 14),
                        backgroundColor: _gold.withValues(alpha: .18),
                        side: BorderSide.none,
                      ),
                  ],
                ),
                if (candidate.brand.isNotEmpty ||
                    candidate.color.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    [
                      candidate.brand,
                      candidate.color,
                    ].where((item) => item.isNotEmpty).join(' · '),
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 9),
                Text(
                  candidate.priceLabel,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                if (candidate.primaryOffer?.salePrice != null)
                  Text(
                    candidate.primaryOffer!.regularPrice.label,
                    style: const TextStyle(
                      color: _muted,
                      decoration: TextDecoration.lineThrough,
                      fontSize: 12,
                    ),
                  ),
                if (candidate.primaryOffer?.storeName.isNotEmpty == true)
                  Text(
                    candidate.primaryOffer!.storeName,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                if (candidate.couponCode != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      's kódom ${candidate.couponCode}',
                      style: const TextStyle(color: _gold, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 8),
                _StatusLine(
                  icon: Icons.straighten_outlined,
                  text: candidate.sizeLabel,
                  warning: candidate.sizeLabel.contains('nedostupná'),
                ),
                if ((candidate.primarySelectedSize?.reliableQuantity ?? 0) > 0)
                  _StatusLine(
                    icon: Icons.inventory_2_outlined,
                    text:
                        '${candidate.primarySelectedSize!.label} — posledné ${candidate.primarySelectedSize!.reliableQuantity} ks',
                    warning: true,
                  ),
                _StatusLine(
                  icon: candidate.isStale
                      ? Icons.schedule_outlined
                      : Icons.verified_outlined,
                  text: candidate.freshnessLabel,
                  warning: candidate.isStale,
                ),
                if (onWishlist != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: onWishlist,
                      icon: const Icon(Icons.favorite_border, size: 18),
                      label: const Text('Pridať do Wishlistu'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ShoppingResultsScreen extends StatelessWidget {
  const ShoppingResultsScreen({
    super.key,
    required this.candidates,
    required this.isComplete,
    this.exactResultCount,
    required this.onCandidate,
    required this.onWishlist,
  });

  final List<ShoppingCandidateData> candidates;
  final bool isComplete;
  final int? exactResultCount;
  final ValueChanged<ShoppingCandidateData> onCandidate;
  final ValueChanged<ShoppingCandidateData> onWishlist;

  @override
  Widget build(BuildContext context) {
    final countCopy = isComplete && exactResultCount != null
        ? 'Našiel som $exactResultCount vhodných kúskov.'
        : 'Zobrazené sú ďalšie overené výsledky.';
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Výsledky Shoppingu'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(countCopy, style: const TextStyle(color: _muted)),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 620 ? 3 : 1;
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: candidates.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: columns == 1 ? 420 : 400,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemBuilder: (context, index) => ShoppingCandidateCard(
                      candidate: candidates[index],
                      rank: index < 3 ? index + 1 : null,
                      onTap: () => onCandidate(candidates[index]),
                      onWishlist: () => onWishlist(candidates[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShoppingCandidateDetailSheet extends StatelessWidget {
  const ShoppingCandidateDetailSheet({
    super.key,
    required this.candidate,
    required this.onWishlist,
    required this.onVisitStore,
  });

  final ShoppingCandidateData candidate;
  final VoidCallback onWishlist;
  final ValueChanged<String> onVisitStore;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                candidate.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (candidate.brand.isNotEmpty)
                Text(candidate.brand, style: const TextStyle(color: _muted)),
              const SizedBox(height: 14),
              ShoppingCandidateCard(candidate: candidate),
              const SizedBox(height: 12),
              Text(
                'Dostupnosť a cena sa zobrazujú z overeného katalógového výsledku.',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              if (candidate.alternativeOffers.isNotEmpty) ...[
                const Text(
                  'Dostupné aj v ďalších obchodoch',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final offer in candidate.alternativeOffers)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(offer.storeName),
                    subtitle: Text(
                      [
                        offer.effectivePrice.label,
                        if (offer.selectedSizes.isNotEmpty)
                          '${offer.selectedSizes.first.label}: ${_availabilityCopy(offer.selectedSizes.first.availability)}',
                        if (offer.couponCode != null) 'kód ${offer.couponCode}',
                      ].join(' · '),
                    ),
                    trailing: offer.url == null
                        ? null
                        : IconButton(
                            tooltip: 'Navštíviť obchod',
                            onPressed: () => onVisitStore(offer.url!),
                            icon: const Icon(Icons.open_in_new),
                          ),
                  ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: candidate.primaryOffer?.url == null
                          ? null
                          : () => onVisitStore(candidate.primaryOffer!.url!),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Navštíviť obchod'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onWishlist,
                      icon: const Icon(Icons.favorite_border),
                      label: const Text('Wishlist'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _availabilityCopy(String value) => switch (value) {
  'AVAILABLE' => 'skladom',
  'UNAVAILABLE' => 'nedostupná',
  _ => 'neoverená',
};

class ShoppingWishlistIntent {
  const ShoppingWishlistIntent({
    required this.variantId,
    required this.selectedSizes,
    required this.preferredSize,
    required this.targetAmountMinor,
    required this.currency,
    required this.priceMonitoringEnabled,
    required this.sizeMonitoringEnabled,
  });
  final String variantId;
  final Set<String> selectedSizes;
  final String? preferredSize;
  final int targetAmountMinor;
  final String currency;
  final bool priceMonitoringEnabled, sizeMonitoringEnabled;
}

class ShoppingWishlistEditor extends StatefulWidget {
  const ShoppingWishlistEditor({
    super.key,
    required this.candidate,
    required this.onDismissed,
    required this.onSave,
    this.initialIntent,
  });

  final ShoppingCandidateData candidate;
  final VoidCallback onDismissed;
  final Future<void> Function(ShoppingWishlistIntent intent) onSave;
  final ShoppingWishlistIntent? initialIntent;

  @override
  State<ShoppingWishlistEditor> createState() => _ShoppingWishlistEditorState();
}

class _ShoppingWishlistEditorState extends State<ShoppingWishlistEditor> {
  final _targetController = TextEditingController();
  final Set<String> _sizes = {};
  String _preferredSize = '';
  bool _priceMonitoring = true;
  bool _sizeMonitoring = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialIntent;
    if (initial != null) {
      _sizes
        ..clear()
        ..addAll(initial.selectedSizes);
      _preferredSize = initial.preferredSize ?? '';
      _targetController.text = (initial.targetAmountMinor / 100)
          .toStringAsFixed(2);
      _priceMonitoring = initial.priceMonitoringEnabled;
      _sizeMonitoring = initial.sizeMonitoringEnabled;
    } else {
      final suggested =
          widget.candidate.primarySelectedSize?.key ??
          ShoppingCandidateData._map(
            widget.candidate.raw['selectedSizeEvidence'],
          )['selectedSizeKey']?.toString();
      if (suggested != null && suggested.isNotEmpty) {
        _sizes.add(suggested);
        _preferredSize = suggested;
      }
    }
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wishlist', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(widget.candidate.title, style: const TextStyle(color: _muted)),
            const SizedBox(height: 16),
            const Text('Sledované veľkosti'),
            Wrap(
              spacing: 8,
              children: ['S', 'M', 'L', 'XL'].map((size) {
                final selected = _sizes.contains(size);
                return FilterChip(
                  label: Text(
                    size == _preferredSize && selected ? '$size ★' : size,
                  ),
                  selected: selected,
                  onSelected: (value) => setState(() {
                    if (value) {
                      _sizes.add(size);
                      _preferredSize = size;
                    } else {
                      _sizes.remove(size);
                      if (_preferredSize == size) {
                        _preferredSize = _sizes.isEmpty ? '' : _sizes.first;
                      }
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetController,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Chcem ju za',
                suffixText: '€',
                helperText: 'Cieľovú cenu si určuješ ty.',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _priceMonitoring,
              onChanged: (value) => setState(() => _priceMonitoring = value),
              title: const Text('Sledovať cenu'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _sizeMonitoring,
              onChanged: (value) => setState(() => _sizeMonitoring = value),
              title: const Text('Sledovať dostupnosť veľkosti'),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: _gold, fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : widget.onDismissed,
                    child: const Text('Nie'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        _saving ||
                            _targetController.text.trim().isEmpty ||
                            _sizes.isEmpty
                        ? null
                        : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.initialIntent == null ? 'Uložiť' : 'Upraviť',
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final normalized = _targetController.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(normalized);
    if (amount == null || amount < 0) {
      setState(() => _error = 'Zadaj platnú cieľovú cenu.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        ShoppingWishlistIntent(
          variantId: widget.candidate.variantId,
          selectedSizes: Set.unmodifiable(_sizes),
          preferredSize: _preferredSize.isEmpty ? null : _preferredSize,
          targetAmountMinor: (amount * 100).round(),
          currency: widget.candidate.currency.isEmpty
              ? 'EUR'
              : widget.candidate.currency,
          priceMonitoringEnabled: _priceMonitoring,
          sizeMonitoringEnabled: _sizeMonitoring,
        ),
      );
      if (mounted) widget.onDismissed();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Wishlist sa nepodarilo uložiť. Skús to znova.';
        });
      }
    }
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.text,
    required this.warning,
  });
  final IconData icon;
  final String text;
  final bool warning;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        Icon(icon, size: 15, color: warning ? _gold : _muted),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: warning ? _gold : _muted, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
