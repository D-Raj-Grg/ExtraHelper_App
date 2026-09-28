import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/tokens.dart';

/// Scan a barcode and return the code, or null if the user backed out.
///
/// The camera is an accelerator, never a gate: everything reachable from here is
/// also reachable by typing into the search box, so a denied permission, a dead
/// camera or an unlabelled shelf all degrade to the same working screen.
///
/// The words around the frame are the caller's: the store room says "item
/// label", the checkout says "coupon". The square is the same.
Future<String?> showScannerSheet(
  BuildContext context, {
  String title = 'Scan an item label',
  String hint =
      'Hold the code inside the frame. No label on the shelf? Close this '
      'and search by name instead.',
  String fallbackHint = 'Searching by name works either way.',
  List<BarcodeFormat>? formats,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ScannerSheet(
    title: title,
    hint: hint,
    fallbackHint: fallbackHint,
    formats: formats,
  ),
);

class _ScannerSheet extends StatefulWidget {
  const _ScannerSheet({
    required this.title,
    required this.hint,
    required this.fallbackHint,
    this.formats,
  });

  final String title;
  final String hint;

  /// What to do when the camera is off — appended to the denied-permission
  /// message so it names the way round it for *this* screen.
  final String fallbackHint;

  /// Null = every format the store room needs. A coupon sheet narrows it to
  /// QR so a product barcode on the counter is not read as a code.
  final List<BarcodeFormat>? formats;

  @override
  State<_ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<_ScannerSheet> {
  /// The controller is owned and disposed here — the same rule the void-reason
  /// dialog exists to enforce, and a camera left running is worse than a leaked
  /// text controller.
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats:
        widget.formats ??
        const [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.code128,
          BarcodeFormat.qrCode,
        ],
  );

  /// One scan per sheet. Without this the detector fires again while the pop is
  /// still animating and the caller is handed a second code it never asked for.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((v) => v.trim().isNotEmpty)
        .firstOrNull;
    if (code == null) return;
    _handled = true;
    Navigator.of(context).pop(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_scanner),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.radiusLg),
              child: SizedBox(
                height: 280,
                width: double.infinity,
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  // A permission the user declined is a state, not a crash.
                  errorBuilder: (context, error) => _ScannerUnavailable(
                    error: error,
                    fallbackHint: widget.fallbackHint,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(widget.hint, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// No camera, or no permission for it. Says which, and says the way round it.
class _ScannerUnavailable extends StatelessWidget {
  const _ScannerUnavailable({required this.error, required this.fallbackHint});

  final MobileScannerException error;
  final String fallbackHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                denied
                    ? Icons.no_photography_outlined
                    : Icons.videocam_off_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                denied ? 'Camera access is off' : "The camera didn't start",
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                denied
                    ? 'Turn the camera on for ExtraHelper in your phone settings '
                          'to scan. $fallbackHint'
                    : 'Close this and carry on by hand — nothing here needs '
                          'the camera.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
