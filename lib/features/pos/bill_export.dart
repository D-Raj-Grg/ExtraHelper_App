import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/share/share_plus_sharer.dart';
import '../../data/supabase/settings_repository.dart';
import 'bill_models.dart';

/// Sending the receipt, as a picture of the document itself.
///
/// The receipt template lives in TypeScript and renders server-side — that is
/// deliberate, so paper and web can never disagree about a bill. A second Dart
/// renderer would be a third opinion, so this photographs `BillPaper`, the very
/// widget the cashier is looking at, and shares the PNG. Nothing here decides
/// what a receipt says; it only decides how big the picture is.

/// Logical width the document is exported at.
///
/// Fixed rather than "whatever this device is", so the picture sent from a
/// tablet and the one sent from a phone are the same document.
const double kBillExportWidth = 380;

/// Target pixel width: 380 × 3, sharp enough that a payment QR photographed off
/// the picture still scans.
const double kBillExportTargetPx = 1140;

/// Ceiling on either dimension. Older Android GPUs refuse a texture much past
/// this, and a long bill should lose sharpness rather than fail to send.
const double kBillExportMaxPx = 4096;

/// How long an exported file is kept before the next export sweeps it.
const Duration kReceiptTtl = Duration(hours: 6);

/// A share that could not be produced. One thing for the screen to catch.
class BillExportFailure implements Exception {
  const BillExportFailure(this.message);

  /// A sentence to put in front of the cashier, not a stack trace.
  final String message;

  @override
  String toString() => message;
}

/// The branding the document was actually able to draw.
///
/// A URL that did not come down is simply **not here**. Absence is the whole
/// design: the receipt renders without it rather than with a grey placeholder
/// where a guest expects a payment code.
class BillBrand {
  const BillBrand({
    this.logo,
    this.qr,
    this.qrCaption = '',
    this.footer = '',
    this.terms = '',
  });

  const BillBrand.none()
    : logo = null,
      qr = null,
      qrCaption = '',
      footer = '',
      terms = '';

  final ImageProvider? logo;
  final ImageProvider? qr;
  final String qrCaption;

  /// Text, so unlike the images these survive a failed fetch — they came down
  /// with the settings row, not over a second request.
  final String footer;
  final String terms;

  /// Whether the tenant asked for a QR and we have it. Drives the one honest
  /// sentence the cashier gets when a share goes out without it.
  static bool qrExpected(ReceiptTemplate receipt) =>
      (receipt.qrUrl ?? '').isNotEmpty;
}

/// The one way a brand image is named.
///
/// `NetworkImage` keys the image cache on `(url, scale)`, so the screen and the
/// export have to build the provider identically or the precache is a miss and
/// the picture comes out blank. Everything goes through here.
ImageProvider brandImage(String url) => NetworkImage(url);

/// Decode the logo and QR **before** the document is painted.
///
/// [precacheImage] completes normally when a fetch fails unless `onError`
/// rethrows, so a plain await would report success and export a blank square.
Future<BillBrand> resolveBrand(
  BuildContext context,
  ReceiptTemplate receipt, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final logo = await _warm(context, receipt.logoUrl, timeout);
  if (!context.mounted) return const BillBrand.none();
  final qr = await _warm(context, receipt.qrUrl, timeout);
  return BillBrand(
    logo: logo,
    qr: qr,
    qrCaption: receipt.qrCaption,
    footer: receipt.footer,
    terms: receipt.terms,
  );
}

Future<ImageProvider?> _warm(
  BuildContext context,
  String? url,
  Duration timeout,
) async {
  if (url == null || url.isEmpty) return null;
  final provider = brandImage(url);
  try {
    await precacheImage(
      provider,
      context,
      onError: (error, _) => throw error,
    ).timeout(timeout);
    return provider;
  } catch (_) {
    // Offline, a 404, an expired URL, a file that isn't an image. All the same
    // answer: the document goes out without it.
    return null;
  }
}

/// How many device pixels per logical one the capture can afford.
///
/// Width sets the quality; height sets the ceiling. A tall bill degrades in
/// sharpness instead of throwing, which is the trade a cashier would pick.
double exportPixelRatio(Size logical) {
  if (logical.width <= 0 || logical.height <= 0) return 1;
  final byWidth = kBillExportTargetPx / logical.width;
  final byHeight = kBillExportMaxPx / logical.height;
  return math.min(byWidth, byHeight).clamp(1.0, 3.0);
}

/// Encode an already-painted boundary as PNG bytes.
///
/// Painted is the operative word: `toImage` converts the layer the boundary
/// last recorded, so a boundary a viewport never painted throws. See the
/// off-screen host in `bill_view_screen.dart` for why it is not in the list.
Future<Uint8List> capturePng(RenderRepaintBoundary boundary) async {
  if (boundary.debugNeedsPaint) {
    throw const BillExportFailure("Couldn't draw the receipt to send.");
  }
  ui.Image image;
  try {
    image = await boundary.toImage(pixelRatio: exportPixelRatio(boundary.size));
  } catch (_) {
    // A refused texture is worth one honest retry at the smallest size before
    // telling someone their receipt cannot be sent.
    try {
      image = await boundary.toImage(pixelRatio: 1);
    } catch (_) {
      throw const BillExportFailure(
        'This receipt is too long to send as an image. Print it instead.',
      );
    }
  }
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const BillExportFailure("Couldn't draw the receipt to send.");
    }
    return data.buffer.asUint8List();
  } finally {
    // Tens of megabytes for a long bill. Not optional.
    image.dispose();
  }
}

/// `receipt-1A2B3C4D-20260813-1942.png`.
///
/// The name lands in the recipient's chat and in their downloads, so it carries
/// the same eight invoice characters the slip, checkout and this screen show —
/// a guest querying a charge quotes those.
String receiptFileName(Bill bill) {
  final at = bill.createdAt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${at.year}${two(at.month)}${two(at.day)}-${two(at.hour)}${two(at.minute)}';
  final invoice = bill.id.length >= 8
      ? bill.id.substring(0, 8).toUpperCase()
      : bill.id.toUpperCase();
  return 'receipt-$invoice-$stamp.png';
}

/// Write the picture somewhere a share sheet can reach it.
///
/// The cache directory, not documents: documents is the drift database's home
/// and is backed up to iCloud, and a receipt is a thing in flight, not a thing
/// kept.
Future<File> writeReceiptPng(Uint8List png, Bill bill) async {
  final dir = Directory(
    p.join((await getTemporaryDirectory()).path, 'receipts'),
  );
  await dir.create(recursive: true);
  await sweepOldReceipts(dir);
  final file = File(p.join(dir.path, receiptFileName(bill)));
  await file.writeAsBytes(png, flush: true);
  return file;
}

/// Delete receipts older than [kReceiptTtl], on the way *in* to a new export.
///
/// Never after sharing: Android hands the receiver a content URI backed by this
/// exact file and the messaging app reads it lazily, so deleting on the way out
/// races the send and puts a broken attachment in someone's chat.
Future<void> sweepOldReceipts(Directory dir, {DateTime? now}) async {
  final cutoff = (now ?? DateTime.now()).subtract(kReceiptTtl);
  try {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        // Sync stat: the async one is slower here, and this loop runs over a
        // handful of files while a cashier waits to send a receipt.
        if (entity.statSync().modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {
        // A file someone else is holding. Leave it; it will age out again.
      }
    }
  } catch (_) {
    // A failed tidy-up must never fail a share.
  }
}

/// The document as it leaves the phone.
///
/// Three wraps, each fixing something a guest would otherwise receive: the text
/// scale is pinned because the particulars restack above 1.3× and a cashier
/// reading at 2× would send a layout that reads nothing like a receipt; the
/// theme is forced light because a dark-mode capture is a black slip; the
/// background is painted because a `RepaintBoundary` keeps its alpha and
/// transparent margins go black again in a messenger's dark mode.
///
/// Takes the document as a child so this file never has to know what a bill
/// looks like — that stays in one widget.
Widget exportFrame({
  required BuildContext context,
  required Key boundaryKey,
  required Widget document,
}) => RepaintBoundary(
  key: boundaryKey,
  child: MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.noScaling,
      devicePixelRatio: 1,
      padding: EdgeInsets.zero,
      viewInsets: EdgeInsets.zero,
      viewPadding: EdgeInsets.zero,
    ),
    child: Theme(
      data: AppTheme.light(),
      child: ColoredBox(
        color: Tokens.lightBackground,
        child: Padding(padding: const EdgeInsets.all(16), child: document),
      ),
    ),
  ),
);

/// One file, on its way out of the app.
class ShareRequest {
  const ShareRequest({
    required this.file,
    required this.text,
    required this.origin,
  });

  final File file;
  final String text;

  /// Where the sheet should point on iPad, in global logical pixels. iPadOS
  /// presents the share sheet as a popover and raises without a source rect.
  final Rect origin;
}

typedef FileSharer = Future<bool> Function(ShareRequest request);

/// The seam. Overridden in tests; the real one is the app's only import of
/// `share_plus`, so a widget test never drags a platform channel in.
final fileSharerProvider = Provider<FileSharer>((ref) => sharePlusSharer);

/// The global rect of the widget behind [key].
///
/// Falls back to a degenerate rect rather than null: null is precisely what
/// crashes on iPad.
Rect shareOriginOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return const Rect.fromLTWH(0, 0, 1, 1);
  return box.localToGlobal(Offset.zero) & box.size;
}
