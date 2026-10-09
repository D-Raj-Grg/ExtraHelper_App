import 'dart:convert';
import 'dart:typed_data';

import 'package:extrahelper/data/supabase/flyer_designs_repository.dart';
import 'package:extrahelper/features/coupons/flyer_pdf.dart';
import 'package:extrahelper/features/coupons/flyer_placement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

Uint8List _png() {
  final img = im.Image(width: 120, height: 170);
  im.fill(img, color: im.ColorRgb8(250, 240, 220));
  return Uint8List.fromList(im.encodePng(img));
}

int _pageCount(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(pdf)).length;

void main() {
  group('placement', () {
    test('the default placement round-trips through json', () {
      final back = parsePlacement(defaultPlacement.toJson());
      expect(back, isNotNull);
      expect(back!.code.x, defaultPlacement.code.x);
      expect(back.qr.s, defaultPlacement.qr.s);
      expect(back.codeColor, '#7a2a12');
      expect(back.codeScale, 0.85);
    });

    test('a malformed placement is rejected so the default is used', () {
      expect(parsePlacement(null), isNull);
      expect(parsePlacement({'code': {}, 'qr': {}}), isNull);
      final bad = defaultPlacement.toJson()..['codeColor'] = 'red';
      expect(parsePlacement(bad), isNull);
      expect(
        FlyerDesign.fromRow({
          'id': 'd1',
          'name': 'x',
          'image_path': 't/a.png',
          'width': 1000,
          'height': '1400',
          'placement': {'nonsense': true},
          'mode': 'url',
        }).placement.qr.s,
        defaultPlacement.qr.s,
      );
    });

    test('moving stays inside the picture', () {
      final p = moveCode(defaultPlacement, 5, 5);
      expect(p.code.x, closeTo(1 - p.code.w, 1e-9));
      expect(p.code.y, closeTo(1 - p.code.h, 1e-9));
      final q = moveQr(defaultPlacement, -5, -5, 1.4);
      expect(q.qr.x, 0);
      expect(q.qr.y, 0);
      final far = moveQr(defaultPlacement, 5, 5, 1.4);
      expect(far.qr.x, closeTo(1 - far.qr.s, 1e-9));
      expect(far.qr.y, closeTo(1 - far.qr.s * 1.4, 1e-9));
    });

    test('resizing keeps the minimums and the picture edge', () {
      expect(resizeCode(defaultPlacement, -5, -5).code.w, 0.05);
      expect(resizeCode(defaultPlacement, -5, -5).code.h, 0.01);
      expect(resizeQr(defaultPlacement, -5, -5, 1.4).qr.s, 0.04);
      final big = resizeQr(defaultPlacement, 5, 5, 1.4);
      expect(big.qr.x + big.qr.s, lessThanOrEqualTo(1 + 1e-9));
      expect(big.qr.y + big.qr.s * 1.4, lessThanOrEqualTo(1 + 1e-9));
    });
  });

  group('qr', () {
    test('runs merge neighbours and cover every dark module', () {
      const o = true;
      const x = false;
      final runs = qrRuns(const [
        [o, o, x, o],
        [x, x, x, x],
        [o, o, o, o],
      ]);
      expect(runs, [(0, 0, 2), (0, 3, 1), (2, 0, 4)]);
    });

    test('payload follows the mode and falls back to the bare code', () {
      expect(
        flyerPayload(
          mode: 'url',
          origin: 'https://app.example.com/',
          slug: 'sekuwa',
          code: 'DASH-ABC123',
        ),
        'https://app.example.com/s/sekuwa?coupon=DASH-ABC123',
      );
      expect(
        flyerPayload(
          mode: 'code',
          origin: 'https://app.example.com',
          slug: 'sekuwa',
          code: 'DASH-ABC123',
        ),
        'DASH-ABC123',
      );
      expect(
        flyerPayload(mode: 'url', origin: '', slug: 's', code: 'DASH-ABC123'),
        'DASH-ABC123',
      );
    });

    test('a grid is produced for a url payload', () {
      final g = flyerQrGrid('https://app.example.com/s/sekuwa?coupon=X-1234');
      expect(g, isNotEmpty);
      expect(g.length, g.first.length);
    });
  });

  test('slugify', () {
    expect(slugify('Dashain Flyers!'), 'dashain-flyers');
    expect(slugify('***'), 'flyers');
  });

  group('pdf', () {
    test('one A4 page per code, valid pdf', () async {
      final pdf = await buildFlyerPdfSync(_png(), defaultPlacement, const [
        FlyerPage(
          code: 'DASH-AAAAAA',
          payload: 'https://x.test/s/a?coupon=DASH-AAAAAA',
        ),
        FlyerPage(code: 'DASH-BBBBBB', payload: 'DASH-BBBBBB'),
        FlyerPage(code: 'DASH-CCCCCC', payload: 'DASH-CCCCCC'),
      ]);
      expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(_pageCount(pdf), 3);
      // A4 in points.
      expect(latin1.decode(pdf), contains('595.28'));
    });

    test('the picture is embedded once, not once per page', () async {
      final one = await buildFlyerPdfSync(_png(), defaultPlacement, const [
        FlyerPage(code: 'A-111111', payload: 'A-111111'),
      ]);
      final fifty = await buildFlyerPdfSync(_png(), defaultPlacement, [
        for (var i = 0; i < 50; i++)
          FlyerPage(code: 'A-${100000 + i}', payload: 'A-${100000 + i}'),
      ]);
      expect(_pageCount(fifty), 50);
      // 50 pages are far less than 50x one page: the template is shared.
      expect(fifty.length, lessThan(one.length * 20));
    });

    test('runs off the UI isolate too', () async {
      final pdf = await buildFlyerPdf(
        template: _png(),
        placement: defaultPlacement,
        pages: const [FlyerPage(code: 'Z-999999', payload: 'Z-999999')],
      );
      expect(_pageCount(pdf), 1);
    });
  });
}
