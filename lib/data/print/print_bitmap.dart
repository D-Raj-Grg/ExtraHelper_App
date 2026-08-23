import 'dart:convert';
import 'dart:typed_data';

/// 1-bit bitmaps for thermal printers.
///
/// Ported from the web's `lib/print/bitmap.ts`. Rows are packed MSB-first, one
/// bit per dot, 1 = burn, and the width is always a multiple of 8: a raster row
/// goes out as whole bytes, so a width that isn't makes the printer's row wider
/// than the canvas it was measured against.
///
/// Plain Dart — no Flutter imports — so the packing can be unit-tested without
/// a binding.

/// Printable dots per paper width in millimetres.
const _dotsByWidth = <int, int>{58: 384, 76: 416, 80: 576};

int printableDots(int paperWidthMm) => _dotsByWidth[paperWidthMm] ?? 576;

/// The widths a branding image is baked for, so a print job never misses its
/// size. Every value is a multiple of 8 — see the row-packing note above.
const bakeWidths = <int>[384, 416, 576];

/// A baked image, ready to print at one specific paper width.
class PrintBitmap {
  const PrintBitmap({required this.w, required this.h, required this.data});

  final int w;
  final int h;

  /// Base64 of the packed rows — `ceil(w / 8) * h` bytes.
  final String data;

  Map<String, dynamic> toJson() => {'w': w, 'h': h, 'data': data};

  static PrintBitmap fromJson(Map<String, dynamic> json) => PrintBitmap(
    w: (json['w'] as num).toInt(),
    h: (json['h'] as num).toInt(),
    data: json['data'] as String,
  );

  /// How many bytes the packed rows should be. The server refuses a bitmap
  /// whose payload disagrees with this: a row count that does not match makes
  /// the printer read the next ticket's bytes as image data and spit out a
  /// metre of noise.
  int get expectedBytes => ((w + 7) ~/ 8) * h;
}

/// Pack a run of luma values into MSB-first rows. `luma < 128` burns.
///
/// [luma] is row-major, [w] × [h], one byte per dot.
PrintBitmap packBitmap(Uint8List luma, int w, int h) {
  final widthBytes = (w + 7) ~/ 8;
  final out = Uint8List(widthBytes * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (luma[y * w + x] < 128) {
        out[y * widthBytes + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
  }
  return PrintBitmap(w: w, h: h, data: base64Encode(out));
}
