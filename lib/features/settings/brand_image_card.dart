import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/print/bake_image.dart';
import '../../data/print/print_bitmap.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/supabase/settings_repository.dart';
import '../tenant/tenant_providers.dart';
import 'settings_providers.dart';

/// The size the web refuses above. Same number here so a file accepted on a
/// laptop is accepted on a phone.
const _maxUploadBytes = 3 * 1024 * 1024;

/// Baking is milliseconds of tight pixel loops per roll width. On the UI
/// isolate that is a visible stall on the frame the picker closes.
Future<BakeResult> _bake(Uint8List bytes, String kind) =>
    compute((_BakeArgs args) => bakeAsset(args.bytes, args.kind),
        _BakeArgs(bytes, kind));

class _BakeArgs {
  const _BakeArgs(this.bytes, this.kind);

  final Uint8List bytes;
  final String kind;
}

/// One brand image — the logo, or the payment QR — with its upload and removal.
///
/// Both go through the same three steps the browser does: pick, bake for every
/// roll width, then attach. The bake is the reason this is not a plain file
/// upload: a thermal head cannot fetch a URL, so what actually prints is a
/// 1-bit bitmap prepared here and stored beside the picture.
class BrandImageCard extends ConsumerStatefulWidget {
  const BrandImageCard({
    super.key,
    required this.kind,
    required this.settings,
    required this.canEdit,
  });

  /// `logo` or `qr`.
  final String kind;
  final TenantSettings settings;
  final bool canEdit;

  @override
  ConsumerState<BrandImageCard> createState() => _BrandImageCardState();
}

class _BrandImageCardState extends ConsumerState<BrandImageCard> {
  bool _busy = false;

  bool get _isQr => widget.kind == 'qr';
  String get _noun => _isQr ? 'Payment QR' : 'Logo';
  String? get _url =>
      _isQr ? widget.settings.receipt.qrUrl : widget.settings.receipt.logoUrl;

  Future<void> _pick() async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || _busy) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Not resized here: the baker needs every pixel it can get, and a QR
      // downscaled twice loses modules the second time.
      requestFullMetadata: false,
    );
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    // Empty means "said nothing" — the partial-scan dialog can be cancelled,
    // which is not a failure and does not deserve a snackbar.
    var message = '';
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxUploadBytes) {
        throw PosFailure('$_noun must be under 3 MB.');
      }

      final baked = await _bake(bytes, widget.kind);

      if (baked.bytes > bakeByteBudget) {
        throw PosFailure(
          'That image is too detailed to store for printing. Try a simpler '
          'or smaller one.',
        );
      }

      // A QR that survives no roll width is not worth uploading: it would
      // print on every slip and scan on none of them.
      if (_isQr && baked.unscannable.length == bakeWidths.length) {
        throw const PosFailure(
          "This QR doesn't survive black-and-white printing. Try a larger or "
          'higher-contrast image.',
        );
      }

      if (!mounted) return;
      if (_isQr && baked.unscannable.isNotEmpty && !await _confirmPartial(baked)) {
        return;
      }

      final repo = ref.read(settingsRepositoryProvider(tenant.tenantId));
      final url = await repo.uploadBrandObject(
        kind: widget.kind,
        bytes: bytes,
        extension: picked.name.split('.').last,
        contentType: picked.mimeType,
      );
      await repo.attachBrandImage(
        kind: widget.kind,
        url: url,
        variants: baked.variants,
        // Read from what this screen loaded, and spread: the merge is shallow,
        // so a patch carrying only this kind deletes the other one.
        currentAssets: widget.settings.receipt.printAssets,
      );
      ref.invalidate(tenantSettingsProvider);
      message = '$_noun updated.';
    } on PosFailure catch (e) {
      message = e.message;
    } on BakeFailure catch (e) {
      message = e.message;
    } catch (_) {
      message = "Couldn't prepare that image for printing.";
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmPartial(BakeResult baked) async {
    final widths = baked.unscannable.map(_paperLabel).join(' and ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scans on some paper only'),
        content: Text(
          "Printed on $widths this QR doesn't scan back. It will work on the "
          'other roll widths. Use it anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use it'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _remove() async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove the $_noun?'),
        content: Text(
          _isQr
              ? 'Receipts stop carrying a code for guests to scan and pay.'
              : 'Receipts and tickets print without it from the next one on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    String message;
    try {
      final repo = ref.read(settingsRepositoryProvider(tenant.tenantId));
      // Object first, then the template: the bucket is public, so a URL left
      // pointing at a live object keeps serving a picture that was deleted.
      await repo.removeBrandObject(_url);
      await repo.detachBrandImage(
        kind: widget.kind,
        currentAssets: widget.settings.receipt.printAssets,
      );
      ref.invalidate(tenantSettingsProvider);
      message = '$_noun removed.';
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _paperLabel(int dots) => switch (dots) {
    384 => '58mm',
    416 => '76mm',
    _ => '80mm',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = _url;
    final widths = widget.settings.receipt.widthsFor(widget.kind);
    final prepared = (bakeWidths.map((d) => '$d').where(widths.contains))
        .map((d) => _paperLabel(int.parse(d)))
        .toList();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _noun,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isQr
                  ? 'Printed at the foot of a bill for guests to scan and pay.'
                  : 'Printed at the top of receipts and tickets.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Preview(url: url, busy: _busy),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        url == null
                            ? 'Nothing set.'
                            : prepared.isEmpty
                            // A picture with no baked bytes prints nothing:
                            // uploaded before the baking existed, or attached
                            // by hand. Say so rather than implying it works.
                            ? 'Uploaded, but not prepared for printing — '
                                  'upload it again to fix that.'
                            : 'Prepared for ${prepared.join(', ')} paper.',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (widget.canEdit) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _pick,
                              icon: const Icon(Icons.upload_outlined, size: 18),
                              label: Text(url == null ? 'Upload' : 'Replace'),
                            ),
                            if (url != null)
                              TextButton(
                                onPressed: _busy ? null : _remove,
                                child: const Text('Remove'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.url, required this.busy});

  final String? url;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 72,
      width: 72,
      decoration: BoxDecoration(
        // White regardless of theme: this is a preview of what hits paper, and
        // paper is white.
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: busy
          ? const Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : url == null
          ? Icon(Icons.image_outlined, color: theme.colorScheme.outline)
          : Image.network(
              url!,
              fit: BoxFit.contain,
              errorBuilder: (context, _, _) => Icon(
                Icons.broken_image_outlined,
                color: theme.colorScheme.outline,
              ),
            ),
    );
  }
}
