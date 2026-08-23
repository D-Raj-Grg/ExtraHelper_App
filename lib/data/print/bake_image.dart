import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import 'print_bitmap.dart';

/// Turns an uploaded logo or payment QR into the 1-bit bitmaps a thermal head
/// actually prints.
///
/// **A line-for-line port of the web's `components/print/bake-image.ts`.** The
/// two must agree byte for byte: the same restaurant uploads its logo from
/// whichever client is to hand, and a phone that dithers differently from the
/// browser prints a visibly different mark on the same paper. Any change to one
/// belongs in the other, in the same commit.
///
/// Baking happens **at upload**, not at print time, because the print agent and
/// the phone's own print loop are byte pipes — they fetch finished ESC/POS and
/// write it to a socket. Rasterise at print time and branding would appear on
/// till-driven printers only.
///
/// Two treatments, for one reason: a QR is data, a logo is a picture. Dithering
/// a QR scatters its module edges and it stops scanning; hard-thresholding a
/// logo turns a photographic mark into a blob.
///
/// Runs on a background isolate — see `bakeAssetInBackground`.

/// A logo taller than this eats the top of every receipt.
const _logoMaxHeightRatio = 0.25;

/// Leaves room either side so the QR is not crowded by the paper edge.
const _qrWidthRatio = 0.62;

/// The quiet zone a scanner needs, as a fraction of the QR's own size.
const _qrQuietRatio = 0.08;

/// Total base64 across every width. The web applies the same ceiling before
/// storing, and `tenant_settings` is read on every print.
const bakeByteBudget = 200 * 1024;

class BakeResult {
  const BakeResult({
    required this.variants,
    required this.bytes,
    required this.unscannable,
  });

  /// `{"384": {w,h,data}, "416": …, "576": …}` — the shape stored under
  /// `receipt_template.print_assets.<kind>`.
  final Map<String, dynamic> variants;

  /// Base64 payload size across all widths, for the storage guard.
  final int bytes;

  /// Paper widths whose baked QR would not decode. Always empty for a logo.
  final List<int> unscannable;
}

/// Thrown when the file is not an image at all. Anything else is a judgement
/// the caller makes from [BakeResult].
class BakeFailure implements Exception {
  const BakeFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// [kind] is `logo` or `qr`.
BakeResult bakeAsset(Uint8List bytes, String kind) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const BakeFailure(
      "That file isn't an image we can read. Try a PNG or JPEG.",
    );
  }
  // Straight to greyscale: every step below works on luma, and carrying three
  // channels through a dither is three times the arithmetic for one answer.
  final source = _toLuma(decoded);
  final trimmed = kind == 'qr' ? _trimWhiteBorder(source) : source;

  final variants = <String, dynamic>{};
  final unscannable = <int>[];
  var total = 0;

  for (final dots in bakeWidths) {
    final composed = kind == 'qr'
        ? _composeQr(trimmed, dots)
        : _composeLogo(trimmed, dots);
    if (kind == 'qr' && !_decodes(composed)) unscannable.add(dots);
    final bitmap = packBitmap(composed.pixels, composed.w, composed.h);
    variants['$dots'] = bitmap.toJson();
    total += bitmap.data.length;
  }

  return BakeResult(
    variants: variants,
    bytes: total,
    unscannable: unscannable,
  );
}

/// A greyscale canvas: one byte per dot, row-major, 0 = black.
class _Grey {
  _Grey(this.w, this.h, this.pixels);

  _Grey.white(this.w, this.h) : pixels = Uint8List(w * h)..fillRange(0, w * h, 255);

  final int w;
  final int h;
  final Uint8List pixels;

  int at(int x, int y) => pixels[y * w + x];
}

_Grey _toLuma(img.Image source) {
  final out = Uint8List(source.width * source.height);
  var i = 0;
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final p = source.getPixel(x, y);
      // The mean of the three channels, matching the browser's `luma()` — not
      // the perceptual Rec.601 weighting, which would bake a different image.
      var value = (p.r + p.g + p.b) / 3;
      // Composite onto white: a transparent PNG logo is the common case, and
      // treating alpha as black prints a solid rectangle.
      final alpha = p.a / 255;
      value = value * alpha + 255 * (1 - alpha);
      out[i++] = value.round().clamp(0, 255);
    }
  }
  return _Grey(source.width, source.height, out);
}

/// Payment QRs are usually handed over as a screenshot with a wide white
/// surround. Cropping it back lets the code itself use the paper.
_Grey _trimWhiteBorder(_Grey source) {
  const near = 230;
  var top = 0;
  var left = 0;
  var right = source.w - 1;
  var bottom = source.h - 1;

  bool rowBlank(int y) {
    for (var x = 0; x < source.w; x++) {
      if (source.at(x, y) < near) return false;
    }
    return true;
  }

  bool colBlank(int x) {
    for (var y = top; y <= bottom; y++) {
      if (source.at(x, y) < near) return false;
    }
    return true;
  }

  while (top < bottom && rowBlank(top)) {
    top++;
  }
  while (bottom > top && rowBlank(bottom)) {
    bottom--;
  }
  while (left < right && colBlank(left)) {
    left++;
  }
  while (right > left && colBlank(right)) {
    right--;
  }

  final w = right - left + 1;
  final h = bottom - top + 1;
  // Nothing but white, or a sliver: keep the original rather than crop to
  // something a scanner could never read.
  if (w < 8 || h < 8) return source;

  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out[y * w + x] = source.at(left + x, top + y);
    }
  }
  return _Grey(w, h, out);
}

/// Full printable width, white, with the artwork centred in it.
///
/// The centring is baked into the pixels on purpose: `ESC a 1` is honoured for
/// text on every printer but for raster bit images on only some of them.
_Grey _composeLogo(_Grey source, int dots) {
  final maxH = (dots * _logoMaxHeightRatio).round();
  var w = dots;
  var h = (source.h * dots / source.w).round();
  if (h > maxH) {
    h = maxH;
    w = (source.w * maxH / source.h).round();
  }
  w = w.clamp(1, dots);
  h = h.clamp(1, maxH);

  final canvas = _Grey.white(dots, h);
  _draw(canvas, source, ((dots - w) / 2).round(), 0, w, h, smooth: true);
  _dither(canvas);
  return canvas;
}

_Grey _composeQr(_Grey source, int dots) {
  final side = (dots * _qrWidthRatio).round();
  final quiet = (side * _qrQuietRatio).round();
  final box = side + quiet * 2;

  final canvas = _Grey.white(dots, box);
  // Nearest-neighbour, and square regardless of what was uploaded: a smoothed
  // QR is a grey mush that the threshold below rounds into ragged modules, and
  // a stretched one does not scan at all.
  _draw(canvas, source, ((dots - side) / 2).round(), quiet, side, side,
      smooth: false);
  _threshold(canvas, _otsu(canvas));
  return canvas;
}

/// Scale [source] into [canvas] at ([dx], [dy]), [w] × [h].
///
/// [smooth] picks box-average sampling (a logo, where a hard pick aliases) over
/// nearest-neighbour (a QR, where averaging destroys the modules).
void _draw(
  _Grey canvas,
  _Grey source,
  int dx,
  int dy,
  int w,
  int h, {
  required bool smooth,
}) {
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final tx = dx + x;
      final ty = dy + y;
      if (tx < 0 || ty < 0 || tx >= canvas.w || ty >= canvas.h) continue;
      canvas.pixels[ty * canvas.w + tx] = smooth
          ? _sampleBox(source, x, y, w, h)
          : _sampleNearest(source, x, y, w, h);
    }
  }
}

int _sampleNearest(_Grey source, int x, int y, int w, int h) {
  final sx = (x * source.w ~/ w).clamp(0, source.w - 1);
  final sy = (y * source.h ~/ h).clamp(0, source.h - 1);
  return source.at(sx, sy);
}

/// The average of every source pixel this destination pixel covers. Equivalent
/// to the browser's high-quality downscale for the shrink case, which is the
/// only case a receipt logo ever hits.
int _sampleBox(_Grey source, int x, int y, int w, int h) {
  final x0 = (x * source.w ~/ w).clamp(0, source.w - 1);
  final y0 = (y * source.h ~/ h).clamp(0, source.h - 1);
  final x1 = (((x + 1) * source.w + w - 1) ~/ w).clamp(x0 + 1, source.w);
  final y1 = (((y + 1) * source.h + h - 1) ~/ h).clamp(y0 + 1, source.h);

  var sum = 0;
  var count = 0;
  for (var sy = y0; sy < y1; sy++) {
    for (var sx = x0; sx < x1; sx++) {
      sum += source.at(sx, sy);
      count++;
    }
  }
  return count == 0 ? source.at(x0, y0) : (sum / count).round();
}

/// Floyd–Steinberg.
///
/// A thermal head has one bit per dot, so a gradient has to be carried by dot
/// density; the flat 128 cutoff the page rasteriser uses is right for black
/// text on white and wrong for a mark with any shading in it.
void _dither(_Grey canvas) {
  final w = canvas.w;
  final h = canvas.h;
  final grey = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    grey[i] = canvas.pixels[i].toDouble();
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final old = grey[i];
      final next = old < 128 ? 0.0 : 255.0;
      grey[i] = next;
      final err = old - next;
      if (x + 1 < w) grey[i + 1] += err * 7 / 16;
      if (y + 1 < h) {
        if (x > 0) grey[i + w - 1] += err * 3 / 16;
        grey[i + w] += err * 5 / 16;
        if (x + 1 < w) grey[i + w + 1] += err / 16;
      }
    }
  }

  for (var i = 0; i < w * h; i++) {
    canvas.pixels[i] = grey[i] < 128 ? 0 : 255;
  }
}

/// `<=`, not `<`.
///
/// Otsu returns the last level belonging to the dark class, so a clean
/// black-and-white QR — every pixel at 0 or 255 — comes back with a cut of 0.
/// Compared exclusively, nothing is ever below it and the whole code bakes out
/// white.
void _threshold(_Grey canvas, int cut) {
  for (var i = 0; i < canvas.pixels.length; i++) {
    canvas.pixels[i] = canvas.pixels[i] <= cut ? 0 : 255;
  }
}

/// Otsu's method, rather than a fixed 128: a QR photographed off a phone screen
/// or printed on coloured stock has its own idea of what "white" is.
int _otsu(_Grey canvas) {
  final hist = List<int>.filled(256, 0);
  final n = canvas.pixels.length;
  for (final value in canvas.pixels) {
    hist[value]++;
  }

  var sum = 0.0;
  for (var t = 0; t < 256; t++) {
    sum += t * hist[t];
  }

  var sumB = 0.0;
  var wB = 0;
  var best = 0.0;
  var cut = 128;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = n - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      cut = t;
    }
  }
  return cut;
}

/// The whole point of the exercise.
///
/// A payment QR that prints but does not scan is a guest standing at the till
/// with a phone that will not pay, and nobody finds out until service.
bool _decodes(_Grey canvas) {
  try {
    // zxing2 wants packed ARGB. The canvas is already pure black and white by
    // the time this runs, so the three channels are the same byte.
    final argb = Int32List(canvas.w * canvas.h);
    for (var i = 0; i < argb.length; i++) {
      final v = canvas.pixels[i];
      argb[i] = 0xff000000 | (v << 16) | (v << 8) | v;
    }
    final source = RGBLuminanceSource(canvas.w, canvas.h, argb);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    return QRCodeReader().decode(bitmap).text.isNotEmpty;
  } catch (_) {
    // Any reader failure means "did not decode". There is no partial credit on
    // a QR a scanner has to read at a counter.
    return false;
  }
}
