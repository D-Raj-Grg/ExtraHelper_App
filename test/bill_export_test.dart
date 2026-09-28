import 'dart:io';

import 'package:extrahelper/data/supabase/settings_repository.dart';
import 'package:extrahelper/features/pos/bill_export.dart';
import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The arithmetic and the filing behind sending a receipt.
///
/// Nothing here draws anything: these are the parts that decide how big the
/// picture is, what it is called, and when it is thrown away — the parts that
/// go wrong quietly on someone else's phone.

Bill _bill({String id = 'bill-1111-2222-3333-444444444444'}) => Bill(
  id: id,
  status: 'paid',
  createdAt: DateTime(2026, 8, 13, 19, 42),
  subtotalCents: 1000,
  taxCents: 0,
  serviceChargeCents: 0,
  discountCents: 0,
  tipCents: 0,
  roundingCents: 0,
  totalCents: 1000,
);

void main() {
  // `shareOriginOf` reaches through a GlobalKey, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('receiptFileName', () {
    test('carries the same eight characters the slip quotes', () {
      expect(receiptFileName(_bill()), 'receipt-BILL-111-20260813-1942.png');
    });

    test('a short id is not cut into', () {
      expect(receiptFileName(_bill(id: 'abc')), startsWith('receipt-ABC-'));
    });
  });

  group('exportPixelRatio', () {
    test('a normal bill goes out at full sharpness', () {
      expect(exportPixelRatio(const Size(380, 400)), 3.0);
    });

    test('a long bill loses sharpness rather than failing to send', () {
      // 380 × 3000 at 3× would be 9000px tall — past what plenty of Android
      // GPUs will allocate.
      final ratio = exportPixelRatio(const Size(380, 3000));
      expect(ratio, lessThan(3.0));
      expect(3000 * ratio, lessThanOrEqualTo(kBillExportMaxPx));
    });

    test('never goes below 1, however long the bill', () {
      expect(exportPixelRatio(const Size(380, 999999)), 1.0);
    });

    test('a degenerate size does not divide by zero', () {
      expect(exportPixelRatio(Size.zero), 1.0);
    });
  });

  group('sweepOldReceipts', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('receipt-sweep');
    });
    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('yesterday goes, this minute stays', () async {
      final old = File('${dir.path}/old.png')..writeAsBytesSync([1]);
      final fresh = File('${dir.path}/fresh.png')..writeAsBytesSync([1]);
      old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 1)));

      await sweepOldReceipts(dir);

      expect(old.existsSync(), isFalse);
      expect(
        fresh.existsSync(),
        isTrue,
        reason: 'a share may still be reading',
      );
    });

    test(
      'a missing directory is not an error — a tidy-up never fails a share',
      () async {
        final gone = Directory('${dir.path}/nope');
        await expectLater(sweepOldReceipts(gone), completes);
      },
    );
  });

  group('ShareRequest', () {
    test('an origin is always a real rect, because null crashes iPad', () {
      // The key is not attached to anything, which is the case that used to
      // hand UIKit a null anchor.
      final rect = shareOriginOf(GlobalKey());
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
    });
  });

  group('BillBrand.qrExpected', () {
    test('a restaurant that uploaded no QR is not owed a warning', () {
      expect(BillBrand.qrExpected(const ReceiptTemplate()), isFalse);
    });

    test('a restaurant that did upload one is', () {
      // This is what decides whether a cashier is told the guest cannot scan
      // the receipt they were just sent.
      expect(
        BillBrand.qrExpected(const ReceiptTemplate(qrUrl: 'https://x/qr.png')),
        isTrue,
      );
    });
  });
}
