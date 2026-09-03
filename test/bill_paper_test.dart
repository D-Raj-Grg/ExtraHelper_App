import 'dart:typed_data';

import 'package:extrahelper/core/theme/app_theme.dart';
import 'package:extrahelper/features/pos/bill_export.dart';
import 'package:extrahelper/features/pos/bill_models.dart';
import 'package:extrahelper/features/pos/bill_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a guest is handed.
///
/// The web receipt and the printed slip both carry the restaurant's logo, its
/// closing words and the payment QR a guest scans. Until this the phone carried
/// none of them, so a cashier standing at the table had nothing to hold out.
/// These tests pin the three that matter: the code is there when it exists, it
/// is *absent* rather than placeheld when it does not, and the slip always ends
/// with something.

/// A 1×1 transparent PNG. Decodes in a test, where a network image cannot:
/// `flutter_test` answers every HTTP request with a 400.
final _pixel = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

BillSnapshot _snapshot({String status = 'paid'}) {
  const lines = [
    BillLine(
      id: 'l1',
      orderItemId: 'oi1',
      description: 'Tuborg',
      qty: 1,
      unitPriceCents: 45000,
      totalCents: 45000,
    ),
  ];
  return BillSnapshot(
    bill: Bill(
      id: 'bill-1111-2222-3333-444444444444',
      status: status,
      createdAt: DateTime(2026, 8, 13, 19, 42),
      subtotalCents: 45000,
      taxCents: 0,
      serviceChargeCents: 0,
      discountCents: 0,
      tipCents: 0,
      roundingCents: 0,
      totalCents: 45000,
      tableLabel: 'A1',
    ),
    lines: lines,
    payments: const [],
    charges: const [],
    discounts: const [],
    settings: const TenantMoneySettings(),
  );
}

/// The document on its own — no screen, no scroller. `EarlierDayMark` inside it
/// reads a provider, hence the scope.
Widget _paper(BillBrand brand, {bool forExport = false}) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: BillPaper(
          snapshot: _snapshot(),
          currency: 'NPR',
          shopName: 'The Sekuwa Station',
          brand: brand,
          forExport: forExport,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the payment QR and its caption are on the slip', (tester) async {
    await tester.pumpWidget(
      _paper(BillBrand(qr: MemoryImage(_pixel), qrCaption: 'Scan to pay')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scan to pay'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the code takes the same share of the paper as the printed one', (
    tester,
  ) async {
    // 0.62 — the ratio bake_image.dart gives it on thermal paper and the web
    // receipt uses on screen. All three have to agree or a guest comparing the
    // slip to the phone sees two different documents.
    await tester.pumpWidget(_paper(BillBrand(qr: MemoryImage(_pixel))));
    await tester.pumpAndSettle();

    final box = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(box.widthFactor, closeTo(0.62, 0.001));
  });

  testWidgets('no QR uploaded, no QR block — a guest is looking at this', (
    tester,
  ) async {
    await tester.pumpWidget(_paper(const BillBrand.none()));
    await tester.pumpAndSettle();

    expect(find.byType(FractionallySizedBox), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Settings'), findsNothing);
  });

  testWidgets('the logo sits above the name, capped so it cannot take over', (
    tester,
  ) async {
    await tester.pumpWidget(_paper(BillBrand(logo: MemoryImage(_pixel))));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    final constrained = tester.widget<ConstrainedBox>(
      find
          .ancestor(
            of: find.byType(Image),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(constrained.constraints.maxHeight, 64);
  });

  testWidgets('a slip with nothing written on it still says thank you', (
    tester,
  ) async {
    await tester.pumpWidget(_paper(const BillBrand.none()));
    await tester.pumpAndSettle();

    expect(find.text('Thank you!'), findsOneWidget);
  });

  testWidgets("the restaurant's own words replace it, terms and all", (
    tester,
  ) async {
    await tester.pumpWidget(
      _paper(
        const BillBrand(
          footer: 'See you again',
          terms: 'No refunds after 24 hours.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thank you!'), findsNothing);
    expect(find.text('See you again'), findsOneWidget);
    expect(find.text('No refunds after 24 hours.'), findsOneWidget);
  });

  testWidgets('an image that will not load leaves a placeholder on screen', (
    tester,
  ) async {
    // Every network request in a widget test answers 400, which is exactly the
    // failure this has to survive.
    await tester.pumpWidget(
      _paper(BillBrand(qr: brandImage('https://example.test/qr.png'))),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });

  testWidgets('but leaves nothing at all in a picture sent to a guest', (
    tester,
  ) async {
    // A broken-image glyph where a payment code belongs reads as a scam.
    await tester.pumpWidget(
      _paper(
        BillBrand(qr: brandImage('https://example.test/qr.png')),
        forExport: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
  });

  testWidgets('a receipt sent from a phone in dark mode is still on paper', (
    tester,
  ) async {
    // The one regression that is invisible in review and unmistakable to a
    // guest: drop the light-theme wrap or the opaque background in
    // `exportFrame`, and what lands in their chat is a black slip, or one with
    // transparent margins that go black in their messenger. The ambient theme
    // here is dark on purpose.
    tester.view.physicalSize = const Size(380, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => exportFrame(
              context: context,
              boundaryKey: const ValueKey('export'),
              document: BillPaper(
                snapshot: _snapshot(),
                currency: 'NPR',
                shopName: 'The Sekuwa Station',
                brand: const BillBrand(footer: 'See you again'),
                forExport: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('export')),
      matchesGoldenFile('goldens/receipt_export.png'),
    );
  });
}
