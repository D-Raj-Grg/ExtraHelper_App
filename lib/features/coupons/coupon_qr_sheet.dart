import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:zxing2/qrcode.dart';

import '../../core/env.dart';
import '../../core/theme/tokens.dart';
import '../../data/supabase/coupons_repository.dart';
import '../pos/bill_export.dart';
import '../tenant/tenant_providers.dart';
import 'coupon_status.dart';

/// The flyer square for one coupon: hold the phone up for a guest to scan,
/// copy the link, or send the picture to whoever prints the flyers.
///
/// Printing itself stays on the web (Insights → Coupons → Print); the phone
/// has no page printer, only the receipt printer.
Future<void> showCouponQrSheet(
  BuildContext context, {
  required Coupon coupon,
  required String currency,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _CouponQrSheet(coupon: coupon, currency: currency),
);

class _CouponQrSheet extends ConsumerStatefulWidget {
  const _CouponQrSheet({required this.coupon, required this.currency});

  final Coupon coupon;
  final String currency;

  @override
  ConsumerState<_CouponQrSheet> createState() => _CouponQrSheetState();
}

class _CouponQrSheetState extends ConsumerState<_CouponQrSheet> {
  final _exportKey = GlobalKey();
  final _shareKey = GlobalKey();
  Widget? _exportChild;
  bool _busy = false;
  bool _copied = false;

  /// Fixed for the sheet's life: nothing it depends on changes while a
  /// coupon is on screen, and the grid is the expensive part.
  late final String _payload;
  late final List<List<bool>> _grid;

  @override
  void initState() {
    super.initState();
    _payload = couponQrPayload(
      origin: Env.appUrl,
      slug: ref.read(activeTenantProvider)?.slug ?? '',
      code: widget.coupon.code,
    );
    _grid = qrModules(_payload);
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _payload));
      if (mounted) setState(() => _copied = true);
    } catch (_) {
      _say("Couldn't copy — long-press the code instead.");
    }
  }

  /// Photograph the card and hand the PNG to the share sheet — the same
  /// path a receipt takes, so it works with no signal.
  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      setState(
        () => _exportChild = exportFrame(
          context: context,
          boundaryKey: _exportKey,
          document: _QrCard(
            coupon: widget.coupon,
            currency: widget.currency,
            payload: _payload,
            grid: _grid,
            forExport: true,
          ),
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final boundary =
          _exportKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw const BillExportFailure("Couldn't draw the QR to send.");
      }
      final png = await capturePng(boundary);
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'coupons'),
      );
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'coupon-${widget.coupon.code}.png'));
      await file.writeAsBytes(png, flush: true);
      if (!mounted) return;

      await ref.read(fileSharerProvider)(
        ShareRequest(
          file: file,
          text:
              '${widget.coupon.code} · '
              '${couponSummary(widget.coupon, widget.currency)}',
          origin: shareOriginOf(_shareKey),
        ),
      );
    } on BillExportFailure catch (e) {
      _say(e.message);
    } catch (_) {
      _say("Couldn't send the QR.");
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
    final theme = Theme.of(context);
    final c = widget.coupon;
    final linked = _payload != c.code;
    return SafeArea(
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Flyer QR',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  linked
                      ? 'Scanning opens your online menu with the code already '
                            'in. Staff can scan it at checkout too.'
                      : 'Scanning gives the bare code — set APP_URL and a '
                            'storefront slug for a menu link.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: _QrCard(
                    coupon: c,
                    currency: widget.currency,
                    payload: _payload,
                    grid: _grid,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _copy,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, Tokens.tapTarget),
                        ),
                        icon: Icon(_copied ? Icons.check : Icons.link),
                        label: Text(_copied ? 'Copied' : 'Copy link'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        key: _shareKey,
                        onPressed: _busy ? null : _share,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, Tokens.tapTarget),
                        ),
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Off-screen but inside a real Stack, so it is laid out and painted
          // — `Offstage` skips paint and `toImage` would find nothing. Same
          // trick as the receipt share in `bill_view_screen.dart`.
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

/// The square with the code and the rules under it — what a guest sees on
/// the phone and what the shared PNG contains.
class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.coupon,
    required this.currency,
    required this.payload,
    required this.grid,
    this.forExport = false,
  });

  final Coupon coupon;
  final String currency;
  final String payload;
  final List<List<bool>> grid;
  final bool forExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: forExport ? kBillExportWidth : 280,
      padding: const EdgeInsets.all(20),
      // Pure white ground and pure black modules on purpose: a camera wants
      // maximum contrast, and the card must look the same in dark mode as in
      // the PNG it becomes. The text uses the light-theme ink tokens.
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrSquare(payload: payload, grid: grid, size: forExport ? 300 : 220),
          const SizedBox(height: 14),
          Text(
            coupon.code,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Tokens.lightForeground,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            couponSummary(coupon, currency),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Tokens.lightForeground,
            ),
          ),
          if (coupon.name != null) ...[
            const SizedBox(height: 2),
            Text(
              coupon.name!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

/// A QR drawn from `zxing2`'s encoder — no image package, no network. Quiet
/// zone is four modules, the spec minimum, so a camera finds the edges.
class QrSquare extends StatelessWidget {
  const QrSquare({
    super.key,
    required this.payload,
    required this.grid,
    required this.size,
  });

  /// What [grid] encodes — for the accessibility label only.
  final String payload;

  /// From [qrModules], computed once by the owner: encoding is not free and
  /// a rebuild for a snackbar should not redo it.
  final List<List<bool>> grid;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (grid.isEmpty) return SizedBox.square(dimension: size);
    return Semantics(
      label: 'QR code for $payload',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _QrPainter(grid)),
      ),
    );
  }
}

/// The dark modules of [payload], row by row. Empty when the encoder
/// declines (it never does for a URL this short; the guard is for the test
/// that hands it nonsense).
List<List<bool>> qrModules(String payload) {
  final matrix = Encoder.encode(payload, ErrorCorrectionLevel.m).matrix;
  if (matrix == null) return const [];
  return [
    for (var y = 0; y < matrix.height; y++)
      [for (var x = 0; x < matrix.width; x++) matrix.get(x, y) == 1],
  ];
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.grid);

  final List<List<bool>> grid;

  static const _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final modules = grid.length + _quiet * 2;
    final cell = size.width / modules;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final ink = Paint()..color = Colors.black;
    for (var y = 0; y < grid.length; y++) {
      for (var x = 0; x < grid[y].length; x++) {
        if (!grid[y][x]) continue;
        // Overdraw by a hair so antialiasing never leaves white seams.
        canvas.drawRect(
          Rect.fromLTWH(
            (x + _quiet) * cell,
            (y + _quiet) * cell,
            cell + 0.5,
            cell + 0.5,
          ),
          ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.grid != grid;
}
