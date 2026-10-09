import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/env.dart';
import '../../data/supabase/coupon_batches_repository.dart';
import '../../data/supabase/flyer_designs_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../pos/bill_export.dart';
import '../tenant/tenant_providers.dart';
import 'flyer_pdf.dart';
import 'flyer_placement.dart';

/// Print a run: build the flyer PDF on the phone and hand it to the share
/// sheet (Save to Files, AirDrop, a printer app, WhatsApp).
///
/// [onlyCodes] null prints every code of the run (the web's "Download all N
/// flyers"); one code is a single flyer, the first code is the proof page.
/// The run needs a design; without one this says so instead of guessing.
Future<void> exportFlyers(
  BuildContext context,
  WidgetRef ref, {
  required CouponBatch batch,
  List<String>? onlyCodes,
  bool proof = false,
  required void Function(String) say,
}) async {
  final designId = batch.designId;
  if (designId == null) {
    say('Add a design to this run first.');
    return;
  }
  final tenant = ref.read(activeTenantProvider);
  if (tenant == null) return;
  final designs = ref.read(flyerDesignsRepositoryProvider(tenant.tenantId));
  final batches = ref.read(couponBatchesRepositoryProvider(tenant.tenantId));
  final fileSharer = ref.read(fileSharerProvider);

  final navigator = Navigator.of(context, rootNavigator: true);
  final shown = ValueNotifier<String>('Getting the design…');
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<String>(
            valueListenable: shown,
            builder: (_, text, _) => Row(
              children: [
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(text)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  try {
    final all = await designs.list();
    final design = all.where((d) => d.id == designId).firstOrNull;
    if (design == null) {
      throw const PosFailure('That design was deleted. Add a new one.');
    }
    final template = await designs.template(design.imagePath);

    var codes = onlyCodes;
    codes ??= (await batches.codes(batch.id)).map((c) => c.code).toList();
    if (proof) codes = codes.take(1).toList();
    if (codes.isEmpty) throw const PosFailure('This run has no codes.');

    shown.value =
        'Building ${codes.length} ${codes.length == 1 ? 'page' : 'pages'}…';
    final origin = design.linkBase ?? Env.appUrl;
    final pages = [
      for (final c in codes)
        FlyerPage(
          code: c,
          payload: flyerPayload(
            mode: design.mode,
            origin: origin,
            slug: tenant.slug,
            code: c,
          ),
        ),
    ];
    final Uint8List pdf = await buildFlyerPdf(
      template: template,
      placement: design.placement,
      pages: pages,
    );

    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'flyers'),
    );
    await dir.create(recursive: true);
    final base = slugify(batch.name);
    final name = codes.length == 1 && !proof
        ? '${codes.first}.pdf'
        : proof
        ? '$base-proof.pdf'
        : '$base-flyers.pdf';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(pdf, flush: true);

    if (navigator.mounted) navigator.pop(); // progress dialog
    await fileSharer(
      ShareRequest(
        file: file,
        text: codes.length == 1
            ? '${batch.name} · ${codes.first}'
            : '${batch.name} · ${codes.length} flyers',
        origin: shareOriginOf(GlobalKey()),
      ),
    );
  } on PosFailure catch (e) {
    if (navigator.mounted) navigator.pop();
    say(e.message);
  } catch (_) {
    if (navigator.mounted) navigator.pop();
    say("Couldn't build the flyer PDF.");
  } finally {
    shown.dispose();
  }
}
