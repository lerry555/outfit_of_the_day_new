import 'package:flutter/material.dart';

/// Survives widget disposal — keeps last hero slot image across rebuilds.
class HomeOutfitSlotImageMemory {
  HomeOutfitSlotImageMemory._();

  static final Map<String, String> visibleUrlBySlot = <String, String>{};
  static final Map<String, ImageProvider<Object>> providerBySlot =
      <String, ImageProvider<Object>>{};

  static void remember(
    String slotKey,
    String url,
    ImageProvider<Object> provider,
  ) {
    visibleUrlBySlot[slotKey] = url;
    providerBySlot[slotKey] = provider;
  }

  static String? urlFor(String slotKey) => visibleUrlBySlot[slotKey];

  static ImageProvider<Object>? providerFor(String slotKey) =>
      providerBySlot[slotKey];
}

/// Keeps the last displayed Home hero outfit image mounted until a replacement
/// URL is fully precached — avoids blank tiles on day switch or app resume.
class HomeOutfitFrozenImage extends StatefulWidget {
  const HomeOutfitFrozenImage({
    super.key,
    required this.slotKey,
    this.itemId,
    this.imageUrl,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.high,
    this.alignment = Alignment.center,
  });

  final String slotKey;
  final String? itemId;
  final String? imageUrl;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final Alignment alignment;

  @override
  State<HomeOutfitFrozenImage> createState() => _HomeOutfitFrozenImageState();
}

class _HomeOutfitFrozenImageState extends State<HomeOutfitFrozenImage> {
  String? _visibleUrl;
  ImageProvider<Object>? _visibleProvider;
  int _precacheToken = 0;
  String? _pendingUrl;
  bool _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    final slot = widget.slotKey;
    final rememberedUrl = HomeOutfitSlotImageMemory.urlFor(slot);
    final rememberedProvider = HomeOutfitSlotImageMemory.providerFor(slot);
    if (rememberedProvider != null &&
        rememberedUrl != null &&
        rememberedUrl.isNotEmpty) {
      _visibleUrl = rememberedUrl;
      _visibleProvider = rememberedProvider;
    }
    _queueIncomingUrl(widget.imageUrl, immediate: _visibleProvider == null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_dependenciesReady) {
      _dependenciesReady = true;
      _flushPendingPrecache();
    }
  }

  @override
  void didUpdateWidget(HomeOutfitFrozenImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.imageUrl?.trim();
    if (next == null || next.isEmpty) return;
    if (next == _visibleUrl) return;
    _queueIncomingUrl(next, immediate: false);
  }

  void _rememberSlot() {
    final url = _visibleUrl;
    final provider = _visibleProvider;
    if (url == null || url.isEmpty || provider == null) return;
    HomeOutfitSlotImageMemory.remember(widget.slotKey, url, provider);
  }

  void _queueIncomingUrl(String? raw, {required bool immediate}) {
    final url = raw?.trim();
    if (url == null || url.isEmpty) return;
    if (url == _visibleUrl) return;

    if (immediate || _visibleProvider == null) {
      final provider = NetworkImage(url);
      _visibleUrl = url;
      _visibleProvider = provider;
      _pendingUrl = null;
      _rememberSlot();
      if (mounted && _dependenciesReady) {
        setState(() {});
      }
      return;
    }

    _pendingUrl = url;
    if (_dependenciesReady) {
      _flushPendingPrecache();
    }
  }

  void _flushPendingPrecache() {
    final url = _pendingUrl?.trim();
    if (url == null || url.isEmpty) return;
    if (url == _visibleUrl) {
      _pendingUrl = null;
      return;
    }

    final token = ++_precacheToken;
    final provider = NetworkImage(url);
    precacheImage(provider, context).then((_) {
      if (!mounted || token != _precacheToken) return;
      if (_pendingUrl?.trim() != url) return;
      setState(() {
        _visibleUrl = url;
        _visibleProvider = provider;
        _pendingUrl = null;
      });
      _rememberSlot();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = _visibleProvider ??
        HomeOutfitSlotImageMemory.providerFor(widget.slotKey);
    if (provider == null) {
      return const SizedBox.shrink();
    }
    return Image(
      image: provider,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      alignment: widget.alignment,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        final fallback = HomeOutfitSlotImageMemory.providerFor(widget.slotKey);
        if (fallback != null && fallback != provider) {
          return Image(
            image: fallback,
            fit: widget.fit,
            filterQuality: widget.filterQuality,
            alignment: widget.alignment,
            gaplessPlayback: true,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
