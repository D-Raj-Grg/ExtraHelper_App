import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/env.dart';
import '../../core/theme/tokens.dart';
import '../coupons/coupon_qr_sheet.dart' show QrSquare, qrModules;
import '../pos/bill_export.dart';
import '../pos/models.dart';

/// The public link a table's printed QR opens.
String tableQrUrl(String origin, String token) =>
    '${origin.replaceAll(RegExp(r'/+$'), '')}/t/$token';

/// The table's QR: hold the phone up for a guest, copy the link, or send the
/// picture to whoever prints the table cards.
Future<void> showTableQrSheet(
  BuildContext context, {
  required PosTable table,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => TableQrSheet(table: table),
);

class TableQrSheet extends ConsumerStatefulWidget {
  const TableQrSheet({super.key, required this.table});

  final PosTable table;

  @override
  ConsumerState<TableQrSheet> createState() => _TableQrSheetState();
}

class _TableQrSheetState extends ConsumerState<TableQrSheet> {
  final _cardKey = GlobalKey();
  final _shareKey = GlobalKey();
  bool _busy = false;
  bool _copied = false;
  String? _payload;
  List<List<bool>> _grid = const [];

  @override
  void initState() {
    super.initState();
    final token = widget.table.qrToken;
    if (token != null && token.isNotEmpty && Env.appUrl.isNotEmpty) {
      _payload = tableQrUrl(Env.appUrl, token);
      _grid = qrModules(_payload!);
    }
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _payload!));
      if (mounted) setState(() => _copied = true);
    } catch (_) {
      _say("Couldn't copy the link.");
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw const BillExportFailure("Couldn't draw the QR to send.");
      }
      final png = await capturePng(boundary);
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'tables'),
      );
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'table-${widget.table.id}.png'));
      await file.writeAsBytes(png, flush: true);
      if (!mounted) return;
      await ref.read(fileSharerProvider)(
        ShareRequest(
          file: file,
          text: 'Table ${widget.table.label} · $_payload',
          origin: shareOriginOf(_shareKey),
        ),
      );
    } on BillExportFailure catch (e) {
      _say(e.message);
    } catch (_) {
      _say("Couldn't send the QR.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payload = _payload;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Table ${widget.table.label} QR',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              payload != null
                  ? 'Guests scan this to order from the table.'
                  : Env.appUrl.isEmpty
                  ? "This build has no web address set, so it can't make "
                        'the QR link.'
                  : "This table's QR isn't on this phone yet. Connect and "
                        'pull to refresh the list, then try again.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (payload != null) ...[
              const SizedBox(height: 16),
              Center(
                child: RepaintBoundary(
                  key: _cardKey,
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.all(20),
                    // White ground and black modules on purpose: a camera
                    // wants maximum contrast, in dark mode too.
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        QrSquare(payload: payload, grid: _grid, size: 220),
                        const SizedBox(height: 14),
                        Text(
                          widget.table.label,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Tokens.lightForeground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
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
          ],
        ),
      ),
    );
  }
}
