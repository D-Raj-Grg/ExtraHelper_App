import 'dart:convert';
import 'dart:typed_data';

import 'package:extrahelper/data/print/bake_image.dart';
import 'package:extrahelper/data/print/print_bitmap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// A real QR, encoded here rather than checked in as a fixture so the test says
/// what it is testing. Scaled up because a payment QR arrives as a screenshot,
/// not as a 21-module matrix.
Uint8List _qrPng(String payload, {int scale = 8, int quiet = 16}) {
  final matrix = Encoder.encode(payload, ErrorCorrectionLevel.m).matrix!;
  final side = matrix.width * scale + quiet * 2;
  final image = img.Image(width: side, height: side);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (matrix.get(x, y) == 1) {
        img.fillRect(
          image,
          x1: quiet + x * scale,
          y1: quiet + y * scale,
          x2: quiet + (x + 1) * scale - 1,
          y2: quiet + (y + 1) * scale - 1,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    }
  }
  return img.encodePng(image);
}

Uint8List _solidPng(int w, int h, int level) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(level, level, level));
  return img.encodePng(image);
}

void main() {
  group('bakeAsset — payment QR', () {
    test('bakes every roll width and each one still scans', () {
      final result = bakeAsset(_qrPng('https://pay.example/abc123'), 'qr');

      expect(result.variants.keys.toSet(), {'384', '416', '576'});
      expect(
        result.unscannable,
        isEmpty,
        reason: 'a clean QR must survive black-and-white printing',
      );
    });

    test('every variant carries exactly ceil(w/8)*h packed bytes', () {
      final result = bakeAsset(_qrPng('https://pay.example/abc123'), 'qr');

      for (final entry in result.variants.entries) {
        final bitmap = PrintBitmap.fromJson(
          entry.value as Map<String, dynamic>,
        );
        expect(bitmap.w, int.parse(entry.key));
        expect(
          base64Decode(bitmap.data).length,
          bitmap.expectedBytes,
          reason:
              'a payload that disagrees with w/h makes the printer read the '
              'next ticket as image data',
        );
      }
    });

    test('stays inside the storage budget the server enforces', () {
      final result = bakeAsset(_qrPng('https://pay.example/abc123'), 'qr');
      expect(result.bytes, lessThan(bakeByteBudget));
    });

    test('a featureless image bakes but never scans', () {
      final result = bakeAsset(_solidPng(200, 200, 200), 'qr');
      expect(result.unscannable, bakeWidths);
    });
  });

  group('bakeAsset — logo', () {
    test('never taller than a quarter of the paper', () {
      // Deliberately tall: unconstrained, this would be 3x the roll width.
      final result = bakeAsset(_solidPng(100, 300, 40), 'logo');

      for (final entry in result.variants.entries) {
        final bitmap = PrintBitmap.fromJson(
          entry.value as Map<String, dynamic>,
        );
        expect(bitmap.h, lessThanOrEqualTo((bitmap.w * 0.25).round()));
      }
    });

    test('fills the full printable width', () {
      final result = bakeAsset(_solidPng(400, 100, 40), 'logo');
      final bitmap = PrintBitmap.fromJson(
        result.variants['576'] as Map<String, dynamic>,
      );
      expect(bitmap.w, 576);
    });

    test('a logo is never checked for scannability', () {
      final result = bakeAsset(_solidPng(200, 200, 255), 'logo');
      expect(result.unscannable, isEmpty);
    });

    test('a dark mark burns rather than baking out white', () {
      // The Otsu `<=` trap: an image of one flat level must not threshold to
      // all-white just because every pixel sits on the cut.
      final result = bakeAsset(_solidPng(200, 60, 20), 'logo');
      final bitmap = PrintBitmap.fromJson(
        result.variants['384'] as Map<String, dynamic>,
      );
      final bytes = base64Decode(bitmap.data);
      expect(bytes.any((b) => b != 0), isTrue, reason: 'nothing would print');
    });
  });

  test('a file that is not an image is refused, not silently blank', () {
    expect(
      () => bakeAsset(Uint8List.fromList(utf8.encode('not an image')), 'logo'),
      throwsA(isA<BakeFailure>()),
    );
  });
}
