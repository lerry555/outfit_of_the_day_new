// lib/screens/outfit_builder_screen.dart
import '../config/feature_flags.dart';
import 'dart:ui';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';

// ✅ Firebase
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';



// ✅ HTTP na stiahnutie obrázka (trim)
import 'package:http/http.dart' as http;


class OutfitBuilderScreen extends StatefulWidget {
  final String? incomingExternalUrl;

  const OutfitBuilderScreen({super.key, this.incomingExternalUrl});
  

  @override
  State<OutfitBuilderScreen> createState() => _OutfitBuilderScreenState();
}

enum FocusRegion { none, head, torso, legs, feet }
enum SubLayerTier { base, mid, outer }
enum HeadScope { head, neck }

/// ✅ Kam sa uloží vybraný kúsok (vrstvy v rámci buildera)
enum OutfitSlot {
  head,
  neck,
  torsoBase,
  torsoMid,
  torsoOuter,
  legsBase,
  legsMid,
  legsOuter,
  shoes,
}

extension _TierX on SubLayerTier {
  String get titleSk {
    switch (this) {
      case SubLayerTier.base:
        return 'Spodná...';
      case SubLayerTier.mid:
        return 'Stredná...';
      case SubLayerTier.outer:
        return 'Vrchná...';
    }
  }
}

extension _OutfitSlotX on OutfitSlot {
  String get backendKey {
    switch (this) {
      case OutfitSlot.head:
        return 'head';
      case OutfitSlot.neck:
        return 'neck';
      case OutfitSlot.torsoBase:
        return 'torsoBase';
      case OutfitSlot.torsoMid:
        return 'torsoMid';
      case OutfitSlot.torsoOuter:
        return 'torsoOuter';
      case OutfitSlot.legsBase:
        return 'legsBase';
      case OutfitSlot.legsMid:
        return 'legsMid';
      case OutfitSlot.legsOuter:
        return 'legsOuter';
      case OutfitSlot.shoes:
        return 'shoes';
    }
  }
}

class OutfitPick {
  final String label;
  final String mainGroupKey;
  final String categoryKey;
  final String subCategoryKey;

  const OutfitPick({
    required this.label,
    required this.mainGroupKey,
    required this.categoryKey,
    required this.subCategoryKey,
  });
}

class WardrobePickedItem {
  final String id;
  final String title;
  final String? previewImageUrl;
  final String? cutoutImageUrl;

  const WardrobePickedItem({
    required this.id,
    required this.title,
    required this.previewImageUrl,
    required this.cutoutImageUrl,
  });
}

class _OutfitBuilderScreenState extends State<OutfitBuilderScreen> {
  static const String kWardrobePath = 'wardrobe';

  // ✅ Male/Female mannequin
  String _mannequinGender = 'male'; // 'male' | 'female'
  String get _mannequinAsset =>
      _mannequinGender == 'female' ? 'assets/mannequins/female.png' : 'assets/mannequins/male.png';

  ({Alignment align, double widthFactor}) _placementForSlot(OutfitSlot slot) {
    switch (slot) {
      case OutfitSlot.head:
        return (align: const Alignment(0, -0.76), widthFactor: 0.20);
      case OutfitSlot.neck:
        return (align: const Alignment(0, -0.60), widthFactor: 0.26);
      case OutfitSlot.torsoBase:
        return (align: const Alignment(0, -0.26), widthFactor: 0.30);
      case OutfitSlot.torsoMid:
        return (align: const Alignment(0, -0.22), widthFactor: 0.36);
      case OutfitSlot.torsoOuter:
        return (align: const Alignment(0, -0.12), widthFactor: 0.40);
      case OutfitSlot.legsBase:
        return (align: const Alignment(0, 0.34), widthFactor: 0.30);
      case OutfitSlot.legsMid:
        return (align: const Alignment(0, 0.42), widthFactor: 0.46);
      case OutfitSlot.legsOuter:
        return (align: const Alignment(0, 0.38), widthFactor: 0.48);
      case OutfitSlot.shoes:
        return (align: const Alignment(0, 0.90), widthFactor: 0.42);
    }
  }


  // ✅ Try-On (result overlay)
  bool _tryOnBusy = false;
  String? _tryOnStatus;
  String? _tryOnResultUrl;
  String? _tryOnJobId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tryOnJobSub;
  OutfitSlot? _tryOnSlot; // ✅ na ktorý slot sa má try-on overlay zarovnať

  FocusRegion focus = FocusRegion.none;
  SubLayerTier? tier;
  HeadScope headScope = HeadScope.head;

  final TransformationController _tc = TransformationController();
  bool _zoomed = false;

  Alignment _menuAnchor = Alignment.center;

  final Map<OutfitSlot, WardrobePickedItem?> _selectedBySlot = {
    for (final s in OutfitSlot.values) s: null,
  };

  final Map<String, Future<Uint8List?>> _trimFutureCache = {};

  @override
  void dispose() {
    _tryOnJobSub?.cancel();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      for (final s in OutfitSlot.values) {
        _selectedBySlot[s] = null;
      }
      focus = FocusRegion.none;
      tier = null;
      headScope = HeadScope.head;
      _resetZoom();

      _tryOnBusy = false;
      _tryOnStatus = null;
      _tryOnResultUrl = null;
      _tryOnJobId = null;
      _tryOnSlot = null;
    });

    _tryOnJobSub?.cancel();
    _tryOnJobSub = null;
  }

  void _resetZoom() {
    _tc.value = Matrix4.identity();
    _zoomed = false;
  }

  bool _isInsideMannequinHitBox(double xNorm, double yNorm) {
    double minX = 0.16;
    double maxX = 0.84;
    double minY = 0.02;
    double maxY = 0.99;

    if (yNorm >= 0.70) {
      minX = 0.10;
      maxX = 0.90;
      maxY = 0.999;
    }

    return xNorm >= minX && xNorm <= maxX && yNorm >= minY && yNorm <= maxY;
  }

  void _zoomToPoint({
    required double xNorm,
    required double yNorm,
    required double stageW,
    required double stageH,
    required double scale,
  }) {
    final px = xNorm * stageW;
    final py = yNorm * stageH;

    final cx = stageW * 0.5;
    final cy = stageH * 0.5;

    final tx = cx - (px * scale);
    final ty = cy - (py * scale);

    _tc.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);

    _zoomed = true;
  }

  double _scaleFor(FocusRegion r) {
    switch (r) {
      case FocusRegion.head:
        return 1.95;
      case FocusRegion.torso:
        return 1.75;
      case FocusRegion.legs:
        return 1.85;
      case FocusRegion.feet:
        return 2.05;
      case FocusRegion.none:
        return 1.0;
    }
  }

  void _closeMenuAndReset() {
    setState(() {
      focus = FocusRegion.none;
      tier = null;
      headScope = HeadScope.head;
      _resetZoom();
    });
  }

  void _onTapStage(BoxConstraints c, Offset localPos) {
    final w = c.maxWidth;
    final h = c.maxHeight;

    final x = (localPos.dx / w).clamp(0.0, 1.0);
    final y = (localPos.dy / h).clamp(0.0, 1.0);

    if (!_isInsideMannequinHitBox(x, y)) {
      _closeMenuAndReset();
      return;
    }

    _menuAnchor = Alignment((x * 2) - 1, (y * 2) - 1);

    FocusRegion newFocus;
    if (y < 0.26) {
      newFocus = FocusRegion.head;
    } else if (y < 0.52) {
      newFocus = FocusRegion.torso;
    } else if (y < 0.78) {
      newFocus = FocusRegion.legs;
    } else {
      newFocus = FocusRegion.feet;
    }

    setState(() {
      final focusChanged = newFocus != focus;
      focus = newFocus;

      if (focusChanged && (focus == FocusRegion.torso || focus == FocusRegion.legs)) {
        tier = null;
      }

      if (focus != FocusRegion.head) {
        headScope = HeadScope.head;
      }

      _zoomToPoint(
        xNorm: x,
        yNorm: y,
        stageW: w,
        stageH: h,
        scale: _scaleFor(newFocus),
      );
    });
  }

  List<SubLayerTier> _tiersFor(FocusRegion r) {
    if (r == FocusRegion.torso || r == FocusRegion.legs) {
      return const [SubLayerTier.base, SubLayerTier.mid, SubLayerTier.outer];
    }
    return const [];
  }

  String _titleForFocus() {
    switch (focus) {
      case FocusRegion.head:
        return headScope == HeadScope.head ? 'Hlava' : 'Krk';
      case FocusRegion.torso:
        return 'Trup';
      case FocusRegion.legs:
        return 'Nohy';
      case FocusRegion.feet:
        return 'Obuv';
      case FocusRegion.none:
        return 'Vyber časť tela';
    }
  }

  OutfitSlot _slotForCurrentContext() {
    switch (focus) {
      case FocusRegion.head:
        return headScope == HeadScope.head ? OutfitSlot.head : OutfitSlot.neck;
      case FocusRegion.feet:
        return OutfitSlot.shoes;
      case FocusRegion.torso:
        if (tier == SubLayerTier.base) return OutfitSlot.torsoBase;
        if (tier == SubLayerTier.mid) return OutfitSlot.torsoMid;
        return OutfitSlot.torsoOuter;
      case FocusRegion.legs:
        if (tier == SubLayerTier.base) return OutfitSlot.legsBase;
        if (tier == SubLayerTier.mid) return OutfitSlot.legsMid;
        return OutfitSlot.legsOuter;
      case FocusRegion.none:
        return OutfitSlot.torsoMid;
    }
  }

  // ---------------------------------------------------------------------------
  // ✅ ZOZNAMY typov (tvoje)
  // ---------------------------------------------------------------------------
  List<OutfitPick> _picksFor() {
    if (focus == FocusRegion.feet) {
      return const [
        OutfitPick(label: 'Športové tenisky', mainGroupKey: 'obuv', categoryKey: 'tenisky', subCategoryKey: 'tenisky_sportove'),
        OutfitPick(label: 'Fashion tenisky', mainGroupKey: 'obuv', categoryKey: 'tenisky', subCategoryKey: 'tenisky_fashion'),
        OutfitPick(label: 'Bežecké tenisky', mainGroupKey: 'obuv', categoryKey: 'tenisky', subCategoryKey: 'tenisky_bezecke'),
        OutfitPick(label: 'Členkové čižmy', mainGroupKey: 'obuv', categoryKey: 'cizmy', subCategoryKey: 'cizmy_clenkove'),
        OutfitPick(label: 'Vysoké čižmy', mainGroupKey: 'obuv', categoryKey: 'cizmy', subCategoryKey: 'cizmy_vysoke'),
        OutfitPick(label: 'Sandále', mainGroupKey: 'obuv', categoryKey: 'letna_obuv', subCategoryKey: 'sandale'),
        OutfitPick(label: 'Šľapky', mainGroupKey: 'obuv', categoryKey: 'letna_obuv', subCategoryKey: 'slapky'),
        OutfitPick(label: 'Žabky', mainGroupKey: 'obuv', categoryKey: 'letna_obuv', subCategoryKey: 'zabky'),
      ];
    }

    if (focus == FocusRegion.head) {
      if (headScope == HeadScope.head) {
        return const [
          OutfitPick(label: 'Čiapka', mainGroupKey: 'doplnky', categoryKey: 'dopl_hlava', subCategoryKey: 'ciapka'),
          OutfitPick(label: 'Šiltovka', mainGroupKey: 'doplnky', categoryKey: 'dopl_hlava', subCategoryKey: 'siltovka'),
          OutfitPick(label: 'Bucket hat', mainGroupKey: 'doplnky', categoryKey: 'dopl_hlava', subCategoryKey: 'bucket_hat'),
          OutfitPick(label: 'Slnečné okuliare', mainGroupKey: 'doplnky', categoryKey: 'dopl_ostatne', subCategoryKey: 'slnecne_okuliare'),
        ];
      } else {
        return const [
          OutfitPick(label: 'Šál', mainGroupKey: 'doplnky', categoryKey: 'dopl_saly_rukavice', subCategoryKey: 'sal'),
          OutfitPick(label: 'Šatka', mainGroupKey: 'doplnky', categoryKey: 'dopl_saly_rukavice', subCategoryKey: 'satka'),
          OutfitPick(label: 'Rukavice', mainGroupKey: 'doplnky', categoryKey: 'dopl_saly_rukavice', subCategoryKey: 'rukavice'),
        ];
      }
    }

    if ((focus == FocusRegion.torso || focus == FocusRegion.legs) && tier == null) {
      return const [];
    }

    if (focus == FocusRegion.torso) {
      switch (tier!) {
        case SubLayerTier.base:
          return const [
            OutfitPick(label: 'Podprsenka', mainGroupKey: 'oblecenie', categoryKey: 'spodna_bielizen', subCategoryKey: 'podprsenka'),
            OutfitPick(label: 'Športová podprsenka', mainGroupKey: 'oblecenie', categoryKey: 'sport_oblecenie', subCategoryKey: 'sport_podprsenka'),
            OutfitPick(label: 'Body', mainGroupKey: 'oblecenie', categoryKey: 'tricka_topy', subCategoryKey: 'body'),
            OutfitPick(label: 'Tielko', mainGroupKey: 'oblecenie', categoryKey: 'tricka_topy', subCategoryKey: 'tielko'),
          ];
        case SubLayerTier.mid:
          return const [
            OutfitPick(label: 'Tričko', mainGroupKey: 'oblecenie', categoryKey: 'tricka_topy', subCategoryKey: 'tricko'),
            OutfitPick(label: 'Tričko dlhý rukáv', mainGroupKey: 'oblecenie', categoryKey: 'tricka_topy', subCategoryKey: 'tricko_dlhy_rukav'),
            OutfitPick(label: 'Crop top', mainGroupKey: 'oblecenie', categoryKey: 'tricka_topy', subCategoryKey: 'crop_top'),
            OutfitPick(label: 'Polo tričko', mainGroupKey: 'oblecenie', categoryKey: 'tricka_topy', subCategoryKey: 'polo_tricko'),
            OutfitPick(label: 'Košeľa', mainGroupKey: 'oblecenie', categoryKey: 'kosele', subCategoryKey: 'kosela_klasicka'),
            OutfitPick(label: 'Mikina', mainGroupKey: 'oblecenie', categoryKey: 'mikiny', subCategoryKey: 'mikina_klasicka'),
            OutfitPick(label: 'Sveter', mainGroupKey: 'oblecenie', categoryKey: 'svetre', subCategoryKey: 'sveter_klasicky'),
            OutfitPick(label: 'Rolák', mainGroupKey: 'oblecenie', categoryKey: 'svetre', subCategoryKey: 'sveter_rolak'),
          ];
        case SubLayerTier.outer:
          return const [
            OutfitPick(label: 'Prechodná bunda', mainGroupKey: 'oblecenie', categoryKey: 'bundy_kabaty', subCategoryKey: 'bunda_prechodna'),
            OutfitPick(label: 'Zimná bunda', mainGroupKey: 'oblecenie', categoryKey: 'bundy_kabaty', subCategoryKey: 'bunda_zimna'),
            OutfitPick(label: 'Kabát', mainGroupKey: 'oblecenie', categoryKey: 'bundy_kabaty', subCategoryKey: 'kabat'),
            OutfitPick(label: 'Trenchcoat', mainGroupKey: 'oblecenie', categoryKey: 'bundy_kabaty', subCategoryKey: 'trenchcoat'),
            OutfitPick(label: 'Sako / blejzer', mainGroupKey: 'oblecenie', categoryKey: 'bundy_kabaty', subCategoryKey: 'sako'),
            OutfitPick(label: 'Vesta', mainGroupKey: 'oblecenie', categoryKey: 'bundy_kabaty', subCategoryKey: 'vesta'),
          ];
      }
    }

    if (focus == FocusRegion.legs) {
      switch (tier!) {
        case SubLayerTier.base:
          return const [
            OutfitPick(label: 'Nohavičky', mainGroupKey: 'oblecenie', categoryKey: 'spodna_bielizen', subCategoryKey: 'nohavičky'),
            OutfitPick(label: 'Tanga', mainGroupKey: 'oblecenie', categoryKey: 'spodna_bielizen', subCategoryKey: 'tanga'),
            OutfitPick(label: 'Boxerky', mainGroupKey: 'oblecenie', categoryKey: 'spodna_bielizen', subCategoryKey: 'boxerky'),
          ];
        case SubLayerTier.mid:
          return const [
            OutfitPick(label: 'Rifle', mainGroupKey: 'oblecenie', categoryKey: 'nohavice_rifle', subCategoryKey: 'rifle'),
            OutfitPick(label: 'Chino nohavice', mainGroupKey: 'oblecenie', categoryKey: 'nohavice_rifle', subCategoryKey: 'nohavice_chino'),
            OutfitPick(label: 'Teplákové nohavice', mainGroupKey: 'oblecenie', categoryKey: 'nohavice_rifle', subCategoryKey: 'nohavice_teplakove'),
            OutfitPick(label: 'Cargo nohavice', mainGroupKey: 'oblecenie', categoryKey: 'nohavice_rifle', subCategoryKey: 'nohavice_cargo'),
            OutfitPick(label: 'Legíny', mainGroupKey: 'oblecenie', categoryKey: 'sport_oblecenie', subCategoryKey: 'sport_leginy'),
          ];
        case SubLayerTier.outer:
          return const [
            OutfitPick(label: 'Šortky', mainGroupKey: 'oblecenie', categoryKey: 'sortky_sukne', subCategoryKey: 'sortky'),
            OutfitPick(label: 'Mini sukňa', mainGroupKey: 'oblecenie', categoryKey: 'sortky_sukne', subCategoryKey: 'sukna_mini'),
            OutfitPick(label: 'Midi sukňa', mainGroupKey: 'oblecenie', categoryKey: 'sortky_sukne', subCategoryKey: 'sukna_midi'),
            OutfitPick(label: 'Maxi sukňa', mainGroupKey: 'oblecenie', categoryKey: 'sortky_sukne', subCategoryKey: 'sukna_maxi'),
          ];
      }
    }

    return const [];
  }

  // ---------------------------------------------------------------------------
  // ✅ SOURCE PICKER + WARDROBE PICKER
  // ---------------------------------------------------------------------------
  Future<void> _chooseSource(OutfitPick pick) async {
    final incoming = widget.incomingExternalUrl?.trim();
    final hasIncoming = incoming != null && incoming.isNotEmpty;

    final res = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SourcePickerSheet(hasIncomingLink: hasIncoming, incomingLink: incoming),
    );

    if (res == null) return;

    if (res == 'wardrobe') {
      await _openWardrobePicker(pick);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Partner: ${pick.label} (napojíme linky ďalším krokom)')),
    );
  }

  Future<void> _openWardrobePicker(OutfitPick pick) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie si prihlásený.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<WardrobePickedItem>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WardrobePickerSheet(
        uid: user.uid,
        wardrobeSubCollection: kWardrobePath,
        pick: pick,
      ),
    );

    if (selected == null) return;

    final slot = _slotForCurrentContext();
    setState(() {
      _selectedBySlot[slot] = selected;
      // _tryOnSlot = slot;
      _tryOnResultUrl = null;
      _tryOnStatus = null;

    });

// await _startTryOnForPickedItem(uid: user.uid, slot: slot, picked: selected);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pridané do outfitu: ${selected.title}')),
    );
  }


  // ---------------------------------------------------------------------------
  // ✅ TRY-ON (fallback na existujúce requestTryOn)
  // ---------------------------------------------------------------------------
  Future<void> _startTryOnForPickedItem({
    required String uid,
    required OutfitSlot slot,
    required WardrobePickedItem picked,
  }) async {
    final garmentUrl = (picked.cutoutImageUrl ?? picked.previewImageUrl ?? '').trim();
    if (garmentUrl.isEmpty) {
      setState(() {
        _tryOnBusy = false;
        _tryOnStatus = 'error';
      });
      return;
    }

    await _tryOnJobSub?.cancel();
    _tryOnJobSub = null;

    setState(() {
      _tryOnBusy = true;
      _tryOnStatus = 'processing';
      _tryOnResultUrl = null;
      _tryOnJobId = null;
      _tryOnSlot = slot; // ✅ uložíme, kam to patrí
    });


    try {
      // ✅ zatiaľ voláme tvoje existujúce callable: requestTryOn -> {resultUrl}
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('requestTryOn');

      final res = await callable.call({
        'garmentImageUrl': garmentUrl,
        'slot': slot.backendKey,
        'sessionId': 'builder_${DateTime.now().millisecondsSinceEpoch}',
        'baseImageUrl': '',
        'mannequinGender': _mannequinGender,
      });



      final data = res.data;
      String? url;
      if (data is Map) {
        url = (data['resultUrl'] ?? data['url'])?.toString();
      }

      if (url == null || url.trim().isEmpty) {
        throw Exception('Backend nevrátil resultUrl.');
      }

      if (!mounted) return;
      setState(() {
        _tryOnBusy = false;
        _tryOnStatus = 'done';
        _tryOnResultUrl = url!.trim();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tryOnBusy = false;
        _tryOnStatus = 'error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Try-On sa nepodaril: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ✅ TRIM
  // ---------------------------------------------------------------------------
  Future<Uint8List?> _trimmedBytesForUrl(String url) {
    _trimFutureCache[url] ??= _downloadAndTrim(url);
    return _trimFutureCache[url]!;
  }

  Future<Uint8List?> _downloadAndTrim(String url) async {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return null;

      final bytes = resp.bodyBytes;
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      final bd = await img.toByteData(format: ImageByteFormat.rawRgba);
      if (bd == null) return null;

      final w = img.width;
      final h = img.height;
      final data = bd.buffer.asUint8List();

      const int aThr = 8;

      int minX = w, minY = h, maxX = -1, maxY = -1;

      for (int y = 0; y < h; y++) {
        final row = y * w * 4;
        for (int x = 0; x < w; x++) {
          final i = row + x * 4;
          final a = data[i + 3];
          if (a > aThr) {
            if (x < minX) minX = x;
            if (y < minY) minY = y;
            if (x > maxX) maxX = x;
            if (y > maxY) maxY = y;
          }
        }
      }

      if (maxX < 0 || maxY < 0) {
        final png = await img.toByteData(format: ImageByteFormat.png);
        return png?.buffer.asUint8List();
      }

      const pad = 2;
      minX = (minX - pad).clamp(0, w - 1);
      minY = (minY - pad).clamp(0, h - 1);
      maxX = (maxX + pad).clamp(0, w - 1);
      maxY = (maxY + pad).clamp(0, h - 1);

      final cropW = (maxX - minX + 1).clamp(1, w);
      final cropH = (maxY - minY + 1).clamp(1, h);

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..isAntiAlias = true;

      final src = Rect.fromLTWH(minX.toDouble(), minY.toDouble(), cropW.toDouble(), cropH.toDouble());
      final dst = Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble());

      canvas.drawImageRect(img, src, dst, paint);

      final pic = recorder.endRecording();
      final cropped = await pic.toImage(cropW, cropH);
      final png = await cropped.toByteData(format: ImageByteFormat.png);
      return png?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Widget _buildOverlay(OutfitSlot slot) {
    final item = _selectedBySlot[slot];
    if (item == null) return const SizedBox.shrink();

    final url = (item.previewImageUrl ?? '').trim();
    if (url.isEmpty) return const SizedBox.shrink();

    Alignment align;
    double widthFactor;

    switch (slot) {
      case OutfitSlot.head:
        align = const Alignment(0, -0.76);
        widthFactor = 0.20;
        break;
      case OutfitSlot.neck:
        align = const Alignment(0, -0.60);
        widthFactor = 0.26;
        break;
      case OutfitSlot.torsoBase:
        align = const Alignment(0, -0.26);
        widthFactor = 0.30;
        break;
      case OutfitSlot.torsoMid:
        align = const Alignment(0, -0.22);
        widthFactor = 0.36;
        break;
      case OutfitSlot.torsoOuter:
        align = const Alignment(0, -0.12);
        widthFactor = 0.40;
        break;
      case OutfitSlot.legsBase:
        align = const Alignment(0, 0.34);
        widthFactor = 0.30;
        break;
      case OutfitSlot.legsMid:
        align = const Alignment(0, 0.42);
        widthFactor = 0.46;
        break;
      case OutfitSlot.legsOuter:
        align = const Alignment(0, 0.38);
        widthFactor = 0.48;
        break;
      case OutfitSlot.shoes:
        align = const Alignment(0, 0.90);
        widthFactor = 0.42;
        break;
    }

    return Align(
      alignment: align,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: IgnorePointer(
          child: _TrimmedNetworkImage(
            url: url,
            getTrimmedBytes: _trimmedBytesForUrl,
          ),
        ),
      ),
    );
  }

  Widget _buildTryOnOverlay() {
    final url = (_tryOnResultUrl ?? '').trim();
    final slot = _tryOnSlot;
    if (url.isEmpty || slot == null) return const SizedBox.shrink();

    final p = _placementForSlot(slot);

    return Align(
      alignment: p.align,
      child: FractionallySizedBox(
        widthFactor: p.widthFactor,
        child: IgnorePointer(
          child: _TrimmedNetworkImage(
            url: url,
            getTrimmedBytes: _trimmedBytesForUrl,
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFF0D36B);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Outfit Builder'),
        actions: [
          IconButton(
            tooltip: _mannequinGender == 'female' ? 'Female figurína' : 'Male figurína',
            icon: Icon(_mannequinGender == 'female' ? Icons.female : Icons.male),
            onPressed: () {
              setState(() {
                _mannequinGender = _mannequinGender == 'male' ? 'female' : 'male';
                _tryOnResultUrl = null;
                _tryOnStatus = null;
                _tryOnBusy = false;
                _tryOnJobId = null;
              });
              _tryOnJobSub?.cancel();
              _tryOnJobSub = null;
            },
          ),
          IconButton(
            tooltip: 'Vymazať',
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearAll,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final picks = _picksFor();
            final tiers = _tiersFor(focus);

            return Stack(
              children: [
                const Positioned.fill(child: _LuxuryBackground()),

                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (d) => _onTapStage(c, d.localPosition),
                    child: Center(
                      child: InteractiveViewer(
                        transformationController: _tc,
                        panEnabled: true,
                        scaleEnabled: true,
                        minScale: 1.0,
                        maxScale: 3.0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // ✅ Ak máme Try-On výsledok, zobraz len jeho (backend už obsahuje figurínu),
                              //    aby nevznikla "figurína vo figuríne".
                              if ((_tryOnResultUrl ?? '').trim().isNotEmpty)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Image.network(
                                      _tryOnResultUrl!.trim(),
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                    ),
                                  ),
                                )
                              else ...[
                                // ✅ Inak klasika: naša figurína + lokálne overlaye
                                Image.asset(
                                  _mannequinAsset,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (_, __, ___) {
                                    return const Icon(Icons.accessibility_new, color: Colors.white24, size: 220);
                                  },
                                ),

                                _buildOverlay(OutfitSlot.torsoBase),
                                _buildOverlay(OutfitSlot.legsBase),
                                _buildOverlay(OutfitSlot.torsoMid),
                                _buildOverlay(OutfitSlot.legsMid),
                                _buildOverlay(OutfitSlot.torsoOuter),
                                _buildOverlay(OutfitSlot.legsOuter),
                                _buildOverlay(OutfitSlot.shoes),
                                _buildOverlay(OutfitSlot.neck),
                                _buildOverlay(OutfitSlot.head),
                              ],
                            ],

                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (_zoomed)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _TinyGlassButton(
                      icon: Icons.zoom_out_map,
                      label: 'Reset',
                      onTap: () => setState(_resetZoom),
                    ),
                  ),

                if (_tryOnBusy || ((_tryOnStatus ?? '').isNotEmpty))
                  Positioned(
                    left: 12,
                    top: 12,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            border: Border.all(color: Colors.white.withOpacity(0.10)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_tryOnBusy)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                const Icon(Icons.check_circle, size: 16, color: Colors.white70),
                              const SizedBox(width: 8),
                              Text(
                                _tryOnBusy ? 'Try-On…' : 'Try-On: ${_tryOnStatus ?? ''}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                if (focus != FocusRegion.none)
                  Align(
                    alignment: _menuAnchor,
                    child: Transform.translate(
                      offset: const Offset(22, 18),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: _GlassPanel(
                          title: _titleForFocus(),
                          onClose: _closeMenuAndReset,
                          child: _ScrollablePanelBody(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (focus == FocusRegion.head) ...[
                                  Row(
                                    children: [
                                      _ChipToggle(
                                        text: 'Hlava',
                                        selected: headScope == HeadScope.head,
                                        onTap: () => setState(() => headScope = HeadScope.head),
                                      ),
                                      const SizedBox(width: 8),
                                      _ChipToggle(
                                        text: 'Krk',
                                        selected: headScope == HeadScope.neck,
                                        onTap: () => setState(() => headScope = HeadScope.neck),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                ],

                                if (tiers.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      for (int i = 0; i < tiers.length; i++) ...[
                                        Expanded(
                                          child: _ChipToggle(
                                            text: tiers[i].titleSk,
                                            selected: tier == tiers[i],
                                            onTap: () => setState(() => tier = tiers[i]),
                                          ),
                                        ),
                                        if (i != tiers.length - 1) const SizedBox(width: 8),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                ],

                                if (picks.isEmpty)
                                  Text(
                                    (focus == FocusRegion.torso || focus == FocusRegion.legs)
                                        ? 'Vyber vrstvu vyššie'
                                        : 'Vyber typ',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  )
                                else
                                  Column(
                                    children: [
                                      for (final p in picks)
                                        _PickRow(
                                          label: p.label,
                                          onTap: () => _chooseSource(p),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                if (focus == FocusRegion.none)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 18,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            border: Border.all(color: Colors.white.withOpacity(0.10)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(color: accent, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                              'Outfit Builder slúži na vizuálny náhľad outfitu.\n'
                              'Realistická AI figurína je vo vývoji a pribudne v budúcnosti.',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TrimmedNetworkImage extends StatelessWidget {
  final String url;
  final Future<Uint8List?> Function(String url) getTrimmedBytes;

  const _TrimmedNetworkImage({
    required this.url,
    required this.getTrimmedBytes,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: getTrimmedBytes(url),
      builder: (context, snap) {
        final b = snap.data;
        if (b == null) {
          return Image.network(
            url,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        }

        return Image.memory(
          b,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        );
      },
    );
  }
}

class _LuxuryBackground extends StatelessWidget {
  const _LuxuryBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: Colors.black),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF090909), Color(0xFF000000), Color(0xFF000000)],
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 1.25,
                  colors: [
                    Colors.white.withOpacity(0.10),
                    Colors.transparent,
                    Colors.black.withOpacity(0.60),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final Widget child;

  const _GlassPanel({required this.title, required this.onClose, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.60),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollablePanelBody extends StatelessWidget {
  final Widget child;
  const _ScrollablePanelBody({required this.child});

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.62;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: child,
      ),
    );
  }
}

class _ChipToggle extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _ChipToggle({required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFF0D36B);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(selected ? 0.0 : 0.10)),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PickRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyGlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TinyGlassButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withOpacity(0.06),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourcePickerSheet extends StatelessWidget {
  final bool hasIncomingLink;
  final String? incomingLink;

  const _SourcePickerSheet({required this.hasIncomingLink, required this.incomingLink});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFF0D36B);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottomInset),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.78),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Odkiaľ chceš vybrať?',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                _SheetButton(
                  title: 'Môj šatník',
                  subtitle: 'Vyberiem z mojich uložených kúskov',
                  onTap: () => Navigator.pop(context, 'wardrobe'),
                  filled: false,
                ),
                const SizedBox(height: 10),
                _SheetButton(
                  title: 'Partnerské obchody',
                  subtitle: hasIncomingLink ? 'Použijem prijatý link' : 'Zadám link / vyberiem produkt partnera',
                  onTap: () => Navigator.pop(context, 'partner'),
                  filled: true,
                  accent: accent,
                ),
                if (hasIncomingLink && incomingLink != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    incomingLink!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Zrušiť', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool filled;
  final Color? accent;

  const _SheetButton({
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.filled,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? (accent ?? Colors.white) : Colors.white.withOpacity(0.06);
    final fg = filled ? Colors.black : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(filled ? 0.0 : 0.10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: filled ? Colors.black54 : Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: filled ? Colors.black87 : Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ✅ WARDROBE PICKER SHEET (Firestore) + vyhľadávanie
// -----------------------------------------------------------------------------
class _WardrobePickerSheet extends StatefulWidget {
  final String uid;
  final String wardrobeSubCollection;
  final OutfitPick pick;

  const _WardrobePickerSheet({
    required this.uid,
    required this.wardrobeSubCollection,
    required this.pick,
  });

  @override
  State<_WardrobePickerSheet> createState() => _WardrobePickerSheetState();
}

class _WardrobePickerSheetState extends State<_WardrobePickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String? _bestPreviewUrl(Map<String, dynamic> d) {
    final a = (d['productImageUrl'] ?? d['product_image_url']) as String?;
    final b = (d['cleanImageUrl'] ?? d['cutoutImageUrl'] ?? d['cutout_image_url']) as String?;
    final c = (d['imageUrl'] ?? d['image_url']) as String?;
    return (a != null && a.isNotEmpty) ? a : (b != null && b.isNotEmpty) ? b : c;
  }

  String? _cutoutUrl(Map<String, dynamic> d) {
    final cut = (d['cutoutImageUrl'] ?? d['cutout_image_url']) as String?;
    final clean = (d['cleanImageUrl'] ?? d['clean_image_url']) as String?;
    final preview = _bestPreviewUrl(d);
    final v = (cut != null && cut.isNotEmpty) ? cut : (clean != null && clean.isNotEmpty) ? clean : preview;
    return (v != null && v.isNotEmpty) ? v : null;
  }

  bool _matchesType(Map<String, dynamic> d) {
    final main = (d['mainGroup'] ?? d['mainGroupKey'] ?? d['main_group'])?.toString();
    final cat = (d['category'] ?? d['categoryKey'] ?? d['category_key'])?.toString();
    final sub = (d['subCategory'] ?? d['subCategoryKey'] ?? d['sub_category'])?.toString();

    if (main == null && cat == null && sub == null) return true;

    return (main == widget.pick.mainGroupKey) &&
        (cat == widget.pick.categoryKey) &&
        (sub == widget.pick.subCategoryKey);
  }

  bool _matchesSearch(Map<String, dynamic> d) {
    if (_q.isEmpty) return true;
    final name = (d['name'] ?? d['title'] ?? d['nazov'] ?? '').toString().toLowerCase();
    final brand = (d['brand'] ?? d['znacka'] ?? '').toString().toLowerCase();
    final t = '$name $brand';
    return t.contains(_q);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection(widget.wardrobeSubCollection);

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottomInset),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.82),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Môj šatník – ${widget.pick.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Hľadať v šatníku… (názov / značka)',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.06),
                      prefixIcon: const Icon(Icons.search, color: Colors.white54),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFF0D36B)),
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: ref.orderBy('createdAt', descending: true).limit(250).snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return const Padding(
                          padding: EdgeInsets.all(14),
                          child: Text('Chyba pri načítaní šatníka.', style: TextStyle(color: Colors.white70)),
                        );
                      }
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(14),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final docs = snap.data!.docs;
                      final filtered = docs.where((d) {
                        final data = d.data();
                        return _matchesType(data) && _matchesSearch(data);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(14),
                          child: Text(
                            'Nenašiel som nič v šatníku pre tento typ.\nSkús zmeniť vrstvu alebo vyhľadávanie.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final doc = filtered[i];
                          final data = doc.data();

                          final name = (data['name'] ?? data['title'] ?? 'Kúsok bez názvu').toString();
                          final brand = (data['brand'] ?? '').toString();
                          final preview = _bestPreviewUrl(data);
                          final cutout = _cutoutUrl(data);

                          return _WardrobeRow(
                            title: name,
                            subtitle: brand.isEmpty ? null : brand,
                            imageUrl: preview,
                            onTap: () {
                              Navigator.pop(
                                context,
                                WardrobePickedItem(
                                  id: doc.id,
                                  title: name,
                                  previewImageUrl: preview,
                                  cutoutImageUrl: cutout,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WardrobeRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback onTap;

  const _WardrobeRow({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withOpacity(0.05),
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
                ),
                clipBehavior: Clip.antiAlias,
                child: (imageUrl == null || imageUrl!.isEmpty)
                    ? const Icon(Icons.image_outlined, color: Colors.white54)
                    : Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined, color: Colors.white54),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
