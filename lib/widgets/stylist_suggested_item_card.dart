import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../utils/stylist_card_image_priority.dart';

class StylistSuggestedItemCard extends StatefulWidget {
  const StylistSuggestedItemCard({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  State<StylistSuggestedItemCard> createState() =>
      _StylistSuggestedItemCardState();
}

class _ResolvedStylistCardImage {
  const _ResolvedStylistCardImage.memory(this.bytes) : url = null;
  const _ResolvedStylistCardImage.network(this.url) : bytes = null;

  final Uint8List? bytes;
  final String? url;
}

class _StylistSuggestedItemCardState extends State<StylistSuggestedItemCard> {
  static const int _maxStorageImageBytes = 15 * 1024 * 1024;

  late List<StylistCardImageCandidate> _candidates;
  late Future<_ResolvedStylistCardImage?> _imageFuture;
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
    const keys = <String>[
      'id',
      'productImageUrl',
      'productStoragePath',
      'cutoutImageUrl',
      'cleanImageUrl',
      'cleanStoragePath',
      'storagePath',
    ];
    final changed = keys.any((key) => oldWidget.item[key] != widget.item[key]);
    if (changed) _reset();
  }

  void _reset() {
    _index = 0;
    _failed.clear();
    _candidates = stylistCardImageCandidates(widget.item);
    _imageFuture = _resolveCurrentCandidate();
  }

  Future<_ResolvedStylistCardImage?> _resolveCurrentCandidate() async {
    if (_index < 0 || _index >= _candidates.length) return null;
    final candidate = _candidates[_index];
    final path = candidate.storagePath?.trim() ?? '';

    if (path.isNotEmpty) {
      try {
        final bytes = await FirebaseStorage.instance
            .ref(path)
            .getData(_maxStorageImageBytes)
            .timeout(const Duration(seconds: 6));
        if (bytes != null && bytes.isNotEmpty) {
          return _ResolvedStylistCardImage.memory(bytes);
        }
      } catch (_) {
        // A stored/external URL can still work. If it does not, errorBuilder
        // advances product -> cutout -> clean before showing a placeholder.
      }
    }

    final url = candidate.url.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return _ResolvedStylistCardImage.network(url);
    }
    return null;
  }

  void _advanceAfterFailure(int failedIndex) {
    if (_failed.contains(failedIndex)) return;
    _failed.add(failedIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _index != failedIndex) return;
      if (failedIndex + 1 < _candidates.length) {
        setState(() {
          _index = failedIndex + 1;
          _imageFuture = _resolveCurrentCandidate();
        });
      }
    });
  }

  Widget _placeholder(Color color) =>
      Icon(Icons.checkroom, color: color, size: 24);

  @override
  Widget build(BuildContext context) {
    const textPrimary = Color(0xFFF1F0EC);
    const textSecondary = Color(0xFFAAA59B);
    final label =
        (widget.item['name'] ??
                widget.item['label'] ??
                widget.item['category'] ??
                'Kúsok')
            .toString();

    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 78,
            width: double.infinity,
            child: FutureBuilder<_ResolvedStylistCardImage?>(
              future: _imageFuture,
              builder: (context, snapshot) {
                if (_candidates.isEmpty || _index >= _candidates.length) {
                  return _placeholder(textSecondary);
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox.shrink();
                }

                final currentIndex = _index;
                final image = snapshot.data;
                if (image == null) {
                  _advanceAfterFailure(currentIndex);
                  return _placeholder(textSecondary);
                }

                final bytes = image.bytes;
                if (bytes != null) {
                  return Image.memory(
                    bytes,
                    key: ValueKey(
                      '${widget.item['id'] ?? label}:memory:$currentIndex',
                    ),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) {
                      _advanceAfterFailure(currentIndex);
                      return _placeholder(textSecondary);
                    },
                  );
                }

                final url = image.url;
                if (url == null || url.isEmpty) {
                  _advanceAfterFailure(currentIndex);
                  return _placeholder(textSecondary);
                }
                return Image.network(
                  url,
                  key: ValueKey('${widget.item['id'] ?? label}:$url'),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) {
                    _advanceAfterFailure(currentIndex);
                    return _placeholder(textSecondary);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
