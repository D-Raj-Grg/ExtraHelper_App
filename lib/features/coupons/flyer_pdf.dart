import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';

import 'flyer_placement.dart';

/// A4 in points, exactly as the web's `flyer-pdf.ts`: one flyer per page,
/// the picture stretched to the page (templates are within ~1% of A4).
const _pageW = 595.28;
const _pageH = 841.89;

/// One flyer: the code printed on it and what its QR carries.
class FlyerPage {
  const FlyerPage({required this.code, required this.payload});

  final String code;
  final String payload;
}

/// Build the PDF off the UI isolate — a 1000-page run is seconds of work.
/// [template] is the JPEG or PNG exactly as uploaded.
Future<Uint8List> buildFlyerPdf({
  required Uint8List template,
  required FlyerPlacement placement,
  required List<FlyerPage> pages,
}) => Isolate.run(() => buildFlyerPdfSync(template, placement, pages));

/// The same, on the calling isolate (tests, and callers already off-thread).
Future<Uint8List> buildFlyerPdfSync(
  Uint8List template,
  FlyerPlacement placement,
  List<FlyerPage> pages,
) async {
  final doc = PdfDocument();
  // Embedded once; every page refers to the same image object.
  final image = PdfImage.file(doc, bytes: template);
  final font = PdfFont.helveticaBold(doc);
  final codeColor = _color(placement.codeColor);
  final qrColor = _color(placement.qrColor);

  for (final p in pages) {
    final page = PdfPage(doc, pageFormat: const PdfPageFormat(_pageW, _pageH));
    final g = page.getGraphics();
    g.drawImage(image, 0, 0, _pageW, _pageH);

    // --- Code text: centred in its box, shrunk to fit the width.
    final c = placement.code;
    final boxX = c.x * _pageW;
    final boxW = c.w * _pageW;
    final boxH = c.h * _pageH;
    final boxY = _pageH - (c.y + c.h) * _pageH; // PDF y points up
    var size = boxH * placement.codeScale;
    final unit = font.stringMetrics(p.code);
    final widthAt = unit.width * size;
    if (widthAt > boxW && widthAt > 0) size = size * boxW / widthAt;
    final textW = unit.width * size;
    final textH = unit.ascent * size;
    g
      ..setFillColor(codeColor)
      ..drawString(
        font,
        size,
        p.code,
        boxX + (boxW - textW) / 2,
        boxY + (boxH - textH) / 2,
      );

    // --- QR: vector rectangles, one per run of dark modules.
    final grid = flyerQrGrid(p.payload);
    if (grid.isNotEmpty) {
      final q = placement.qr;
      final side = q.s * _pageW;
      final qrX = q.x * _pageW;
      final qrY = _pageH - q.y * _pageH - side;
      final inner = side * (1 - 2 * placement.qrInset);
      final cell = inner / grid.length;
      final ox = qrX + side * placement.qrInset;
      final oy = qrY + side * placement.qrInset + inner;
      g.setFillColor(qrColor);
      for (final (row, col, len) in qrRuns(grid)) {
        g.drawRect(ox + col * cell, oy - (row + 1) * cell, len * cell, cell);
      }
      g.fillPath();
    }
  }
  return doc.save();
}

PdfColor _color(String hex) {
  try {
    return PdfColor.fromHex(hex);
  } catch (_) {
    return PdfColors.black;
  }
}
