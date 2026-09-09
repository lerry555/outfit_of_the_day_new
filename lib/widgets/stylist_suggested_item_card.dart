import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../utils/stylist_card_image_priority.dart';

class StylistSuggestedItemCard extends StatefulWidget {
  const StylistSuggestedItemCard({super.key, required this.item});
  final Map<String, dynamic> item;

  @override
  State<StylistSuggestedItemCard> createState() => _StylistSuggestedItemCardState();
}

class _StylistSuggestedItemCardState extends State<StylistSuggestedItemCard> {
  late Future<List<String>> _urlsFuture;
  int _index = 0;
  final Set<int> _failed = <int>{};

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant StylistSuggestedItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.item['id'] ?? '').toString() != (widget.item['id'] ?? '').toString() ||
        oldWidget.item['productImageUrl'] != widget.item['productImageUrl'] ||
        oldWidget.item['cleanImageUrl'] != widget.item['cleanImageUrl'] ||
        oldWidget.item['cutoutImageUrl'] != widget.item['cutoutImageUrl']) {
      _reset();
    }
  }

  void _reset() {
    _index = 0;
    _failed.clear();
    _urlsFuture = _resolveFreshUrls();
  }

  Future<List<String>> _resolveFreshUrls() async {
    final candidates = stylistCardImageCandidates(widget.item);
    final urls = <String>[];
    for (final candidate in candidates) {
      var url = candidate.url;
      final path = candidate.storagePath?.trim() ?? '';
      if (path.isNotEmpty) {
        try {
          url = await FirebaseStorage.instance.ref(path).getDownloadURL()
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          continue;
        }
      }
      if ((url.startsWith('http://') || url.startsWith('https://')) && !urls.contains(url)) {
        urls.add(url);
      }
    }
    return List<String>.unmodifiable(urls);
  }

  void _advanceAfterFailure(int failedIndex, int length) {
    if (_failed.contains(failedIndex)) return;
    _failed.add(failedIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _index != failedIndex) return;
      if (failedIndex + 1 < length) setState(() => _index = failedIndex + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    const textPrimary = Color(0xFFF1F0EC);
    const textSecondary = Color(0xFFAAA59B);
    final label = (widget.item['name'] ?? widget.item['label'] ?? widget.item['category'] ?? 'Kúsok').toString();
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 78,
            width: double.infinity,
            child: FutureBuilder<List<String>>(
              future: _urlsFuture,
              builder: (context, snapshot) {
                final urls = snapshot.data ?? const <String>[];
                if (urls.isEmpty || _index >= urls.length) {
                  return const Icon(Icons.checkroom, color: textSecondary, size: 24);
                }
                final currentIndex = _index;
                final url = urls[currentIndex];
                return Image.network(
                  url,
                  key: ValueKey('${widget.item['id'] ?? label}:$url'),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) {
                    _advanceAfterFailure(currentIndex, urls.length);
                    return const Icon(Icons.checkroom, color: textSecondary, size: 24);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
            style: const TextStyle(color: textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2)),
        ],
      ),
    );
  }
}
