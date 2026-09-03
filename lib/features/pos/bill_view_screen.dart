import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/labels.dart';
import '../../core/format/money.dart';
import '../../core/format/when.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/print/reprint_actions.dart';
import '../../data/supabase/settings_repository.dart';
import '../../data/sync/sync_providers.dart';
import '../settings/settings_providers.dart';
import '../tenant/tenant_providers.dart';
import 'bill_export.dart';
import 'bill_grouping.dart';
import 'bill_models.dart';
import 'bill_providers.dart';
import 'checkout_screen.dart' show CheckoutErrorBlock, MoneyRow;
import 'earlier_day_mark.dart';

/// The bill as the guest will read it, before any paper is burnt.
///
/// Checkout is a set of levers; this is the document. Until now the phone could
/// print a bill it had never seen — the receipt template lives in TypeScript
/// (`lib/print/docs.ts`) and renders server-side, so the first look anyone got
/// at a slip was the slip itself. This screen lays the same figures out in the
/// same order, grouped the same way, so a cashier can check before printing.
///
/// Read-only on purpose. Every write stays on checkout: one screen commits
/// money, and it is not this one.
class BillViewScreen extends ConsumerStatefulWidget {
  const BillViewScreen({super.key, required this.billId});

  final String billId;

  @override
  ConsumerState<BillViewScreen> createState() => _BillViewScreenState();
}

class _BillViewScreenState extends ConsumerState<BillViewScreen> {
  bool _busy = false;

  /// Anchors the iPad share popover to the button that was tapped.
  final _shareKey = GlobalKey();

  /// The boundary the picture is taken from. On the off-screen copy, never the
  /// one in the list.
  final _exportKey = GlobalKey();

  /// Mounted only while a share is being taken.
  Widget? _exportChild;

  /// Branding for the document on screen. Starts empty and stays empty when
  /// the settings read fails — the figures are the point, the logo is not.
  BillBrand _brand = const BillBrand.none();

  /// Which template [_brand] was built from, so a rebuild does not re-fetch.
  String? _brandSource;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _sourceOf(ReceiptTemplate r) =>
      '${r.logoUrl}|${r.qrUrl}|${r.qrCaption}|${r.footer}|${r.terms}';

  /// Decode the restaurant's images once the settings row lands.
  ///
  /// Unawaited by the caller: a picture arriving late is fine, a document that
  /// waits for one is not.
  Future<void> _warmBrand(ReceiptTemplate receipt) async {
    final source = _sourceOf(receipt);
    if (_brandSource == source) return;
    _brandSource = source;
    final brand = await resolveBrand(context, receipt);
    if (!mounted || _brandSource != source) return;
    setState(() => _brand = brand);
  }

  /// The same two actions the checkout bar offers, calling the same functions.
  ///
  /// Printing an estimate is the one thing here that is not purely a read:
  /// `enqueue_print_job` stamps `bill_printed_at` and the total it went out
  /// with. So this re-reads afterwards exactly as checkout does — without it
  /// the button would go on saying "Print bill" after the slip was printed,
  /// and the screen would not know the guest is holding an old total. A
  /// receipt for a settled bill is history and stamps nothing.
  Future<void> _print({required bool paid}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = paid
          ? await reprintBill(ref, widget.billId)
          : await printBillEstimate(ref, widget.billId);
      if (!paid) {
        // Unawaited: a read must never hold up the person at the table.
        unawaited(
          ref.read(billSnapshotProvider(widget.billId).notifier).refresh(),
        );
      }
      _say(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Send the receipt as a picture of itself.
  ///
  /// Deliberately not gated on connectivity, unlike printing: the bill is
  /// already in hand and the picture is made on the device, so a cashier with
  /// no signal can still hand a guest their receipt over whatever messenger
  /// has a cached connection.
  Future<void> _share(BillSnapshot s, String currency, String shopName) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final receipt =
          ref.read(tenantSettingsProvider).valueOrNull?.receipt ??
          const ReceiptTemplate();
      // Resolved again here rather than reusing [_brand]: the screen's copy may
      // still be in flight, and a blank square is worse than a short wait.
      final brand = await resolveBrand(context, receipt);
      if (!mounted) return;

      setState(
        () => _exportChild = exportFrame(
          context: context,
          boundaryKey: _exportKey,
          document: BillPaper(
            snapshot: s,
            currency: currency,
            shopName: shopName,
            brand: brand,
            forExport: true,
          ),
        ),
      );
      // Two frames: one to build, lay out and paint the subtree just mounted,
      // one of slack so an image that resolved during the first is definitely
      // on the canvas before it is photographed.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final boundary =
          _exportKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw const BillExportFailure("Couldn't draw the receipt to send.");
      }
      final file = await writeReceiptPng(await capturePng(boundary), s.bill);
      if (!mounted) return;

      await ref.read(fileSharerProvider)(
        ShareRequest(
          file: file,
          text:
              '${s.bill.isPaid ? 'Receipt' : 'Bill'} '
              '#${s.bill.id.substring(0, 8).toUpperCase()}'
              '${shopName.isEmpty ? '' : ' · $shopName'}',
          origin: shareOriginOf(_shareKey),
        ),
      );

      // Said after the fact, not instead of sending: a receipt without the code
      // is still the receipt, but the cashier has to know the guest cannot scan
      // it before they walk away.
      if (BillBrand.qrExpected(receipt) && brand.qr == null) {
        _say('Sent without the payment QR — check your connection.');
      }
    } on BillExportFailure catch (e) {
      _say(e.message);
    } catch (e) {
      _say("Couldn't send the receipt.");
    } finally {
      if (mounted) {
        setState(() {
          _exportChild = null;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(billSnapshotProvider(widget.billId));
    final tenant = ref.watch(activeTenantProvider);
    final currency = tenant?.currency ?? 'USD';
    // Checkout disables printing offline rather than hiding it — a missing
    // button reads as "this bill cannot be printed", which is a different and
    // wronger thing. The same holds here.
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    // Watched, not listened to: the settings row is often already cached when
    // this screen opens, and a listener only fires on a *change*, so the first
    // bill of a session would render unbranded. Decoding is deferred to after
    // the frame so nothing writes state during build.
    final receipt = ref.watch(tenantSettingsProvider).valueOrNull?.receipt;
    if (receipt != null && _sourceOf(receipt) != _brandSource) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_warmBrand(receipt)),
      );
    }

    return AppScaffold(
      title: 'Bill',
      subtitle: snapshot.valueOrNull?.bill.tableLabel is String
          ? 'Table ${snapshot.valueOrNull!.bill.tableLabel}'
          : null,
      showDrawer: false,
      actions: [
        if (snapshot.valueOrNull case final s?)
          IconButton(
            key: _shareKey,
            // Available on a void bill too: a picture of a voided bill is
            // evidence, and the header stamps the status on it.
            onPressed: _busy
                ? null
                : () => _share(s, currency, tenant?.name ?? ''),
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share receipt',
          ),
      ],
      bottomNavigationBar: switch (snapshot.valueOrNull) {
        null => null,
        final s when s.bill.isVoid => null,
        final s => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: OutlinedButton.icon(
              onPressed: _busy || !online
                  ? null
                  : () => _print(paid: s.bill.isPaid),
              icon: const Icon(Icons.print_outlined, size: 18),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, Tokens.tapTarget),
              ),
              label: Text(
                s.bill.isPaid
                    ? 'Print receipt'
                    : s.bill.wasPrinted
                    ? 'Reprint bill'
                    : 'Print bill',
              ),
            ),
          ),
        ),
      },
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          RefreshIndicator(
            onRefresh: () => ref
                .read(billSnapshotProvider(widget.billId).notifier)
                .refresh(),
            child: snapshot.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(
                children: [
                  const SizedBox(height: 80),
                  CheckoutErrorBlock(
                    message: "Couldn't open that bill.",
                    detail: '$e',
                    onRetry: () =>
                        ref.invalidate(billSnapshotProvider(widget.billId)),
                  ),
                ],
              ),
              data: (s) => ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  BillPaper(
                    snapshot: s,
                    currency: currency,
                    shopName: tenant?.name ?? '',
                    brand: _brand,
                  ),
                ],
              ),
            ),
          ),
          // Off-screen, but inside a real Stack, so it is laid out and painted
          // — which is the whole trick. `Offstage`, `Visibility(false)` and
          // `Opacity(0)` all skip painting, and a boundary that was never
          // painted cannot be turned into an image. An ancestor clip does not
          // reach the boundary's own layer, so the picture is complete even
          // though none of this was ever on screen.
          if (_exportChild case final child?)
            Positioned(
              left: -kBillExportWidth - 100,
              top: 0,
              width: kBillExportWidth,
              child: child,
            ),
        ],
      ),
    );
  }
}

/// The document itself — no scroller, no viewport.
///
/// Public and unscrolled on purpose: the export in `bill_export.dart` mounts
/// **this same widget** off-screen and photographs it, so what a guest is sent
/// is the document a cashier just looked at rather than a second rendering of
/// it that can drift. Sized by its parent's width, unbounded in height.
class BillPaper extends StatelessWidget {
  const BillPaper({
    super.key,
    required this.snapshot,
    required this.currency,
    required this.shopName,
    this.brand = const BillBrand.none(),
    this.forExport = false,
  });

  final BillSnapshot snapshot;
  final String currency;
  final String shopName;

  /// The restaurant's logo and payment QR, already resolved. Empty until the
  /// settings read lands, and empty forever offline — branding is a nicety and
  /// must never hold up the figures.
  final BillBrand brand;

  /// Whether this is being photographed rather than looked at. Only changes
  /// what a *failed* image leaves behind: a placeholder on screen, nothing at
  /// all in the picture — a broken-image glyph on a guest's receipt reads as a
  /// scam.
  final bool forExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bill = snapshot.bill;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        // Paper, not a card: a surface the eye reads as the document itself, so
        // what's on screen and what comes out of the printer are obviously the
        // same object.
        color: scheme.surface,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            snapshot: snapshot,
            shopName: shopName,
            brand: brand,
            forExport: forExport,
          ),
          const Divider(height: 22),
          _Particulars(snapshot: snapshot, currency: currency),
          const Divider(height: 22),
          _Totals(snapshot: snapshot, currency: currency),
          if (snapshot.payments.isNotEmpty) ...[
            const Divider(height: 22),
            _Payments(snapshot: snapshot, currency: currency),
          ],
          if (snapshot.customer != null || bill.note != null) ...[
            const Divider(height: 22),
            if (snapshot.customer != null)
              Text(
                '${snapshot.customer!.label} · '
                '${snapshot.customer!.points} pts',
                style: theme.textTheme.bodySmall,
              ),
            if (bill.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  bill.note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
          _PayHere(brand: brand, forExport: forExport),
          _Sign(brand: brand),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.snapshot,
    required this.shopName,
    required this.brand,
    required this.forExport,
  });

  final BillSnapshot snapshot;
  final String shopName;
  final BillBrand brand;
  final bool forExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semantic;
    final bill = snapshot.bill;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (brand.logo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BrandImage(
              image: brand.logo!,
              // Capped, not sized: a logo is whatever shape the restaurant
              // gave us, and the name under it is what identifies the bill.
              constraints: const BoxConstraints(maxHeight: 64),
              forExport: forExport,
            ),
          ),
        if (shopName.isNotEmpty)
          Text(
            shopName,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        Text(
          bill.isPaid ? 'Receipt' : 'Bill',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // The same eight characters the web prints and the status
                    // band on checkout shows. A guest querying a charge quotes
                    // this, so all three have to agree.
                    'Invoice no: #${bill.id.substring(0, 8).toUpperCase()}',
                    style: (theme.textTheme.bodySmall ?? const TextStyle())
                        .tabular,
                  ),
                  if (bill.tableLabel != null)
                    Text(
                      'Table ${bill.tableLabel}',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (snapshot.waiterName != null)
                    Text(
                      'Served by ${snapshot.waiterName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Flexible, not bare: a date at double text size is wider than
            // whatever the invoice number leaves behind, and an unconstrained
            // column runs straight off the paper.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    billDateTime(bill.createdAt),
                    textAlign: TextAlign.end,
                    style: (theme.textTheme.bodySmall ?? const TextStyle())
                        .tabular,
                  ),
                  Text(
                    billStatusLabel(bill.status),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: bill.isVoid
                          ? semantic.neutral
                          : bill.isPaid
                          ? semantic.goodText
                          : semantic.infoText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        EarlierDayMark(
          at: bill.createdAt,
          padding: const EdgeInsets.only(top: 8),
        ),
      ],
    );
  }
}

class _Particulars extends StatelessWidget {
  const _Particulars({required this.snapshot, required this.currency});

  final BillSnapshot snapshot;
  final String currency;

  /// Above this, the four-column table stops fitting on a 320dp phone and the
  /// rows go stacked instead. Columns are a nicety; a legible price is not.
  static const _stackAbove = 1.3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final head = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final rows = groupBillLines(snapshot.lines);

    if (rows.isEmpty) {
      return Text('Nothing on this bill.', style: theme.textTheme.bodySmall);
    }

    // Someone running their phone at double text size is doing it because they
    // need to; taking their price column away to keep a table shape would be
    // the wrong half to save.
    final stacked = scaler.scale(1) > _stackAbove;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!stacked) ...[
          Row(
            children: [
              Expanded(child: Text('Particulars', style: head)),
              _Cell(
                width: scaler.scale(34),
                child: Text('Qty', style: head, textAlign: TextAlign.right),
              ),
              _Cell(
                width: scaler.scale(82),
                child: Text('Rate', style: head, textAlign: TextAlign.right),
              ),
              const SizedBox(width: 8),
              Text('Amount', style: head, textAlign: TextAlign.right),
            ],
          ),
          const SizedBox(height: 6),
        ],
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.description, style: theme.textTheme.bodyMedium),
                      for (final m in row.modifiers)
                        Text(
                          '↳ ${m.name}${m.qty > 1 ? ' ×${m.qty}' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      // Stacked, the quantity and rate move under the name —
                      // the same shape the checkout card uses, which is where
                      // the eye already expects them.
                      if (stacked)
                        Text(
                          '${row.qty} × ${money(row.unitPriceCents, currency)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!stacked) ...[
                  _Cell(
                    width: scaler.scale(34),
                    child: Text(
                      '${row.qty}',
                      textAlign: TextAlign.right,
                      style: (theme.textTheme.bodyMedium ?? const TextStyle())
                          .tabular,
                    ),
                  ),
                  _Cell(
                    width: scaler.scale(82),
                    child: Text(
                      money(row.unitPriceCents, currency),
                      textAlign: TextAlign.right,
                      style: (theme.textTheme.bodySmall ?? const TextStyle())
                          .tabular,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // The amount is never a fixed cell: it is the figure a guest
                // checks, so it takes the width it needs, and wraps rather
                // than clips when the text size grows.
                Flexible(
                  child: Text(
                    money(row.totalCents, currency),
                    textAlign: TextAlign.right,
                    style: (theme.textTheme.bodyMedium ?? const TextStyle())
                        .tabular,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A column cell that keeps its width in step with the user's text size, so a
/// scaled-up price is never clipped by a number chosen at 1×.
class _Cell extends StatelessWidget {
  const _Cell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: child);
}

/// Same rows, same order, same "a zero line is not a line" rule as checkout's
/// totals card — the two must never disagree about what a bill comes to.
class _Totals extends StatelessWidget {
  const _Totals({required this.snapshot, required this.currency});

  final BillSnapshot snapshot;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final bill = snapshot.bill;
    return Column(
      children: [
        MoneyRow(
          label: 'Item total',
          cents: snapshot.itemTotalCents,
          currency: currency,
          muted: true,
        ),
        MoneyRow(
          label: 'Sub total',
          cents: bill.subtotalCents,
          currency: currency,
        ),
        if (bill.serviceChargeCents > 0)
          MoneyRow(
            label: 'Service + packaging',
            cents: bill.serviceChargeCents,
            currency: currency,
            muted: true,
          ),
        if (bill.taxCents > 0)
          MoneyRow(
            label: 'Tax',
            cents: bill.taxCents,
            currency: currency,
            muted: true,
          ),
        for (final c in snapshot.charges)
          MoneyRow(
            label: c.label,
            cents: c.amountCents,
            currency: currency,
            muted: true,
          ),
        if (bill.discountCents > 0)
          MoneyRow(
            label: 'Discount',
            cents: -bill.discountCents,
            currency: currency,
            muted: true,
          ),
        if (bill.tipCents > 0)
          MoneyRow(
            label: 'Tip',
            cents: bill.tipCents,
            currency: currency,
            muted: true,
          ),
        if (bill.roundingCents != 0)
          MoneyRow(
            label: 'Round off',
            cents: bill.roundingCents,
            currency: currency,
            muted: true,
          ),
        const Divider(height: 18),
        MoneyRow(
          label: 'Total',
          cents: bill.totalCents,
          currency: currency,
          strong: true,
        ),
      ],
    );
  }
}

class _Payments extends StatelessWidget {
  const _Payments({required this.snapshot, required this.currency});

  final BillSnapshot snapshot;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in snapshot.payments)
          MoneyRow(
            label:
                '${paymentMethodLabel(p.method)} · ${clockTime(p.createdAt)}',
            cents: p.amountCents,
            currency: currency,
            muted: true,
          ),
        MoneyRow(
          label: snapshot.dueCents <= 0 ? 'Settled' : 'Due',
          cents: snapshot.dueCents <= 0 ? 0 : snapshot.dueCents,
          currency: currency,
          strong: true,
        ),
        if (snapshot.bill.isVoid)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'This bill was voided.',
              style: theme.textTheme.labelMedium,
            ),
          ),
      ],
    );
  }
}

/// Scan to pay.
///
/// The web receipt and the printed slip both carry this; without it a cashier
/// standing at the table has nothing to hold out. The code itself is whatever
/// image the restaurant uploaded from their payment provider — nothing here
/// builds a payment payload, on this client or the web.
///
/// Absent when there is no QR: no placeholder, no "set one up" nudge. A guest
/// is looking at this.
class _PayHere extends StatelessWidget {
  const _PayHere({required this.brand, required this.forExport});

  final BillBrand brand;
  final bool forExport;

  /// The same fraction of the paper the thermal slip gives it
  /// (`bake_image.dart`) and the web receipt uses, so the code is the same size
  /// on screen, on paper and in a shared picture.
  static const _widthRatio = 0.62;

  @override
  Widget build(BuildContext context) {
    final qr = brand.qr;
    if (qr == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 22),
        if (brand.qrCaption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              brand.qrCaption,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Align(
          child: FractionallySizedBox(
            widthFactor: _widthRatio,
            child: AspectRatio(
              aspectRatio: 1,
              child: _BrandImage(image: qr, forExport: forExport),
            ),
          ),
        ),
      ],
    );
  }
}

/// The last thing on the slip. "Thank you!" when the restaurant has not written
/// anything — the same fallback the web receipt uses, so the two end alike.
class _Sign extends StatelessWidget {
  const _Sign({required this.brand});

  final BillBrand brand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 22),
        Text(
          brand.footer.isEmpty ? 'Thank you!' : brand.footer,
          textAlign: TextAlign.center,
          style: style,
        ),
        if (brand.terms.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(brand.terms, textAlign: TextAlign.center, style: style),
          ),
      ],
    );
  }
}

/// A restaurant's own image on the document.
///
/// On screen a failure leaves the house placeholder. In an exported picture it
/// leaves **nothing**: a broken-image glyph where a guest expects a payment
/// code reads as a scam, and an absent one reads as a receipt without a QR,
/// which is what it is.
class _BrandImage extends StatelessWidget {
  const _BrandImage({
    required this.image,
    required this.forExport,
    this.constraints,
  });

  final ImageProvider image;
  final bool forExport;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final picture = Image(
      image: image,
      fit: BoxFit.contain,
      errorBuilder: (context, _, _) => forExport
          ? const SizedBox.shrink()
          : Icon(
              Icons.image_not_supported_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
    );
    if (constraints == null) return picture;
    return ConstrainedBox(constraints: constraints!, child: picture);
  }
}
