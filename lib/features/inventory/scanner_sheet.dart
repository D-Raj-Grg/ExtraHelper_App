import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/tokens.dart';

/// Scan a barcode and return the code, or null if the user backed out.
///
/// The camera is an accelerator, never a gate: everything reachable from here is
/// also reachable by typing into the search box, so a denied permission, a dead
/// camera or an unlabelled shelf all degrade to the same working screen.
Future<String?> showScannerSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ScannerSheet(),
    );

class _ScannerSheet extends StatefulWidget {
  const _ScannerSheet();

  @override
  State<_ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<_ScannerSheet> {
  /// The controller is owned and disposed here — the same rule the void-reason
  /// dialog exists to enforce, and a camera left running is worse than a leaked
  /// text controller.
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
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
                  child: Text(
                    'Scan an item label',
                    style: theme.textTheme.titleMedium,
                  ),
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
                  errorBuilder: (context, error) =>
                      _ScannerUnavailable(error: error),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Hold the code inside the frame. No label on the shelf? Close this '
              'and search by name instead.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// No camera, or no permission for it. Says which, and says the way round it.
class _ScannerUnavailable extends StatelessWidget {
  const _ScannerUnavailable({required this.error});

  final MobileScannerException error;

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
                          'to scan labels. Searching by name works either way.'
                    : 'Close this and search by name — nothing here needs the '
                          'camera.',
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
