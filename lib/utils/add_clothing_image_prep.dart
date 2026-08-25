import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Same upload bounds as camera/gallery Add (`_ensureImageUrl`).
const int kAddClothingUploadMaxSide = 1600;
const int kAddClothingUploadJpegQuality = 88;

/// Decode, bound longest side, encode JPEG. Used by photo Add and product-link
/// owned-image handoff so both land in the same analyzer-friendly format.
Uint8List prepareJpgForUpload(Map<String, dynamic> args) {
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

  return Uint8List.fromList(img.encodeJpg(out, quality: quality));
}
