// lib/screens/add_clothing_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' show Rect;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // compute
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

import 'package:crop_your_image/crop_your_image.dart';

import '../constants/app_constants.dart';
import '../utils/ai_clothing_parser.dart';
import '../widgets/category_picker.dart';
import 'stylist_chat_screen.dart';

/// ✅ ROTATE helper mimo UI thread (encode/decode je ťažké)
Uint8List _rotateJpgBytes(Map<String, dynamic> args) {
  final Uint8List bytes = args['bytes'] as Uint8List;
  final int angle = args['angle'] as int;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final rotated = img.copyRotate(decoded, angle: angle);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
}

/// ✅ PREP helper mimo UI thread:
/// - decode + resize na rozumnú veľkosť (zrýchli crop UI)
/// - používa sa LEN pre editáciu, nie finálny upload
Uint8List _prepareJpgForEditing(Map<String, dynamic> args) {
  final Uint8List bytes = args['bytes'] as Uint8List;
  final int maxSide = args['maxSide'] as int;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final int w = decoded.width;
  final int h = decoded.height;
  final int longest = w > h ? w : h;

  img.Image out = decoded;

  // ✅ zmenšujeme len keď je fotka fakt veľká (typicky z mobilu)
  if (longest > maxSide) {
    final double scale = maxSide / longest;
    final int nw = (w * scale).round();
    final int nh = (h * scale).round();

    out = img.copyResize(
      decoded,
      width: nw,
      height: nh,
      interpolation: img.Interpolation.average,
    );
  }

  return Uint8List.fromList(
    img.encodeJpg(out, quality: 95),
  );
}
/// ✅ UPLOAD helper mimo UI thread:
/// - zmenší finálnu fotku pred uploadom do Storage
/// - zachová pomer strán
/// - zmenšuje LEN keď je fotka väčšia než limit
/// - vysoká kvalita, aby cutout a AI ostali pekné
Uint8List _prepareJpgForUpload(Map<String, dynamic> args) {
  final Uint8List bytes = args['bytes'] as Uint8List;
  final int maxSide = args['maxSide'] as int;
  final int quality = args['quality'] as int;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final int w = decoded.width;
  final int h = decoded.height;
  final int longest = w > h ? w : h;

  img.Image out = decoded;

  if (longest > maxSide) {
    final double scale = maxSide / longest;
    final int nw = (w * scale).round();
    final int nh = (h * scale).round();

    out = img.copyResize(
      decoded,
      width: nw,
      height: nh,
      interpolation: img.Interpolation.average,
    );
  }

  return Uint8List.fromList(
    img.encodeJpg(out, quality: quality),
  );
}
class AddClothingScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final String? imageUrl;
  final String? itemId;
  final bool isEditing;

  const AddClothingScreen({
    super.key,
    this.initialData,
    this.imageUrl,
    this.itemId,
    this.isEditing = false,
  });

  static const String _luxuryBgAsset = 'assets/backgrounds/luxury_dark.png';

  /// ✅ Bottom sheet picker (kamera prvá) -> potom otvorí Preflight (otáčanie + crop)
  static Future<void> openFromPicker(BuildContext context) async {
    final picker = ImagePicker();

    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (sheetCtx) {
        Widget glassCard({
          required Widget child,
          EdgeInsets? padding,
          double opacity = 0.06,
          BorderRadius? radius,
        }) {
          return ClipRRect(
            borderRadius: radius ?? BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: padding ?? const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: radius ?? BorderRadius.circular(24),
                  color: Colors.white.withOpacity(opacity),
                  border: Border.all(color: Colors.white10),
                ),
                child: child,
              ),
            ),
          );
        }

        Widget actionCard({
          required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
          bool primary = false,
        }) {
          return InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: Colors.white.withOpacity(primary ? 0.10 : 0.06),
                border: Border.all(
                  color: primary
                      ? Colors.white.withOpacity(0.16)
                      : Colors.white10,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white70,
                      size: 15,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          height: MediaQuery.of(sheetCtx).size.height,
          decoration: const BoxDecoration(color: Color(0xFF0C0C0C)),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  AddClothingScreen._luxuryBgAsset,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.80),
                        Colors.black.withOpacity(0.42),
                        Colors.black.withOpacity(0.88),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => Navigator.pop(sheetCtx),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.08),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Pridať nový kúsok",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  "Vyber spôsob pridania oblečenia",
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 90),

                      glassCard(
                        padding: const EdgeInsets.all(16),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outline_rounded,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  "Tipy pre najlepšiu fotku",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            _TipRow(
                              icon: Icons.check_rounded,
                              text: "Celý kúsok maj v zábere",
                            ),
                            _TipRow(
                              icon: Icons.check_rounded,
                              text: "Jednoduché pozadie",
                            ),
                            _TipRow(
                              icon: Icons.check_rounded,
                              text: "Dobré svetlo",
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      actionCard(
                        icon: Icons.camera_alt_rounded,
                        title: "Odfotiť",
                        subtitle: "Použiť kameru",
                        primary: true,
                        onTap: () => Navigator.pop(sheetCtx, 'camera'),
                      ),

                      const SizedBox(height: 14),

                      actionCard(
                        icon: Icons.photo_library_rounded,
                        title: "Vybrať z galérie",
                        subtitle: "Použiť existujúcu fotku oblečenia",
                        onTap: () => Navigator.pop(sheetCtx, 'gallery'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (choice == null) return;

    File? pickedFile;

    if (choice == 'camera') {
      final XFile? x = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (x == null) return;
      pickedFile = File(x.path);
    } else if (choice == 'gallery') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
        dialogTitle: 'Vyber fotku',
      );

      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null) return;

      pickedFile = File(path);
    }

    if (pickedFile == null) return;

    // ignore: use_build_context_synchronously
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoPreflightScreen(localFile: pickedFile!),
      ),
    );
  }

  @override
  State<AddClothingScreen> createState() => _AddClothingScreenState();
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white70,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _pickerCard({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// =======================================================
/// ✅ PRE-FLIGHT (otáčanie + crop v appke)
/// - Rotate = okamžitý (len vizuálne, bez sekania)
/// - Rotácia sa "upečie" do bytes iba pri Orezať alebo Potvrdiť
/// - Crop bez hýbania obrázka (interactive: false)
/// =======================================================
class _PhotoPreflightScreen extends StatefulWidget {
  final File localFile;
  const _PhotoPreflightScreen({required this.localFile});

  @override
  State<_PhotoPreflightScreen> createState() => _PhotoPreflightScreenState();
}

class _PhotoPreflightScreenState extends State<_PhotoPreflightScreen> {
  // ✅ luxury theme
  static const _bgAsset = 'assets/backgrounds/luxury_dark.png';

  bool _saving = false;

  Uint8List? _imageBytes;
  Uint8List? _rawBytes;
  bool _prepped = false;

  int _quarterTurns = 0;

  final CropController _cropController = CropController();
  bool _isCropping = false;

  bool _cropPreparing = false;
  Uint8List? _cropBytesReady;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final b = await widget.localFile.readAsBytes();
    if (!mounted) return;

    setState(() {
      _rawBytes = Uint8List.fromList(b);
      _imageBytes = Uint8List.fromList(b);
      _prepped = false;
    });

    _prepareBaseBytesInBackground();
  }

  Future<void> _prepareBaseBytesInBackground() async {
    if (_rawBytes == null) return;

    try {
      final prepared = await compute(_prepareJpgForEditing, {
        'bytes': _rawBytes!,
        'maxSide': 2048,
      });

      if (!mounted) return;
      setState(() {
        _imageBytes = prepared;
        _prepped = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _prepped = true);
    }
  }

  Future<Uint8List> _bakeRotationIfNeeded(Uint8List inputBytes) async {
    final turns = _quarterTurns % 4;
    if (turns == 0) return inputBytes;

    final angle = 90 * turns;

    final out = await compute(_rotateJpgBytes, {
      'bytes': inputBytes,
      'angle': angle,
    });

    return out;
  }

  Future<void> _continueWithBytes(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final outPath = p.join(
      dir.path,
      'ootd_preflight_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final outFile = File(outPath);
    await outFile.writeAsBytes(bytes, flush: true);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _AddClothingEntryPoint(localFile: outFile),
      ),
    );
  }

  Future<void> _enterCropMode() async {
    if (_saving) return;
    if (_imageBytes == null) return;

    setState(() {
      _isCropping = true;
      _cropPreparing = true;
      _cropBytesReady = null;
    });

    try {
      final baked = await _bakeRotationIfNeeded(_imageBytes!);

      if (!mounted) return;
      setState(() {
        _cropBytesReady = baked;
        _quarterTurns = 0;
        _cropPreparing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cropPreparing = false;
        _isCropping = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nepodarilo sa pripraviť orez. ($e)')),
      );
    }
  }

  Future<void> _exitCropMode() async {
    if (_saving) return;
    setState(() {
      _isCropping = false;
      _cropPreparing = false;
      _cropBytesReady = null;
    });
  }

  Future<void> _confirm() async {
    if (_saving) return;
    if (_imageBytes == null) return;

    if (_isCropping) {
      if (_cropPreparing) return;
      setState(() => _saving = true);
      _cropController.crop();
      return;
    }

    setState(() => _saving = true);
    try {
      final baked = await _bakeRotationIfNeeded(_imageBytes!);
      if (!mounted) return;

      _quarterTurns = 0;
      await _continueWithBytes(baked);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nepodarilo sa pripraviť fotku. ($e)')),
      );
    }
  }

  Widget _glassCard({required Widget child, EdgeInsets? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white10),
            color: Colors.white.withOpacity(0.06),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _pillButton({
    required IconData icon,
    required String text,
    required VoidCallback? onTap,
    bool active = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white10),
              color: active
                  ? Colors.white.withOpacity(0.16)
                  : Colors.white.withOpacity(0.07),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String text,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.check, size: 18, color: Colors.black87),
            const SizedBox(width: 10),
            Text(
              text,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black54),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _imageBytes;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(_bgAsset, fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.72),
                    Colors.black.withOpacity(0.18),
                    Colors.black.withOpacity(0.82),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: _glassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Úprava fotky',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isCropping
                                    ? 'Orež oblečenie čo najpresnejšie'
                                    : 'Otoč alebo orež pred spracovaním',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Text(
                            _isCropping ? 'OREZ' : 'NÁHĽAD',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: _glassCard(
                    padding: const EdgeInsets.all(14),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_awesome_outlined, size: 18, color: Colors.white70),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tip: Nech je kúsok celý v zábere a čo najmenej pozadia. '
                                'Výsledok bude čistejší a AI presnejšia.',
                            style: TextStyle(color: Colors.white70, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: _glassCard(
                      padding: const EdgeInsets.all(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: bytes == null
                                  ? const Center(child: CircularProgressIndicator())
                                  : _isCropping
                                  ? (_cropPreparing || _cropBytesReady == null)
                                  ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      'Pripravujem orez…',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                                  : Crop(
                                controller: _cropController,
                                image: _cropBytesReady!,
                                onCropped: (CropResult result) async {
                                  final Uint8List? croppedBytes =
                                  result is CropSuccess ? result.croppedImage : null;

                                  if (croppedBytes == null) {
                                    if (!mounted) return;
                                    setState(() => _saving = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Orezanie bolo zrušené.'),
                                      ),
                                    );
                                    return;
                                  }

                                  if (!mounted) return;
                                  setState(() {
                                    _imageBytes = croppedBytes;
                                    _isCropping = false;
                                    _cropPreparing = false;
                                    _cropBytesReady = null;
                                    _saving = false;
                                    _quarterTurns = 0;
                                  });

                                  try {
                                    await _continueWithBytes(croppedBytes);
                                  } catch (e) {
                                    if (!mounted) return;
                                    setState(() => _saving = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Nepodarilo sa uložiť orez. ($e)',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                aspectRatio: null,
                                baseColor: Colors.black,
                                maskColor: Colors.black.withOpacity(0.55),
                                radius: 0,
                                interactive: true,
                              )
                                  : Center(
                                child: RotatedBox(
                                  quarterTurns: _quarterTurns,
                                  child: Image.memory(bytes, fit: BoxFit.contain),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: _glassCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _pillButton(
                              icon: Icons.rotate_left,
                              text: 'Vľavo',
                              onTap: (_saving || _isCropping)
                                  ? null
                                  : () => setState(
                                    () => _quarterTurns = (_quarterTurns + 3) % 4,
                              ),
                            ),
                            _pillButton(
                              icon: Icons.rotate_right,
                              text: 'Vpravo',
                              onTap: (_saving || _isCropping)
                                  ? null
                                  : () => setState(
                                    () => _quarterTurns = (_quarterTurns + 1) % 4,
                              ),
                            ),
                            _pillButton(
                              icon: _isCropping ? Icons.close : Icons.crop,
                              text: _isCropping ? 'Zrušiť orez' : 'Orezať',
                              active: _isCropping,
                              onTap: _saving
                                  ? null
                                  : () async {
                                if (_isCropping) {
                                  await _exitCropMode();
                                } else {
                                  await _enterCropMode();
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: _primaryButton(
                            text: _saving ? 'Pripravujem…' : 'Pokračovať',
                            loading: _saving,
                            onTap: _saving ? null : _confirm,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddClothingEntryPoint extends StatelessWidget {
  final File localFile;
  const _AddClothingEntryPoint({required this.localFile});

  @override
  Widget build(BuildContext context) {
    return AddClothingScreenHost(localFile: localFile);
  }
}

class AddClothingScreenHost extends StatefulWidget {
  final File localFile;
  const AddClothingScreenHost({super.key, required this.localFile});

  @override
  State<AddClothingScreenHost> createState() => _AddClothingScreenHostState();
}

class _AddClothingScreenHostState extends State<AddClothingScreenHost> {
  @override
  Widget build(BuildContext context) {
    return AddClothingScreen(
      initialData: {'_localFilePath': widget.localFile.path},
      imageUrl: null,
      isEditing: false,
    );
  }
}

class _AddClothingScreenState extends State<AddClothingScreen> {
  List<String> _sanitizeSeasons(List<String> input) {
    final set = input.toSet();
    const four = {'jar', 'leto', 'jeseň', 'zima'};

    if (set.contains('celoročne')) return ['celoročne'];
    if (set.containsAll(four)) return ['celoročne'];

    return allowedSeasons.where((s) => set.contains(s)).toList();
  }

  String _normalizeForSearch(String input) {
    var s = input.toLowerCase().trim();

    const map = {
      'á': 'a',
      'ä': 'a',
      'č': 'c',
      'ď': 'd',
      'é': 'e',
      'ě': 'e',
      'í': 'i',
      'ĺ': 'l',
      'ľ': 'l',
      'ň': 'n',
      'ó': 'o',
      'ô': 'o',
      'ŕ': 'r',
      'ř': 'r',
      'š': 's',
      'ť': 't',
      'ú': 'u',
      'ů': 'u',
      'ü': 'u',
      'ý': 'y',
      'ž': 'z',
    };

    final buffer = StringBuffer();
    for (final ch in s.split('')) {
      buffer.write(map[ch] ?? ch);
    }
    return buffer.toString();
  }

  String? _findCategoryForSubKeyLocal(String subKey) {
    for (final entry in subCategoryTree.entries) {
      if (entry.value.contains(subKey)) return entry.key;
    }
    return null;
  }


  String? _findMainGroupForCategoryLocal(String? categoryKey) {
    if (categoryKey == null) return null;
    for (final entry in categoryTree.entries) {
      if (entry.value.contains(categoryKey)) return entry.key;
    }
    return null;
  }
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();

  bool _isSystemNameSelected = false;
  String? _selectedSystemNameLabel;
  String? _selectedSystemSubCategoryKey;

  File? _localImageFile;
  String? _uploadedImageUrl;
  String? _uploadedStoragePath;

  String? _selectedMainGroupKey;
  String? _selectedCategoryKey;
  String? _selectedSubCategoryKey;
  String? _selectedLayerRole;

  List<String> _selectedColors = [];
  List<String> _selectedStyles = [];
  List<String> _selectedPatterns = [];
  List<String> _selectedSeasons = [];

  bool _isAiLoading = false;
  bool _aiCompleted = false;
  bool _aiFailed = false;
  String? _aiError;

  final List<String> _progressSteps = const [
    'Analyzujem obrázok',
    'Rozpoznávam typ kúsku',
    'Zaraďujem do kategórie',
    'Kontrolujem farby, vzor, sezónu',
    'Pripravujem formulár',
  ];

  final List<bool> _done = [false, false, false, false, false];
  int _activeStepIndex = 0;

  Timer? _uxTimer;
  final int _uxIntervalMs = 2000;
  final int _maxFakeDoneIndex = 3;

  String? _lastTypeLabel;

  List<String> _brandOptions = [];
  bool _brandsLoaded = false;

  static const List<String> _seedBrands = [
    'Adidas',
    'Nike',
    'Puma',
    'Reebok',
    'New Balance',
    'Asics',
    'Converse',
    'Vans',
    'Fila',
    'Under Armour',
    'The North Face',
    'Columbia',
    'Salomon',
    'HI-TEC',
    'Helly Hansen',
    'Jack Wolfskin',
    'Mammut',
    'Patagonia',
    'Quechua',
    'Decathlon',
    'Carhartt',
    'Levi\'s',
    'Wrangler',
    'Diesel',
    'Tommy Hilfiger',
    'Calvin Klein',
    'Hugo Boss',
    'Ralph Lauren',
    'Lacoste',
    'Guess',
    'Armani',
    'Zara',
    'H&M',
    'Bershka',
    'Pull&Bear',
    'Stradivarius',
    'Mango',
    'Reserved',
    'Sinsay',
    'C&A',
    'Uniqlo',
    'Massimo Dutti',
    'COS',
    'GAP',
    'Abercrombie & Fitch',
    'Superdry',
    'Timberland',
    'Dr. Martens',
    'Clarks',
    'Ecco',
    'Geox',
    'Crocs',
    'Birkenstock',
  ];

  @override
  void initState() {
    super.initState();

    final path = (widget.initialData?['_localFilePath'] ?? '').toString();
    if (!widget.isEditing && path.isNotEmpty) {
      _localImageFile = File(path);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fillWithAi();
      });
    }

    if (widget.isEditing && widget.initialData != null) {
      final d = widget.initialData!;
      _nameController.text = (d['name'] ?? '').toString();
      _brandController.text = (d['brand'] ?? '').toString();

      _selectedMainGroupKey =
      (d['mainGroupKey'] ?? d['mainGroup'] ?? '').toString().isEmpty
          ? null
          : (d['mainGroupKey'] ?? d['mainGroup']).toString();

      final cat = (d['categoryKey'] ?? d['category'] ?? '').toString();
      final sub = (d['subCategoryKey'] ?? d['subCategory'] ?? '').toString();

      _selectedCategoryKey = cat.isEmpty ? null : cat;
      _selectedSubCategoryKey = sub.isEmpty ? null : sub;
      _selectedLayerRole =
      (d['layerRole'] ?? '').toString().isEmpty
          ? null
          : (d['layerRole'] ?? '').toString();

      _selectedColors =
          (d['colors'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _selectedStyles =
          (d['styles'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _selectedPatterns =
          (d['patterns'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (_selectedPatterns.length > 1) _selectedPatterns = [_selectedPatterns.first];

      final loadedSeasons =
          (d['seasons'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _selectedSeasons = _sanitizeSeasons(loadedSeasons);

      _uploadedImageUrl = widget.imageUrl;
      _uploadedStoragePath = (d['storagePath'] ?? '').toString().isEmpty
          ? null
          : (d['storagePath'] ?? '').toString();
      _aiCompleted = true;

      _lastTypeLabel =
      _nameController.text.trim().isEmpty ? null : _nameController.text.trim();
    }

    _loadBrandSuggestions();
    _syncSystemNameValidity();

    _nameController.addListener(() {
      final current = _nameController.text.trim();
      if (_selectedSystemNameLabel != null && current != _selectedSystemNameLabel) {
        if (_isSystemNameSelected) {
          setState(() {
            _isSystemNameSelected = false;
            _selectedSystemNameLabel = null;
            _selectedSystemSubCategoryKey = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _uxTimer?.cancel();
    _nameController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  List<String> _toStringList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString()).toList();

    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return [];
      return [s];
    }

    return [];
  }

  Future<void> _loadBrandSuggestions() async {
    final user = _auth.currentUser;
    final base = <String>{..._seedBrands, ...premiumBrands};

    if (user == null) {
      setState(() {
        _brandOptions = base.toList()..sort();
        _brandsLoaded = true;
      });
      return;
    }

    try {
      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('meta')
          .doc('brand_suggestions');

      final snap = await docRef.get();
      final data = snap.data();
      final dynamic arr = data?['brands'];

      final fromDb = <String>[];
      if (arr is List) {
        for (final x in arr) {
          final s = x.toString().trim();
          if (s.isNotEmpty) fromDb.add(s);
        }
      }

      final all = <String>{...base, ...fromDb};
      final list = all.toList()..sort();

      if (!mounted) return;
      setState(() {
        _brandOptions = list;
        _brandsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _brandOptions = base.toList()..sort();
        _brandsLoaded = true;
      });
    }
  }

  Future<void> _saveBrandSuggestion(String brandRaw) async {
    final user = _auth.currentUser;
    final brand = brandRaw.trim();
    if (brand.isEmpty) return;

    if (!_brandOptions.map((e) => e.toLowerCase()).contains(brand.toLowerCase())) {
      setState(() {
        _brandOptions = [..._brandOptions, brand]..sort();
      });
    }

    if (user == null) return;

    try {
      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('meta')
          .doc('brand_suggestions');

      await docRef.set({
        'brands': FieldValue.arrayUnion([brand]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _resetProgress() {
    for (int i = 0; i < _done.length; i++) {
      _done[i] = false;
    }
    _activeStepIndex = 0;

    _uxTimer?.cancel();
    _uxTimer = Timer.periodic(Duration(milliseconds: _uxIntervalMs), (_) {
      if (!mounted) return;
      if (!_isAiLoading) return;

      setState(() {
        if (_activeStepIndex <= _maxFakeDoneIndex) {
          _done[_activeStepIndex] = true;
          _activeStepIndex =
              (_activeStepIndex + 1).clamp(0, _progressSteps.length - 1);
        }
      });
    });
  }

  void _stopProgressTimers() {
    _uxTimer?.cancel();
    _uxTimer = null;
  }

  void _reachMilestone(int index) {
    if (!mounted) return;
    setState(() {
      _done[index] = true;
      if (_activeStepIndex <= index && index < _progressSteps.length - 1) {
        _activeStepIndex = index + 1;
      }
    });
  }

  Future<String?> _ensureImageUrl() async {
    if (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty) {
      return _uploadedImageUrl;
    }

    final user = _auth.currentUser;
    if (user == null) return null;
    if (_localImageFile == null) return null;

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final storagePath = 'wardrobe/${user.uid}/$fileName';
    final ref = _storage.ref().child(storagePath);

    try {
      final rawBytes = await _localImageFile!.readAsBytes();

      final uploadBytes = await compute<Map<String, dynamic>, Uint8List>(
        _prepareJpgForUpload,
        {
          'bytes': rawBytes,
          'maxSide': 1600,
          'quality': 88,
        },
      );

      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
      );

      final task = await ref
          .putData(uploadBytes, metadata)
          .timeout(const Duration(seconds: 25));

      final url = await task.ref.getDownloadURL().timeout(const Duration(seconds: 15));

      setState(() {
        _uploadedImageUrl = url;
        _uploadedStoragePath = storagePath;
      });

      return url;
    } on TimeoutException {
      throw Exception('Upload trvá príliš dlho (timeout). Skontroluj internet a skús znova.');
    } on FirebaseException catch (e) {
      throw Exception('Upload do Storage zlyhal: ${e.code} – ${e.message ?? ''}');
    } catch (e) {
      throw Exception('Upload do Storage zlyhal: $e');
    }
  }

  String _norm(String s) {
    var out = s.toLowerCase().trim();

    const repl = {
      'á': 'a','ä': 'a','č': 'c','ď': 'd','é': 'e','ě': 'e','í': 'i',
      'ĺ': 'l','ľ': 'l','ň': 'n','ó': 'o','ô': 'o','ŕ': 'r','ř': 'r',
      'š': 's','ť': 't','ú': 'u','ů': 'u','ý': 'y','ž': 'z'
    };

    final b = StringBuffer();

    for (final ch in out.split('')) {
      b.write(repl[ch] ?? ch);
    }

    out = b.toString();
    out = out.replaceAll(RegExp(r'\s+'), ' ');

    return out.trim();
  }

  String? _normalizeColor(String raw) {
    final v = _norm(raw);

    const map = {
      'navy': 'tmavomodrá',
      'dark navy': 'tmavomodrá',
      'dark blue': 'tmavomodrá',
      'midnight blue': 'tmavomodrá',
      'blue': 'modrá',
      'light blue': 'svetlomodrá',
      'black': 'čierna',
      'white': 'biela',
      'grey': 'sivá',
      'gray': 'sivá',
      'beige': 'béžová',
      'brown': 'hnedá',
      'tan': 'hnedá',
      'green': 'zelená',
      'olive': 'olivová',
      'khaki': 'khaki',
      'red': 'červená',
      'burgundy': 'bordová',
      'maroon': 'bordová',
      'yellow': 'žltá',
      'orange': 'oranžová',
      'pink': 'ružová',
      'purple': 'fialová',
    };

    final direct = map[v];
    if (direct != null) return direct;

    if (v.contains('navy')) return 'tmavomodrá';
    if (v.contains('dark') && v.contains('blue')) return 'tmavomodrá';
    if (v.contains('blue')) return 'modrá';
    if (v.contains('black')) return 'čierna';
    if (v.contains('white')) return 'biela';
    if (v.contains('grey') || v.contains('gray')) return 'sivá';

    if (allowedColors.contains(raw)) return raw;
    return null;
  }

  List<String> _normalizeColorsList(List<String> input) {
    final out = <String>[];
    for (final x in input) {
      final mapped = _normalizeColor(x);
      if (mapped != null && allowedColors.contains(mapped)) {
        out.add(mapped);
      }
    }
    final seen = <String>{};
    return out.where((e) => seen.add(e)).toList();
  }

  List<String> _dedupeKeepAllowed(List<String> input, List<String> allowed) {
    final allowedNorm = {for (final s in allowed) _norm(s): s};
    final seen = <String>{};
    final out = <String>[];

    for (final item in input) {
      final key = _norm(item);
      final allowedValue = allowedNorm[key];
      if (allowedValue == null) continue;
      if (seen.add(_norm(allowedValue))) {
        out.add(allowedValue);
      }
    }

    return out;
  }

  List<String> _applyStyleRules({
    required List<String> stylesFromAi,
    required String brand,
    required String subCategoryKey,
    required List<String> patterns,
  }) {
    final b = _norm(brand);
    final p = patterns.map(_norm).toList();

    final hasTextPattern = p.contains(_norm('textová potlač'));
    final hasGraphicPattern = p.contains(_norm('grafická potlač'));

    final isNikeFamily =
        b.contains('nike') ||
            b.contains('jordan') ||
            b.contains('adidas') ||
            b.contains('puma') ||
            b.contains('under armour') ||
            b.contains('reebok');

    List<String> out = [...stylesFromAi];

    if (subCategoryKey == 'sport_tricko' ||
        subCategoryKey == 'sport_mikina' ||
        subCategoryKey == 'sport_leginy' ||
        subCategoryKey == 'sport_sortky' ||
        subCategoryKey == 'sport_suprava' ||
        subCategoryKey == 'sport_podprsenka' ||
        subCategoryKey == 'obuv_treningova' ||
        subCategoryKey == 'obuv_turisticka') {
      out = ['sport'];
    } else if (subCategoryKey == 'bluzka' ||
        subCategoryKey == 'sako' ||
        subCategoryKey == 'nohavice_elegantne' ||
        subCategoryKey == 'lodicky' ||
        subCategoryKey == 'poltopanky') {
      out.add('elegant');
      out.add('smart casual');
    } else if (subCategoryKey == 'kosela_klasicka' ||
        subCategoryKey == 'kosela_oversize' ||
        subCategoryKey == 'kosela_flanelova') {
      out.add('casual');
      out.add('smart casual');
    } else if (subCategoryKey == 'mikina_klasicka' ||
        subCategoryKey == 'mikina_na_zips' ||
        subCategoryKey == 'mikina_s_kapucnou' ||
        subCategoryKey == 'mikina_oversize') {
      out.add('casual');
      if (subCategoryKey == 'mikina_s_kapucnou' ||
          subCategoryKey == 'mikina_oversize') {
        out.add('streetwear');
      }
    } else if (subCategoryKey == 'sveter_klasicky' ||
        subCategoryKey == 'sveter_rolak' ||
        subCategoryKey == 'sveter_kardigan' ||
        subCategoryKey == 'sveter_pleteny') {
      out.add('casual');
      out.add('smart casual');
    } else if (subCategoryKey == 'tricko' ||
        subCategoryKey == 'tricko_dlhy_rukav' ||
        subCategoryKey == 'tielko' ||
        subCategoryKey == 'top_basic' ||
        subCategoryKey == 'crop_top' ||
        subCategoryKey == 'polo_tricko' ||
        subCategoryKey == 'body' ||
        subCategoryKey == 'korzet_top' ||
        subCategoryKey == 'undershirt') {
      out.add('casual');

      if (subCategoryKey == 'crop_top' ||
          subCategoryKey == 'korzet_top') {
        out.add('streetwear');
      }

      if ((subCategoryKey == 'tricko' ||
          subCategoryKey == 'tricko_dlhy_rukav' ||
          subCategoryKey == 'tielko') &&
          isNikeFamily &&
          (hasTextPattern || hasGraphicPattern)) {
        out.removeWhere((s) => _norm(s) == _norm('sport'));
        out.removeWhere((s) => _norm(s) == _norm('športový'));
        out.removeWhere((s) => _norm(s) == _norm('sportový'));
        out.add('casual');
        out.add('streetwear');
      }
    } else if (subCategoryKey == 'rifle' ||
        subCategoryKey == 'rifle_skinny' ||
        subCategoryKey == 'rifle_wide_leg' ||
        subCategoryKey == 'rifle_mom' ||
        subCategoryKey == 'nohavice_klasicke' ||
        subCategoryKey == 'nohavice_chino' ||
        subCategoryKey == 'nohavice_cargo' ||
        subCategoryKey == 'sortky' ||
        subCategoryKey == 'sukna' ||
        subCategoryKey == 'sukna_mini' ||
        subCategoryKey == 'sukna_midi' ||
        subCategoryKey == 'sukna_maxi') {
      out.add('casual');
    } else if (subCategoryKey == 'tenisky_fashion') {
      out.add('casual');
      out.add('streetwear');
    } else if (subCategoryKey == 'tenisky_sportove' ||
        subCategoryKey == 'tenisky_bezecke') {
      out = ['sport'];
    } else if (subCategoryKey == 'kabelka' ||
        subCategoryKey == 'taska_crossbody' ||
        subCategoryKey == 'kabelka_listova' ||
        subCategoryKey == 'hodinky' ||
        subCategoryKey == 'sperky') {
      out.add('casual');
    }

    if (out.isEmpty) {
      out.add('casual');
    }

    return _dedupeKeepAllowed(out, allowedStyles);
  }

  List<String> _applyPatternRules({
    required List<String> patternsFromAi,
    required String brand,
    required String prettyType,
    required String rawType,
    required String subCategoryKey,
  }) {
    final out = <String>[];

    final combined = _norm('$brand $prettyType $rawType');

    final hasTextHint =
        combined.contains('text') ||
            combined.contains('napis') ||
            combined.contains('nápis') ||
            combined.contains('letter') ||
            combined.contains('slogan');

    final hasGraphicHint =
        combined.contains('graphic') ||
            combined.contains('graf') ||
            combined.contains('logo') ||
            combined.contains('print') ||
            combined.contains('potlac') ||
            combined.contains('potlač');

    for (final p in patternsFromAi) {
      final mapped = _normalizePattern(p);
      if (mapped != null) out.add(mapped);
    }

    if (hasTextHint) {
      out.add('textová potlač');
    } else if (hasGraphicHint) {
      out.add('grafická potlač');
    }

    if (out.isEmpty &&
        (subCategoryKey == 'undershirt' ||
            subCategoryKey == 'tielko' ||
            subCategoryKey == 'top_basic' ||
            subCategoryKey == 'leginy' ||
            subCategoryKey == 'sport_leginy' ||
            subCategoryKey == 'nohavice_klasicke' ||
            subCategoryKey == 'rifle' ||
            subCategoryKey == 'tricko' ||
            subCategoryKey == 'tricko_dlhy_rukav')) {
      out.add('jednofarebné');
    }

    final deduped = _dedupeKeepAllowed(out, allowedPatterns);

    if (deduped.isEmpty) {
      return ['jednofarebné'];
    }

    if (deduped.contains('textová potlač')) return ['textová potlač'];
    if (deduped.contains('grafická potlač')) return ['grafická potlač'];
    if (deduped.contains('pruhované')) return ['pruhované'];
    if (deduped.contains('kockované')) return ['kockované'];
    if (deduped.contains('kamufláž')) return ['kamufláž'];

    return [deduped.first];
  }

  String? _normalizeStyle(String raw) {
    final v = _norm(raw);

    const map = {
      'basic': 'casual',
      'minimal': 'casual',
      'minimalist': 'casual',
      'everyday': 'casual',
      'everyday wear': 'casual',
      'casual': 'casual',
      'smart casual': 'smart casual',
      'smart-casual': 'smart casual',
      'business': 'business',
      'formal': 'formal',
      'sport': 'casual',
      'sporty': 'casual',
      'athletic': 'casual',
      'streetwear': 'streetwear',
      'street': 'streetwear',
      'elegant': 'elegantný',
    };

    final allowedMap = {for (final s in allowedStyles) _norm(s): s};

    final directAllowed = allowedMap[v];
    if (directAllowed != null) return directAllowed;

    final mapped = map[v];
    if (mapped != null) {
      final allowed2 = allowedMap[_norm(mapped)];
      if (allowed2 != null) return allowed2;

      if (v.contains('basic')) {
        final allowed2 = allowedMap[_norm('casual')];
        if (allowed2 != null) return allowed2;
      }
    }

    return null;
  }

  List<String> _normalizeStylesList(List<String> input) {
    final out = <String>[];
    for (final x in input) {
      final mapped = _normalizeStyle(x);
      if (mapped != null) out.add(mapped);
    }
    final seen = <String>{};
    return out.where((e) => seen.add(e)).toList();
  }

  String? _normalizePattern(String raw) {
    final v = _norm(raw);

    const map = {
      'plain': 'jednofarebné',
      'solid': 'jednofarebné',
      'no pattern': 'jednofarebné',
      'none': 'jednofarebné',
      'striped': 'pruhované',
      'stripes': 'pruhované',
      'stripe': 'pruhované',
      'plaid': 'kockované',
      'checkered': 'kockované',
      'checked': 'kockované',
      'tartan': 'kockované',
      'camo': 'kamufláž',
      'camouflage': 'kamufláž',
      'graphic': 'grafická potlač',
      'printed': 'grafická potlač',
      'print': 'grafická potlač',
      'logo': 'grafická potlač',
      'graficke': 'grafická potlač',
      'grafické': 'grafická potlač',
      'graficky': 'grafická potlač',
      'grafický': 'grafická potlač',
      'graficka': 'grafická potlač',
      'grafická': 'grafická potlač',
      'text': 'textová potlač',
      'lettering': 'textová potlač',
      'slogan': 'textová potlač',
    };

    final allowedMap = {for (final s in allowedPatterns) _norm(s): s};

    final direct = allowedMap[v];
    if (direct != null) return direct;

    final mapped = map[v];
    if (mapped != null) {
      final allowed = allowedMap[_norm(mapped)];
      if (allowed != null) return allowed;
    }

    if (v.contains('camo') || v.contains('camouflage')) {
      return allowedMap[_norm('kamufláž')];
    }
    if (v.contains('stripe')) {
      return allowedMap[_norm('pruhované')];
    }
    if (v.contains('plaid') || v.contains('check') || v.contains('tartan')) {
      return allowedMap[_norm('kockované')];
    }

    if (v.contains('text') || v.contains('letter') || v.contains('slogan')) {
      return allowedMap[_norm('textová potlač')];
    }
    if (v.contains('print') || v.contains('graphic') || v.contains('logo') || v.contains('graf')) {
      return allowedMap[_norm('grafická potlač')];
    }

    return null;
  }

  List<String> _normalizePatternsList(List<String> input) {
    final out = <String>[];
    for (final x in input) {
      final mapped = _normalizePattern(x);
      if (mapped != null) out.add(mapped);
    }
    final seen = <String>{};
    return out.where((e) => seen.add(e)).toList();
  }

  List<String> _fixStylesAfterAi({
    required List<String> styles,
    required List<String> patterns,
    required String brand,
    required String canonicalType,
    required String rawType,
    required String prettyType,
  }) {
    final out = [...styles];

    bool hasSport = out.any((s) => s.toLowerCase().contains('šport'));
    if (!hasSport) return out;

    final b = brand.trim().toLowerCase();
    final isLogoBrand =
        b.contains('jordan') || b.contains('nike') || b.contains('adidas');

    final p = patterns.map((e) => e.toLowerCase()).toList();
    final hasGraphic =
        p.any((x) => x.contains('graf')) ||
            p.any((x) => x.contains('potlač')) ||
            p.any((x) => x.contains('text'));

    final t = (canonicalType + ' ' + rawType + ' ' + prettyType).toLowerCase();

    final isActiveWearType =
        t.contains('dres') ||
            t.contains('funkčné') ||
            t.contains('running') ||
            canonicalType == 'jersey';

    if (!isActiveWearType &&
        canonicalType == 't_shirt' &&
        (isLogoBrand || hasGraphic)) {
      out.removeWhere((s) => s.toLowerCase().contains('šport'));
      if (!out.contains('casual')) out.add('casual');
      if (!out.contains('streetwear')) out.add('streetwear');
    }

    final seen = <String>{};
    return out.where((e) => seen.add(e)).toList();
  }

  bool _isPluralSubcategory(String subKey, String subLabelRaw) {
    final k = subKey.toLowerCase();
    final l = subLabelRaw.toLowerCase();

    return k.startsWith('nohavice_') ||
        k.startsWith('rifle') ||
        k.startsWith('sortky') ||
        k.startsWith('leginy') ||
        k.startsWith('tenisky_') ||
        k.startsWith('sandale') ||
        k.startsWith('cizmy_') ||
        k == 'gumaky' ||
        k == 'snehule' ||
        k == 'zabky' ||
        k == 'espadrilky' ||
        l.contains('nohavice') ||
        l.contains('rifle') ||
        l.contains('šortky') ||
        l.contains('legíny') ||
        l.contains('tenisky') ||
        l.contains('sandále') ||
        l.contains('čižmy') ||
        l.contains('gumáky') ||
        l.contains('snehule') ||
        l.contains('žabky') ||
        l.contains('espadrilky');
  }

  bool _isFeminineSubcategory(String subKey, String subLabelRaw) {
    final k = subKey.toLowerCase();
    final l = subLabelRaw.toLowerCase();

    return k.startsWith('mikina_') ||
        k.startsWith('bluzka') ||
        k.startsWith('kosela_') ||
        k.startsWith('bunda_') ||
        k == 'kabat' ||
        k == 'vesta' ||
        k == 'prsiplast' ||
        k == 'flisova_bunda' ||
        k.startsWith('sukna') ||
        k.startsWith('saty') ||
        k == 'ciapka' ||
        k == 'siltovka' ||
        k == 'kabelka' ||
        k == 'crossbody' ||
        k == 'totebag' ||
        k == 'listova_kabelka' ||
        l.contains('mikina') ||
        l.contains('blúzka') ||
        l.contains('košeľa') ||
        l.contains('bunda') ||
        l.contains('kabát') ||
        l.contains('vesta') ||
        l.contains('pršiplášť') ||
        l.contains('sukňa') ||
        l.contains('šaty') ||
        l.contains('čiapka') ||
        l.contains('šiltovka') ||
        l.contains('kabelka');
  }

  String _colorToAdjectiveForSubcategory(
      String color,
      String subKey,
      String subLabelRaw,
      ) {
    final c = color.trim();
    if (c.isEmpty) return c;

    if (_isPluralSubcategory(subKey, subLabelRaw)) {
      if (c.endsWith('á')) return '${c.substring(0, c.length - 1)}é';
      if (c.endsWith('a')) return '${c.substring(0, c.length - 1)}e';
      return c;
    }

    if (_isFeminineSubcategory(subKey, subLabelRaw)) {
      if (c.endsWith('é')) return '${c.substring(0, c.length - 1)}á';
      if (c.endsWith('e')) return '${c.substring(0, c.length - 1)}a';
      return c;
    }

    return c;
  }
  String _computeAutoNameWithColor() {
    final subKey = _selectedSubCategoryKey;
    final subLabelRaw = (subCategoryLabels[subKey] ?? '').trim();

    String lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
    String upperFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

    String colorPart = '';
    if (_selectedColors.isNotEmpty) {
      colorPart = _colorToAdjectiveForSubcategory(
        _selectedColors.first,
        subKey ?? '',
        subLabelRaw ?? '',
      ).trim();
    }

    final subLabel = lowerFirst(subLabelRaw);

    final parts = [
      if (colorPart.isNotEmpty) colorPart,
      if (subLabel.isNotEmpty) subLabel,
    ];

    final name = parts.join(' ').trim();
    return upperFirst(name);
  }

  void _refreshAutoName() {
    final auto = _computeAutoNameWithColor();
    if (auto.trim().isEmpty) return;

    final current = _nameController.text.trim();
    final lastAuto = (_lastTypeLabel ?? '').trim();

    final shouldOverwrite =
        current.isEmpty || (lastAuto.isNotEmpty && current == lastAuto) || _isSystemNameSelected;

    if (shouldOverwrite) {
      _nameController.text = auto;
      _lastTypeLabel = auto;
    }
  }

  Future<void> _fillWithAi() async {
    if (_isAiLoading) return;

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Musíš byť prihlásený.')),
      );
      return;
    }

    if (_localImageFile == null && (_uploadedImageUrl == null || _uploadedImageUrl!.isEmpty)) {
      return;
    }

    setState(() {
      _isAiLoading = true;
      _aiCompleted = false;
      _aiFailed = false;
      _aiError = null;
    });

    _resetProgress();

    try {
      final imageUrl = await _ensureImageUrl();
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('Nepodarilo sa získať URL obrázka.');
      }
      _reachMilestone(0);

      const endpoint =
          'https://us-east1-outfitoftheday-4d401.cloudfunctions.net/analyzeClothingImage';

      final resp = await http
          .post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'imageUrl': imageUrl}),
      )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode != 200) {
        throw Exception('AI zlyhalo: ${resp.statusCode} ${resp.body}');
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('AI odpoveď nie je JSON objekt.');
      }

      _reachMilestone(1);

      final m = decoded;
      print('AI FULL RESPONSE: ${jsonEncode(m)}');

      final String prettyType = (m['type_pretty'] ?? m['type'] ?? '').toString().trim();
      final String rawType = (m['type'] ?? '').toString().trim();
      String canonical = (m['canonical_type'] ?? '').toString().trim();
      final String brandFromAi = (m['brand'] ?? '').toString().trim();
      final String typeEvidence = '$rawType $prettyType'.toLowerCase();
      final String canonicalLower = canonical.toLowerCase();

      if (canonicalLower == 'jacket') {
        final bool saysMikina =
            typeEvidence.contains('mikina') ||
                typeEvidence.contains('hoodie') ||
                typeEvidence.contains('sweatshirt');

        final bool saysHood =
            typeEvidence.contains('kapuc') ||
                typeEvidence.contains('hood');

        if (saysMikina && saysHood) {
          print(
            'AI TYPE GUARD => overriding canonical "jacket" to "hoodie" '
                'because raw="$rawType", pretty="$prettyType"',
          );
          canonical = 'hoodie';
        } else if (saysMikina) {
          print(
            'AI TYPE GUARD => overriding canonical "jacket" to "sweatshirt" '
                'because raw="$rawType", pretty="$prettyType"',
          );
          canonical = 'sweatshirt';
        }
      }
      final colorsFromAi = _toStringList(m['colors'] ?? m['color']);
      final stylesFromAi = _toStringList(m['style'] ?? m['styles']);
      final patternsFromAi = _toStringList(m['patterns'] ?? m['pattern']);
      final seasonsFromAi = _toStringList(m['season'] ?? m['seasons']);
      final normStyles = stylesFromAi.map((e) => _norm(e)).toList();
      final normPretty = _norm(prettyType);
      final normRawType = _norm(rawType);
      final normCanonical = _norm(canonical);
      final normSeasons = seasonsFromAi.map((e) => _norm(e)).toList();

      String? nextMain;
      String? nextCat;
      String? nextSub;
      String? nextLayerRole;

      if (canonical.isNotEmpty && canonical != 'sneakers' && canonical != 'sneaker') {
        final mapped = AiClothingParser.fromCanonicalType(canonical);
        if (mapped != null) {
          nextMain = mapped.mainGroupKey;
          nextCat = mapped.categoryKey;
          nextSub = mapped.subCategoryKey;
          nextLayerRole = mapped.layerRole;
        }
      }
      if (canonical.isNotEmpty && canonical != 'sneakers' && canonical != 'sneaker') {
        final mapped = AiClothingParser.fromCanonicalType(canonical);
        if (mapped != null) {
          nextMain = mapped.mainGroupKey;
          nextCat = mapped.categoryKey;
          nextSub = mapped.subCategoryKey;
        }
      }

      if (nextMain == null || nextCat == null || nextSub == null) {
        final mapped = AiClothingParser.mapType(
          AiParserInput(
            rawType: rawType,
            aiName: prettyType,
            userName: _nameController.text.trim(),
            seasons: seasonsFromAi,
            brand: brandFromAi,
          ),
        );

        if (mapped != null) {
          nextMain = mapped.mainGroupKey;
          nextCat = mapped.categoryKey;
          nextSub = mapped.subCategoryKey;
          nextLayerRole = mapped.layerRole;

          print(
            'AI TYPE FALLBACK OK => canonical="$canonical", raw="$rawType", pretty="$prettyType" => '
                'main="$nextMain", cat="$nextCat", sub="$nextSub", layer="$nextLayerRole"',
          );
        } else {
          print(
            'AI TYPE MAPPING FAILED => canonical="$canonical", raw="$rawType", pretty="$prettyType"',
          );
        }
      } else {
        print(
          'AI TYPE CANONICAL OK => canonical="$canonical" => '
              'main="$nextMain", cat="$nextCat", sub="$nextSub", layer="$nextLayerRole"',
        );
      }
      final bool jacketLooksWinter =
          nextSub == 'bunda_prechodna' &&
              (normCanonical == 'jacket' || normRawType.contains('bunda')) &&
              (
                  normStyles.contains('outdoor') ||
                      normStyles.contains('sportovy') ||
                      normStyles.contains('sportový') ||
                      normPretty.contains('outdoor') ||
                      normPretty.contains('zimna') ||
                      normPretty.contains('zimná') ||
                      normRawType.contains('zimna') ||
                      normRawType.contains('zimná') ||
                      normSeasons.contains('zima')
              );

      if (jacketLooksWinter) {
        nextSub = 'bunda_zimna';
        nextCat = _findCategoryForSubKeyLocal('bunda_zimna');
        nextMain = _findMainGroupForCategoryLocal(nextCat);
        nextLayerRole = subCategoryLayerRoles['bunda_zimna'] ?? 'outer_layer';

        print(
          'AI JACKET WINTER GUARD => overriding subcategory to "bunda_zimna" '
              'because canonical="$canonical", raw="$rawType", pretty="$prettyType", '
              'styles="$stylesFromAi", seasons="$seasonsFromAi"',
        );
      }
      _reachMilestone(2);
      print('CHECKPOINT 1 => after _reachMilestone(2)');
      final filteredColors = _normalizeColorsList(colorsFromAi);
      final normalizedStylesFromAi = _normalizeStylesList(stylesFromAi);
      final resolvedSubKeyForRules = nextSub ?? '';

      final fixedPatterns = _applyPatternRules(
        patternsFromAi: patternsFromAi,
        brand: brandFromAi,
        prettyType: prettyType,
        rawType: rawType,
        subCategoryKey: resolvedSubKeyForRules,
      );

      final fixedStyles = _applyStyleRules(
        stylesFromAi: normalizedStylesFromAi,
        brand: brandFromAi,
        subCategoryKey: resolvedSubKeyForRules,
        patterns: fixedPatterns,
      );
      print('CHECKPOINT 2 => styles/patterns done');
      print('CHECKPOINT 2A => nextSub=$nextSub');
      print('CHECKPOINT 2B => fixedPatterns=$fixedPatterns');
      print('CHECKPOINT 2C => fixedStyles=$fixedStyles');
      final filteredSeasonsRaw = seasonsFromAi
          .map((e) => e.toString().trim())
          .where((s) => allowedSeasons.contains(s))
          .toList();
      print('CHECKPOINT S1 => filteredSeasonsRaw=$filteredSeasonsRaw');

      List<String> filteredSeasons = _sanitizeSeasons(filteredSeasonsRaw);
      print('CHECKPOINT S2 => filteredSeasons after first sanitize=$filteredSeasons');

      final typeForSeason = nextSub ?? '';
      print('CHECKPOINT S3 => typeForSeason=$typeForSeason');

      if (typeForSeason == 'bunda_zimna') {
        print('CHECKPOINT DIRECT WINTER => forcing winter seasons');
        filteredSeasons = ['jeseň', 'zima'];
        print('CHECKPOINT DX => after direct winter assign, filteredSeasons=$filteredSeasons');
      } else {
        print('CHECKPOINT B1 => entering season branch chain');

        if (typeForSeason == 'tielko') {
          filteredSeasons = ['jar', 'leto'];
        } else if (typeForSeason == 'undershirt') {
          filteredSeasons = ['celoročne'];
        } else if (typeForSeason == 'tenisky_fashion' ||
            typeForSeason == 'tenisky_sportove' ||
            typeForSeason == 'tenisky_bezecke' ||
            typeForSeason == 'obuv_treningova') {
          filteredSeasons = ['jar', 'leto', 'jeseň'];
        } else if (typeForSeason == 'bunda_prechodna' ||
            typeForSeason == 'bunda_riflova' ||
            typeForSeason == 'bunda_kozena' ||
            typeForSeason == 'bunda_bomber' ||
            typeForSeason == 'trenchcoat' ||
            typeForSeason == 'sako' ||
            typeForSeason == 'vesta' ||
            typeForSeason == 'flisova_bunda' ||
            typeForSeason == 'softshell_bunda') {
        } else if (typeForSeason == 'sveter_klasicky' ||
            typeForSeason == 'sveter_rolak' ||
            typeForSeason == 'sveter_kardigan' ||
            typeForSeason == 'sveter_pleteny') {

          print('CHECKPOINT SWEATER BRANCH');

          if (filteredSeasons.isEmpty || filteredSeasons.contains('celoročne')) {
            filteredSeasons = ['jeseň', 'zima'];
          }
          if (filteredSeasons.isEmpty || filteredSeasons.contains('celoročne')) {
            filteredSeasons = ['jar', 'jeseň'];
          }
        } else if (typeForSeason == 'crop_top' ||
            typeForSeason == 'sortky' ||
            typeForSeason == 'sortky_sportove' ||
            typeForSeason == 'sport_sortky' ||
            typeForSeason == 'sandale' ||
            typeForSeason == 'sandale_opatok' ||
            typeForSeason == 'slapky' ||
            typeForSeason == 'zabky' ||
            typeForSeason == 'espadrilky') {
          filteredSeasons = ['jar', 'leto'];
        }
      }

      print('CHECKPOINT X => tesne pred final sanitize seasons, filteredSeasons=$filteredSeasons');
      filteredSeasons = _sanitizeSeasons(filteredSeasons);
      print('CHECKPOINT 3 => seasons done: $filteredSeasons');

      if (canonical == 'tank_top') {
        filteredSeasons = ['jar', 'leto'];
      } else if (canonical == 'undershirt') {
        filteredSeasons = ['celoročne'];
      } else if (canonical == 't_shirt') {
        filteredSeasons = ['celoročne'];
      } else if (canonical == 'longsleeve' || canonical == 'long_sleeve') {
        filteredSeasons = ['celoročne'];
      }

      print('CHECKPOINT 4 => about to enter setState');
      if (!mounted) return;

      setState(() {
        if (_brandController.text.trim().isEmpty && brandFromAi.isNotEmpty) {
          _brandController.text = brandFromAi;
        }

        if (nextMain != null) _selectedMainGroupKey = nextMain;
        if (nextCat != null) _selectedCategoryKey = nextCat;
        if (nextSub != null) _selectedSubCategoryKey = nextSub;
        if (nextLayerRole != null) _selectedLayerRole = nextLayerRole;

        if (filteredColors.isNotEmpty) _selectedColors = filteredColors;
        if (fixedStyles.isNotEmpty) _selectedStyles = fixedStyles;

        if (fixedPatterns.isNotEmpty) {
          _selectedPatterns = [fixedPatterns.first];
        } else {
          _selectedPatterns = [];
        }

        if (filteredSeasons.isNotEmpty) {
          _selectedSeasons = filteredSeasons;
        }

        _isSystemNameSelected = false;
        _selectedSystemNameLabel = null;
        _selectedSystemSubCategoryKey = null;

        _refreshAutoName();

        _aiCompleted = true;
        _aiFailed = false;
        _isAiLoading = false;
        print('CHECKPOINT 5 => inside setState, loading should end now');
      });

      print('CHECKPOINT 6 => setState finished');

      if (_brandController.text.trim().isNotEmpty) {
        await _saveBrandSuggestion(_brandController.text.trim());
      }

      _reachMilestone(3);
      _reachMilestone(4);
      await Future.delayed(const Duration(milliseconds: 450));

      if (!mounted) return;
      _stopProgressTimers();
    }on TimeoutException {
      _stopProgressTimers();
      if (!mounted) return;
      setState(() {
        _aiFailed = true;
        _aiCompleted = false;
        _isAiLoading = false;
        _aiError = 'Sieťový timeout. Skontroluj internet a skús znova.';
      });
    } catch (e) {
      _stopProgressTimers();
      if (!mounted) return;
      setState(() {
        _aiFailed = true;
        _aiCompleted = false;
        _isAiLoading = false;
        _aiError = e.toString();
      });
    }
  }

  Future<void> _save() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final imageUrl = await _ensureImageUrl();
      if (imageUrl == null || imageUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chýba obrázok.')),
        );
        return;
      }

      if (_selectedMainGroupKey == null ||
          _selectedCategoryKey == null ||
          _selectedSubCategoryKey == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI nedokončilo kategóriu/typ. Skús znova alebo oprav ručne.')),
        );
        return;
      }

      final typed = _nameController.text.trim();
      final lastAuto = (_lastTypeLabel ?? '').trim();
      final shouldAuto =
          typed.isEmpty || (lastAuto.isNotEmpty && typed == lastAuto) || _isSystemNameSelected;

      final finalName = shouldAuto ? _computeAutoNameWithColor() : typed;

      if (finalName.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI nevie vytvoriť názov – chýba farba alebo typ.')),
        );
        return;
      }

      final brand = _brandController.text.trim();
      await _saveBrandSuggestion(brand);

      final safeSeasons = _sanitizeSeasons(_selectedSeasons);

      final data = <String, dynamic>{
        'name': finalName.trim(),
        'brand': brand,
        'mainGroup': _selectedMainGroupKey,
        'category': _selectedCategoryKey,
        'subCategory': _selectedSubCategoryKey,
        'mainGroupKey': _selectedMainGroupKey,
        'categoryKey': _selectedCategoryKey,
        'subCategoryKey': _selectedSubCategoryKey,
        'subCategory': _selectedSubCategoryKey,
        'mainGroupKey': _selectedMainGroupKey,
        'categoryKey': _selectedCategoryKey,
        'subCategoryKey': _selectedSubCategoryKey,
        'layerRole': _selectedLayerRole ??
            (_selectedSubCategoryKey == null
                ? null
                : subCategoryLayerRoles[_selectedSubCategoryKey!]),
        'colors': _selectedColors,
        'styles': _selectedStyles,
        'patterns': _selectedPatterns,
        'seasons': safeSeasons.isEmpty ? ['celoročne'] : safeSeasons,
        'imageUrl': imageUrl,
        'originalImageUrl': imageUrl,
        'cutoutImageUrl': null,
        'productImageUrl': null,
        'imageVersion': 1,
        if (_uploadedStoragePath != null) 'storagePath': _uploadedStoragePath,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!widget.isEditing) 'createdAt': FieldValue.serverTimestamp(),
      };

      if (!widget.isEditing) {
        data['processing'] = {
          'cutout': 'queued',
          'product': 'queued',
        };
      }

      final ref = _firestore.collection('users').doc(user.uid).collection('wardrobe');

      if (widget.isEditing && widget.itemId != null) {
        await ref.doc(widget.itemId).set(data, SetOptions(merge: true));
      } else {
        final newDoc = ref.doc();
        await newDoc.set(data, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uloženie zlyhalo: $e')),
      );
    }
  }

  Widget _buildProcessingImagePreview() {
    final Widget imgWidget;

    if (_localImageFile != null) {
      imgWidget = Image.file(_localImageFile!, fit: BoxFit.contain);
    } else if (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty) {
      imgWidget = Image.network(_uploadedImageUrl!, fit: BoxFit.contain);
    } else {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 190,
              width: double.infinity,
              color: Colors.white.withOpacity(0.04),
              alignment: Alignment.center,
              child: imgWidget,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressChecklist() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI spracovanie',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Analyzujeme fotku a pripravujeme formulár.',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              ...List.generate(_progressSteps.length, (i) {
                final done = _done[i];
                final isActive = !done && i == _activeStepIndex;

                Widget leading;
                if (done) {
                  leading = const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF58D26B),
                    size: 21,
                  );
                } else if (isActive) {
                  leading = const SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                } else {
                  leading = Icon(
                    Icons.radio_button_unchecked_rounded,
                    color: Colors.white.withOpacity(0.28),
                    size: 20,
                  );
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: isActive
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.03),
                    border: Border.all(
                      color: isActive
                          ? Colors.white.withOpacity(0.14)
                          : Colors.white.withOpacity(0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      leading,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _progressSteps[i],
                          style: TextStyle(
                            color: done
                                ? Colors.white
                                : isActive
                                ? Colors.white70
                                : Colors.white54,
                            fontWeight: done || isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiError() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.red.withOpacity(0.08),
            border: Border.all(color: Colors.red.withOpacity(0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.redAccent,
                size: 22,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'AI analýza zlyhala. Skús použiť inú fotku alebo pokračuj manuálne.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> get _systemNameOptions {
    final set = <String>{};
    for (final v in subCategoryLabels.values) {
      final s = v.toString().trim();
      if (s.isNotEmpty) set.add(s);
    }
    final list = set.toList()..sort();
    return list;
  }

  String? _findSubCategoryKeyForLabel(String label) {
    final target = label.trim();
    for (final entry in subCategoryLabels.entries) {
      if (entry.value == target) return entry.key;
    }
    return null;
  }

  void _syncSystemNameValidity() {
    final current = _nameController.text.trim();
    if (current.isEmpty) {
      _isSystemNameSelected = false;
      _selectedSystemNameLabel = null;
      _selectedSystemSubCategoryKey = null;
      return;
    }

    final subKey = _findSubCategoryKeyForLabel(current);
    if (subKey != null) {
      _isSystemNameSelected = true;
      _selectedSystemNameLabel = current;
      _selectedSystemSubCategoryKey = subKey;
    } else {
      _isSystemNameSelected = false;
      _selectedSystemNameLabel = null;
      _selectedSystemSubCategoryKey = null;
    }
  }

  Widget _buildNameFreeField() {
    return TextField(
      controller: _nameController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Názov',
        helperText: 'Aplikácia si názov skladá automaticky (farba + typ).',
        helperStyle: const TextStyle(
          color: Colors.white38,
          fontSize: 11.5,
        ),
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.22),
            width: 1.2,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      textInputAction: TextInputAction.next,
      onChanged: (_) {
        _syncSystemNameValidity();
      },
    );
  }

  Widget _brandAutoComplete() {
    final options = _brandOptions;

    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _brandController.text),
      optionsBuilder: (TextEditingValue textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) return options.take(25);
        return options.where((b) => b.toLowerCase().contains(q)).take(50);
      },
      onSelected: (String selection) {
        _brandController.text = selection;
        _saveBrandSuggestion(selection);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        controller.text = _brandController.text;
        controller.selection =
            TextSelection.fromPosition(TextPosition(offset: controller.text.length));

        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Značka',
            labelStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Colors.white.withOpacity(0.22),
                width: 1.2,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            suffixIcon: _brandsLoaded
                ? const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70)
                : const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          onChanged: (v) => _brandController.text = v,
          onEditingComplete: () {
            final txt = controller.text.trim();
            _brandController.text = txt;
            _saveBrandSuggestion(txt);
            onFieldSubmitted();
          },
        );
      },
    );
  }

  Widget _buildMultiSelectField({
    required String label,
    required List<String> options,
    required List<String> selected,
    required ValueChanged<List<String>> onChanged,
  }) {
    final text = selected.isEmpty
        ? 'Vyber...'
        : () {
      const maxVisible = 3;
      if (selected.length <= maxVisible) return selected.join(', ');
      final visible = selected.take(maxVisible).join(', ');
      final rest = selected.length - maxVisible;
      return '$visible +$rest';
    }();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final result = await _openMultiSelectBottomSheet(
          title: label,
          options: options,
          initialSelected: selected,
          enforceSeasonRules: (label == 'Sezóny'),
        );
        if (result != null) onChanged(result);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Colors.white.withOpacity(0.22),
              width: 1.2,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected.isEmpty ? Colors.white54 : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }

  Future<List<String>?> _openMultiSelectBottomSheet({
    required String title,
    required List<String> options,
    required List<String> initialSelected,
    bool enforceSeasonRules = false,
  }) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final tempSelected = <String>{...initialSelected};
        String query = '';

        List<String> filtered() {
          final q = query.trim().toLowerCase();
          if (q.isEmpty) return options;
          return options.where((o) => o.toLowerCase().contains(q)).toList();
        }

        final height = MediaQuery.of(ctx).size.height * 0.75;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void toggle(String value, bool v) {
              setSheetState(() {
                if (!enforceSeasonRules) {
                  if (v) {
                    tempSelected.add(value);
                  } else {
                    tempSelected.remove(value);
                  }
                  return;
                }

                const four = {'jar', 'leto', 'jeseň', 'zima'};

                if (value == 'celoročne') {
                  if (v) {
                    tempSelected
                      ..clear()
                      ..add('celoročne');
                  } else {
                    tempSelected.remove('celoročne');
                  }
                  return;
                }

                if (tempSelected.contains('celoročne')) {
                  tempSelected.remove('celoročne');
                }

                if (v) {
                  tempSelected.add(value);
                } else {
                  tempSelected.remove(value);
                }

                if (tempSelected.containsAll(four)) {
                  tempSelected
                    ..clear()
                    ..add('celoročne');
                }
              });
            }

            final items = filtered();

            return SafeArea(
              child: SizedBox(
                height: height,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 12 + MediaQuery.of(ctx).viewInsets.bottom,
                    top: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, color: Colors.white70),
                          hintText: 'Hľadať...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                          ),
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (ctx, i) {
                            final o = items[i];
                            final checked = tempSelected.contains(o);

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                o,
                                style: const TextStyle(color: Colors.white),
                              ),
                              trailing: checked
                                  ? const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF58D26B),
                              )
                                  : const SizedBox(width: 24, height: 24),
                              onTap: () => toggle(o, !checked),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            child: const Text(
                              'Zrušiť',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setSheetState(() => tempSelected.clear()),
                            child: const Text(
                              'Vymazať',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(tempSelected.toList()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Hotovo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) return null;
    final ordered = options.where((o) => result.contains(o)).toList();
    if (enforceSeasonRules) return _sanitizeSeasons(ordered);
    return ordered;
  }

  Widget _buildSingleSelectField({
    required String label,
    required List<String> options,
    required String? selected,
    required ValueChanged<String?> onChanged,
  }) {
    final text = (selected == null || selected.isEmpty) ? 'Vyber...' : selected;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final result = await _openSingleSelectBottomSheet(
          title: label,
          options: options,
          selected: selected,
        );
        if (result != null) onChanged(result);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: Colors.white.withOpacity(0.22),
              width: 1.2,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: (selected == null || selected.isEmpty)
                      ? Colors.white54
                      : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _openSingleSelectBottomSheet({
    required String title,
    required List<String> options,
    required String? selected,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        String query = '';

        List<String> filtered() {
          final q = query.trim().toLowerCase();
          if (q.isEmpty) return options;
          return options.where((o) => o.toLowerCase().contains(q)).toList();
        }

        final height = MediaQuery.of(ctx).size.height * 0.75;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final items = filtered();

            return SafeArea(
              child: SizedBox(
                height: height,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 12 + MediaQuery.of(ctx).viewInsets.bottom,
                    top: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vzor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, color: Colors.white70),
                          hintText: 'Hľadať...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                          ),
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (ctx, i) {
                            final o = items[i];
                            final checked = (selected == o);

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                o,
                                style: const TextStyle(color: Colors.white),
                              ),
                              trailing: checked
                                  ? const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF58D26B),
                              )
                                  : const SizedBox(width: 24, height: 24),
                              onTap: () => Navigator.of(ctx).pop(o),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            child: const Text(
                              'Zrušiť',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(''),
                            child: const Text(
                              'Vymazať',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(selected ?? ''),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Hotovo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((value) {
      if (value == null) return null;
      if (value.isEmpty) return '';
      return value;
    });
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (_localImageFile != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: Colors.white.withOpacity(0.06),
                  border: Border.all(color: Colors.white10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    height: 260,
                    width: double.infinity,
                    color: Colors.white.withOpacity(0.04),
                    alignment: Alignment.center,
                    child: Image.file(
                      _localImageFile!,
                      height: 260,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          )
        else if (_uploadedImageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: Colors.white.withOpacity(0.06),
                  border: Border.all(color: Colors.white10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    height: 260,
                    width: double.infinity,
                    color: Colors.white.withOpacity(0.04),
                    alignment: Alignment.center,
                    child: Image.network(
                      _uploadedImageUrl!,
                      height: 260,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        _buildNameFreeField(),
        const SizedBox(height: 12),
        _brandAutoComplete(),
        const SizedBox(height: 12),
        CategoryPicker(
          hideSubCategory: false,
          initialMainGroup: _selectedMainGroupKey,
          initialCategory: _selectedCategoryKey,
          initialSubCategory: _selectedSubCategoryKey,
          onChanged: (data) {
            final main = data['mainGroup'];
            final cat = data['category'];
            final sub = data['subCategory'];

            setState(() {
              _selectedMainGroupKey = main;
              _selectedCategoryKey = cat;
              _selectedSubCategoryKey = sub;
              _selectedLayerRole =
              sub == null ? null : subCategoryLayerRoles[sub];

              _isSystemNameSelected = false;
              _selectedSystemNameLabel = null;
              _selectedSystemSubCategoryKey = null;
              _refreshAutoName();
            });
          },
        ),
        const SizedBox(height: 12),
        _buildMultiSelectField(
          label: 'Farby',
          options: allowedColors,
          selected: _selectedColors,
          onChanged: (v) => setState(() {
            _selectedColors = v;
            _refreshAutoName();
          }),
        ),
        const SizedBox(height: 12),
        _buildMultiSelectField(
          label: 'Štýly',
          options: allowedStyles,
          selected: _selectedStyles,
          onChanged: (v) => setState(() => _selectedStyles = v),
        ),
        const SizedBox(height: 12),
        _buildSingleSelectField(
          label: 'Vzor',
          options: allowedPatterns,
          selected: _selectedPatterns.isEmpty ? null : _selectedPatterns.first,
          onChanged: (v) {
            setState(() {
              if (v == null) return;
              if (v.isEmpty) {
                _selectedPatterns = [];
              } else {
                _selectedPatterns = [v];
              }
            });
          },
        ),
        const SizedBox(height: 12),
        _buildMultiSelectField(
          label: 'Sezóny',
          options: allowedSeasons,
          selected: _selectedSeasons,
          onChanged: (v) => setState(() => _selectedSeasons = _sanitizeSeasons(v)),
        ),
    const SizedBox(height: 16),
    SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
    onPressed: _save,
    style: ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    elevation: 0,
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    ),
    ),
    child: const Text(
    'Uložiť do šatníka',
    style: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    ),
    ),
    ),
    ),
    const SizedBox(height: 10),
    if (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty)
    OutlinedButton.icon(
    onPressed: () {
    final payload = <String, dynamic>{
    'name': (_nameController.text.trim().isNotEmpty
    ? _nameController.text.trim()
        : _computeAutoNameWithColor()),
    'brand': _brandController.text.trim(),
    'mainGroupKey': _selectedMainGroupKey,
    'categoryKey': _selectedCategoryKey,
    'subCategoryKey': _selectedSubCategoryKey,
    'color': _selectedColors,
    'style': _selectedStyles,
    'pattern': _selectedPatterns,
    'season': _selectedSeasons,
    'imageUrl': _uploadedImageUrl,
    };

    Navigator.push(
    context,
    MaterialPageRoute(
    builder: (_) => StylistChatScreen(
    initialClothingData: payload,
    ),
    ),
    );
    },
    icon: const Icon(Icons.chat_bubble_outline_rounded),
    label: const Text('Poradiť sa o tomto kúsku'),
    style: OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: BorderSide(color: Colors.white.withOpacity(0.14)),
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    ),
    ),
    ),
      ],
    );
  }
  Widget _buildLuxuryEmptyState() {
    Widget glassCard({
      required Widget child,
      EdgeInsets? padding,
      double opacity = 0.06,
    }) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white.withOpacity(opacity),
              border: Border.all(color: Colors.white10),
            ),
            child: child,
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            AddClothingScreen._luxuryBgAsset,
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.78),
                  Colors.black.withOpacity(0.34),
                  Colors.black.withOpacity(0.86),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              children: [
                glassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.08),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pridať oblečenie',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Pridaj nový kúsok do svojho šatníka',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                glassCard(
                  padding: const EdgeInsets.all(18),
                  opacity: 0.07,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFD6B36A).withOpacity(0.12),
                          border: Border.all(
                            color: const Color(0xFFD6B36A).withOpacity(0.18),
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_outlined,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Vyber fotku a AI automaticky rozpozná typ oblečenia, farby, vzor aj sezónu.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFD6B36A).withOpacity(0.16),
                        Colors.white.withOpacity(0.04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.08),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(
                        Icons.checkroom_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Pridaj nový kúsok',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Odfotiť alebo vybrať fotku z galérie a pokračovať do AI spracovania.',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => AddClothingScreen.openFromPicker(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.white.withOpacity(0.94),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_rounded, color: Colors.black87, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Začať pridávanie',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(width: 10),
                          Icon(Icons.arrow_forward_ios_rounded, color: Colors.black54, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                glassCard(
                  padding: const EdgeInsets.all(14),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pre lepší výsledok',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 10),
                      _TipRow(icon: Icons.check_rounded, text: 'Kúsok polož alebo zaves rovno'),
                      _TipRow(icon: Icons.check_rounded, text: 'Foť bez zbytočných predmetov okolo'),
                      _TipRow(icon: Icons.check_rounded, text: 'Nenechaj oblečenie príliš tmavé'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showPick = !_isAiLoading &&
        _localImageFile == null &&
        (_uploadedImageUrl == null || _uploadedImageUrl!.isEmpty) &&
        !widget.isEditing;

    final showLoader = _isAiLoading;
    final showForm = _aiCompleted || widget.isEditing || _aiFailed;

    if (showPick) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0C),
        body: _buildLuxuryEmptyState(),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              AddClothingScreen._luxuryBgAsset,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.80),
                    Colors.black.withOpacity(0.32),
                    Colors.black.withOpacity(0.88),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          color: Colors.white.withOpacity(0.06),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.08),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: const Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.isEditing ? 'Upraviť oblečenie' : 'Pridať oblečenie',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    showLoader
                                        ? 'AI spracováva obrázok'
                                        : 'Skontroluj a ulož detaily kúsku',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (showLoader) ...[
                    _buildProcessingImagePreview(),
                    const SizedBox(height: 14),
                    _buildProgressChecklist(),
                  ],
                  if (_aiFailed) ...[
                    const SizedBox(height: 14),
                    _buildAiError(),
                  ],
                  if (showForm) ...[
                    const SizedBox(height: 14),
                    _buildForm(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

