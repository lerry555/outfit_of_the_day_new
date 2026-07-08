import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../Services/wardrobe_reanalyze_apply_service.dart';
import '../Services/wardrobe_reanalyze_dry_run_service.dart';

/// Developer-only visual review for wardrobe reanalyze dry-run.
class WardrobeReanalyzeReviewScreen extends StatefulWidget {
  const WardrobeReanalyzeReviewScreen({super.key});

  @override
  State<WardrobeReanalyzeReviewScreen> createState() =>
      _WardrobeReanalyzeReviewScreenState();
}

class _WardrobeReanalyzeReviewScreenState
    extends State<WardrobeReanalyzeReviewScreen> {
  bool _loading = true;
  bool _applying = false;
  String? _error;
  WardrobeReanalyzeRunResult? _result;
  String? _filter;
  int _progressDone = 0;
  int _progressTotal = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (!kDebugMode) {
      setState(() {
        _loading = false;
        _error = 'Available only in debug builds.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _progressDone = 0;
      _progressTotal = 0;
    });

    try {
      final result = await WardrobeReanalyzeDryRunService.runForReview(
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progressDone = done;
            _progressTotal = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _applyMetadata() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1C),
        title: const Text(
          'Zapísať metadáta do šatníka?',
          style: TextStyle(color: Color(0xFFF1F0EC)),
        ),
        content: const Text(
          'Pre každý kúsok znova spustí analýzu fotky a uloží '
          'patterns, logo_prominence a visual_description do Firestore. '
          'Názvy a kategórie sa nemenia.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Zrušiť'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Spustiť'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _applying = true);
    try {
      final summary = await WardrobeReanalyzeApplyService.applyMetadataRefresh(
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progressDone = done;
            _progressTotal = total;
          });
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Hotovo: ${summary.updated} aktualizovaných, '
            '${summary.skipped} bez zmeny, ${summary.failed} chýb',
          ),
        ),
      );
      await _run();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba: $e')),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  List<WardrobeReanalyzeReviewItem> get _visibleItems {
    final all = _result?.items ?? const [];
    switch (_filter) {
      case 'improved':
        return all
            .where((i) =>
                !i.failed &&
                i.status == WardrobeReanalyzeReviewStatus.improved)
            .toList();
      case 'unchanged':
        return all
            .where((i) =>
                !i.failed &&
                i.status == WardrobeReanalyzeReviewStatus.unchanged)
            .toList();
      case 'suspicious':
        return all
            .where((i) =>
                i.failed || i.status == WardrobeReanalyzeReviewStatus.suspicious)
            .toList();
      case 'failed':
        return all.where((i) => i.failed).toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: const Color(0xFFF1F0EC),
        title: const Text(
          'Wardrobe Reanalyze Review',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!_loading && !_applying)
            TextButton.icon(
              onPressed: _applyMetadata,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('Apply metadata'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC8A36A)),
            ),
          if (!_loading && !_applying)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _run,
              tooltip: 'Re-run dry run',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading || _applying) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFC8A36A)),
            const SizedBox(height: 16),
            Text(
              _applying
                  ? 'Zapisujem metadáta… $_progressDone / $_progressTotal'
                  : 'Analyzujem šatník… $_progressDone / $_progressTotal',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _run, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final summary = _result!.summary;
    final items = _visibleItems;

    return Column(
      children: [
        _SummaryBanner(summary: summary),
        _FilterBar(
          summary: summary,
          selected: _filter,
          onSelected: (v) => setState(() => _filter = v),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'No items in this filter.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _ReviewCard(item: items[i]),
                ),
        ),
      ],
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.summary});

  final WardrobeReanalyzeSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WARDROBE_REANALYZE_SUMMARY',
            style: TextStyle(
              color: Color(0xFFC8A36A),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _chip('total', summary.total, Colors.white70),
              _chip('improved', summary.improved, Colors.greenAccent),
              _chip('unchanged', summary.unchanged, Colors.white54),
              _chip('suspicious', summary.suspicious, Colors.orangeAccent),
              _chip('failed', summary.failed, Colors.redAccent),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Dry run only — no Firestore writes',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int value, Color color) {
    return Text(
      '$label=$value',
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.summary,
    required this.selected,
    required this.onSelected,
  });

  final WardrobeReanalyzeSummary summary;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _filterChip('All', null, summary.total),
          _filterChip('Improved', 'improved', summary.improved),
          _filterChip('Unchanged', 'unchanged', summary.unchanged),
          _filterChip('Suspicious', 'suspicious', summary.suspicious + summary.failed),
          _filterChip('Failed', 'failed', summary.failed),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String? value, int count) {
    final sel = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text('$label ($count)'),
        selected: sel,
        onSelected: (_) => onSelected(value),
        selectedColor: const Color(0x44C8A36A),
        checkmarkColor: const Color(0xFFC8A36A),
        labelStyle: TextStyle(
          color: sel ? const Color(0xFFF1F0EC) : Colors.white70,
          fontSize: 12,
        ),
        backgroundColor: const Color(0xFF1B1B1F),
        side: const BorderSide(color: Color(0x33FFFFFF)),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item});

  final WardrobeReanalyzeReviewItem item;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(item);

    return Card(
      color: const Color(0xFF151517),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Image.network(
                    item.imageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Color(0xFF242329),
                      child: Center(
                        child: Icon(Icons.broken_image, color: Colors.white38),
                      ),
                    ),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return const ColoredBox(
                        color: Color(0xFF242329),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  ),
                ),
              )
            else
              const SizedBox(
                height: 120,
                child: ColoredBox(
                  color: Color(0xFF242329),
                  child: Center(
                    child: Text('No image URL', style: TextStyle(color: Colors.white38)),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            _metaRow('itemId', item.itemId),
            _metaRow('documentId', item.documentId),
            if (item.brand.isNotEmpty) _metaRow('brand', item.brand),
            if (item.analyzerConfidence != null)
              _metaRow('confidence', '${item.analyzerConfidence}%'),
            if (item.detectedColors.isNotEmpty)
              _metaRow('AI colors', item.detectedColors.join(', ')),
            const Divider(color: Colors.white12, height: 20),
            _compareBlock('Old', item.old),
            const SizedBox(height: 10),
            _compareBlock('New', item.newFields),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Status: ',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    item.statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (item.suspiciousReasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.suspiciousReasons.join(' · '),
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
              ),
            ],
            if (item.failed && item.error != null) ...[
              const SizedBox(height: 6),
              Text(
                item.error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(WardrobeReanalyzeReviewItem item) {
    if (item.failed) return Colors.redAccent;
    return switch (item.status) {
      WardrobeReanalyzeReviewStatus.improved => Colors.greenAccent,
      WardrobeReanalyzeReviewStatus.unchanged => Colors.white54,
      WardrobeReanalyzeReviewStatus.suspicious => Colors.orangeAccent,
    };
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compareBlock(String title, WardrobeReanalyzeFields fields) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFC8A36A),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        _fieldLine('Name', fields.name),
        _fieldLine('Canonical', fields.canonicalType),
        _fieldLine('Layer', fields.layerRole),
        _fieldLine('categoryKey', fields.categoryKey),
        _fieldLine('subCategoryKey', fields.subCategoryKey),
        _fieldLine(
          'patterns',
          fields.patterns.isEmpty ? '' : fields.patterns.join(', '),
        ),
        _fieldLine('logo', fields.logoProminence),
        if (fields.visualDescription.isNotEmpty)
          _fieldLine('visual', fields.visualDescription),
      ],
    );
  }

  Widget _fieldLine(String label, String value) {
    final display = value.isEmpty ? '—' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label: $display',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}
