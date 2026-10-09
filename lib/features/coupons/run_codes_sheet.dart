import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/notice.dart';
import '../../data/supabase/coupon_batches_repository.dart';
import '../../data/supabase/coupons_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../pos/bill_export.dart';
import '../tenant/tenant_providers.dart';
import 'coupon_qr_sheet.dart';
import 'coupon_status.dart';
import 'coupons_providers.dart';
import 'flyer_export.dart';

/// Every code of one run, with who has it. Copy the list or send it as a CSV
/// to whoever prints; tap a code for its QR; note a flyer as handed out.
Future<void> showRunCodesSheet(
  BuildContext context, {
  required CouponBatch batch,
  required String currency,
  required bool canManage,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.85,
    minChildSize: 0.5,
    maxChildSize: 0.95,
    builder: (_, scroll) => _RunCodesSheet(
      batch: batch,
      currency: currency,
      canManage: canManage,
      scroll: scroll,
    ),
  ),
);

enum _CodeState { used, paused, handedOut, free }

_CodeState _stateOf(BatchCode c) => c.redeemed
    ? _CodeState.used
    : !c.isActive
    ? _CodeState.paused
    : c.shared
    ? _CodeState.handedOut
    : _CodeState.free;

String _stateWord(_CodeState s) => switch (s) {
  _CodeState.used => 'Used',
  _CodeState.paused => 'Paused',
  _CodeState.handedOut => 'Handed out',
  _CodeState.free => 'Free',
};

/// One code per line with its state — what a printer or a spreadsheet wants.
String codesCsv(List<BatchCode> codes) {
  final b = StringBuffer('code,status\n');
  for (final c in codes) {
    b.writeln('${c.code},${_stateWord(_stateOf(c))}');
  }
  return b.toString();
}

class _RunCodesSheet extends ConsumerStatefulWidget {
  const _RunCodesSheet({
    required this.batch,
    required this.currency,
    required this.canManage,
    required this.scroll,
  });

  final CouponBatch batch;
  final String currency;
  final bool canManage;
  final ScrollController scroll;

  @override
  ConsumerState<_RunCodesSheet> createState() => _RunCodesSheetState();
}

class _RunCodesSheetState extends ConsumerState<_RunCodesSheet> {
  final _shareKey = GlobalKey();
  bool _busy = false;

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  CouponBatchesRepository? get _repo {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return null;
    return ref.read(couponBatchesRepositoryProvider(tenant.tenantId));
  }

  Future<void> _toggleShared(BatchCode c) async {
    final repo = _repo;
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    try {
      await repo.markShared(widget.batch.id, c.code, shared: !c.shared);
      ref.invalidate(batchCodesProvider(widget.batch.id));
    } on PosFailure catch (e) {
      _say(e.message);
    } catch (_) {
      _say("Couldn't reach the flyers.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyAll(List<BatchCode> codes) async {
    await Clipboard.setData(
      ClipboardData(text: codes.map((c) => c.code).join('\n')),
    );
    _say('${codes.length} codes copied.');
  }

  Future<void> _shareCsv(List<BatchCode> codes) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'coupons'),
      );
      await dir.create(recursive: true);
      final safe = widget.batch.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
      final file = File(p.join(dir.path, 'run-$safe.csv'));
      await file.writeAsString(codesCsv(codes), flush: true);
      if (!mounted) return;
      await ref.read(fileSharerProvider)(
        ShareRequest(
          file: file,
          text: '${widget.batch.name} · ${codes.length} codes',
          origin: shareOriginOf(_shareKey),
        ),
      );
    } catch (_) {
      _say("Couldn't send the list.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showQr(BatchCode c) {
    // The QR sheet draws a Coupon; a run's code is one with the run's deal.
    final coupon = Coupon(
      id: c.code,
      code: c.code,
      name: widget.batch.name,
      type: widget.batch.type,
      value: widget.batch.value,
      isActive: c.isActive,
      createdAt: widget.batch.createdAt,
    );
    return showCouponQrSheet(
      context,
      coupon: coupon,
      currency: widget.currency,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codes = ref.watch(batchCodesProvider(widget.batch.id));
    final muted = theme.colorScheme.onSurfaceVariant;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.batch.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      couponValueLabel(
                        widget.batch.type,
                        widget.batch.value,
                        widget.currency,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy all codes',
                onPressed: codes.hasValue && !_busy
                    ? () => _copyAll(codes.requireValue)
                    : null,
                icon: const Icon(Icons.copy_all_outlined),
                constraints: const BoxConstraints(
                  minWidth: Tokens.tapTarget,
                  minHeight: Tokens.tapTarget,
                ),
              ),
              IconButton(
                key: _shareKey,
                tooltip: 'Send list as CSV',
                onPressed: codes.hasValue && !_busy
                    ? () => _shareCsv(codes.requireValue)
                    : null,
                icon: const Icon(Icons.ios_share),
                constraints: const BoxConstraints(
                  minWidth: Tokens.tapTarget,
                  minHeight: Tokens.tapTarget,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: codes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: RetryNotice(
                message: "Couldn't load the codes.",
                detail: '$e',
                icon: Icons.cloud_off_outlined,
                onRetry: () =>
                    ref.invalidate(batchCodesProvider(widget.batch.id)),
              ),
            ),
            data: (list) => ListView.builder(
              controller: widget.scroll,
              itemCount: list.length,
              itemBuilder: (_, i) => _CodeRow(
                key: ValueKey(list[i].code),
                code: list[i],
                canManage: widget.canManage && !_busy,
                onQr: () => _showQr(list[i]),
                onPdf: () => exportFlyers(
                  context,
                  ref,
                  batch: widget.batch,
                  onlyCodes: [list[i].code],
                  say: _say,
                ),
                onToggleShared: () => _toggleShared(list[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({
    super.key,
    required this.code,
    required this.canManage,
    required this.onQr,
    required this.onPdf,
    required this.onToggleShared,
  });

  final BatchCode code;
  final bool canManage;
  final VoidCallback onQr;
  final VoidCallback onPdf;
  final VoidCallback onToggleShared;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final state = _stateOf(code);
    // Icon + word carry the state; the hue only reinforces.
    final (icon, color) = switch (state) {
      _CodeState.used => (Icons.check_circle, semantic.goodText),
      _CodeState.paused => (Icons.pause_circle_outline, semantic.neutral),
      _CodeState.handedOut => (Icons.send_outlined, semantic.infoText),
      _CodeState.free => (Icons.radio_button_unchecked, semantic.neutral),
    };
    return ListTile(
      title: Text(
        code.code,
        style: theme.textTheme.titleSmall?.copyWith(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            _stateWord(state),
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canManage && state != _CodeState.used)
            IconButton(
              tooltip: code.shared ? 'Not handed out' : 'Mark handed out',
              onPressed: onToggleShared,
              icon: Icon(
                code.shared ? Icons.undo : Icons.send_outlined,
                size: 20,
              ),
              constraints: const BoxConstraints(
                minWidth: Tokens.tapTarget,
                minHeight: Tokens.tapTarget,
              ),
            ),
          IconButton(
            tooltip: 'Flyer PDF',
            onPressed: onPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            constraints: const BoxConstraints(
              minWidth: Tokens.tapTarget,
              minHeight: Tokens.tapTarget,
            ),
          ),
          IconButton(
            tooltip: 'Show QR',
            onPressed: onQr,
            icon: const Icon(Icons.qr_code_2),
            constraints: const BoxConstraints(
              minWidth: Tokens.tapTarget,
              minHeight: Tokens.tapTarget,
            ),
          ),
        ],
      ),
    );
  }
}
