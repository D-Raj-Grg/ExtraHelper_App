import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_scaffold.dart';
import '../../core/env.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../core/widgets/notice.dart';
import '../../data/supabase/coupon_batches_repository.dart';
import '../../data/supabase/flyer_designs_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../tenant/tenant_providers.dart';
import 'coupons_providers.dart';
import 'flyer_placement.dart';

/// Step 2 of the flyer wizard: put the code and the QR on the picture.
/// Pick a saved design or upload a picture, drag the two boxes where they
/// belong, save. Saving also points [batch] at the design, so printing the
/// run needs nothing further. Pops `true` when a design was saved or removed.
Future<bool?> showFlyerDesignScreen(
  BuildContext context, {
  required CouponBatch batch,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(builder: (_) => FlyerDesignScreen(batch: batch)),
);

const _swatches = [
  '#000000',
  '#7a2a12',
  '#b91c1c',
  '#b45309',
  '#15803d',
  '#1d4ed8',
  '#1f2937',
  '#ffffff',
];

Color _hexColor(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return Color(0xFF000000 | (v ?? 0));
}

bool _isPng(Uint8List b) =>
    b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e;
bool _isJpeg(Uint8List b) => b.length > 3 && b[0] == 0xff && b[1] == 0xd8;

class FlyerDesignScreen extends ConsumerStatefulWidget {
  const FlyerDesignScreen({super.key, required this.batch});

  final CouponBatch batch;

  @override
  ConsumerState<FlyerDesignScreen> createState() => _FlyerDesignScreenState();
}

class _FlyerDesignScreenState extends ConsumerState<FlyerDesignScreen> {
  final _name = TextEditingController();

  /// The saved design being edited, or null for a brand-new one.
  FlyerDesign? _design;

  /// A picture picked this session (not yet stored).
  FlyerPicture? _picture;

  /// What is on screen: the picked picture or the downloaded one.
  Uint8List? _bytes;
  int _w = 0;
  int _h = 0;
  FlyerPlacement _placement = defaultPlacement;
  String _mode = 'url';
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final id = widget.batch.designId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSaved(id));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  FlyerDesignsRepository? get _repo {
    final t = ref.read(activeTenantProvider);
    return t == null
        ? null
        : ref.read(flyerDesignsRepositoryProvider(t.tenantId));
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openSaved(String id) async {
    final designs = await ref
        .read(flyerDesignsProvider.future)
        .catchError((_) => <FlyerDesign>[]);
    final d = designs.where((x) => x.id == id).firstOrNull;
    if (d != null && mounted) await _load(d);
  }

  Future<void> _load(FlyerDesign d) async {
    final repo = _repo;
    if (repo == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await repo.template(d.imagePath);
      if (!mounted) return;
      setState(() {
        _design = d;
        _picture = null;
        _bytes = bytes;
        _w = d.width;
        _h = d.height;
        _placement = d.placement;
        _mode = d.mode;
        _name.text = d.name;
      });
    } on PosFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't open that design.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    try {
      // A4 at 300 dpi is 2480×3508: plenty to print from, and small enough
      // to stay under the 5 MB the bucket accepts.
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2480,
        maxHeight: 3508,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!_isPng(bytes) && !_isJpeg(bytes)) {
        _say('Use a JPEG or PNG picture.');
        return;
      }
      if (bytes.length > flyerTemplateMaxBytes) {
        _say('That picture is over 5 MB. Pick a smaller one.');
        return;
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      final stem = x.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      setState(() {
        _design = null;
        _picture = FlyerPicture(
          bytes: bytes,
          width: w,
          height: h,
          isPng: _isPng(bytes),
        );
        _bytes = bytes;
        _w = w;
        _h = h;
        _placement = defaultPlacement;
        _mode = 'url';
        _name.text = stem.length > 80 ? stem.substring(0, 80) : stem;
        _error = null;
      });
    } catch (_) {
      _say("Couldn't read that picture.");
    }
  }

  /// Replace the picture of the design being edited, keeping its placement.
  Future<void> _replacePicture() async {
    final keepPlacement = _placement;
    final keepMode = _mode;
    final keepName = _name.text;
    final d = _design;
    await _upload();
    if (!mounted || _picture == null) return;
    setState(() {
      _design = d;
      _placement = keepPlacement;
      _mode = keepMode;
      _name.text = keepName;
    });
  }

  void _chooseAnother() => setState(() {
    _bytes = null;
    _design = null;
    _picture = null;
    _error = null;
  });

  Future<void> _save({bool asCopy = false}) async {
    final repo = _repo;
    final bytes = _bytes;
    if (repo == null || bytes == null || _saving) return;
    final copy = asCopy && _design != null;
    final name = copy ? '${_name.text.trim()} copy' : _name.text;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // A copy is a new row, so it needs a picture of its own to store.
      final picture =
          _picture ??
          (copy
              ? FlyerPicture(
                  bytes: bytes,
                  width: _w,
                  height: _h,
                  isPng: _isPng(bytes),
                )
              : null);
      await repo.save(
        id: copy ? null : _design?.id,
        name: name,
        picture: picture,
        previousPath: copy ? null : _design?.imagePath,
        width: _w,
        height: _h,
        placement: _placement,
        mode: _mode,
        linkBase: _design?.linkBase,
        batchId: widget.batch.id,
      );
      ref
        ..invalidate(flyerDesignsProvider)
        ..invalidate(couponBatchesProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PosFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't save the design.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final d = _design;
    final repo = _repo;
    if (d == null || repo == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${d.name}?'),
        content: const Text(
          'Runs that use it keep their codes and stay valid; they just have '
          'no design until you add one. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Theme.of(c).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete design'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await repo.delete(d.id);
      ref
        ..invalidate(flyerDesignsProvider)
        ..invalidate(couponBatchesProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on PosFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't delete the design.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(hasPermissionProvider('coupons.manage'));
    final bytes = _bytes;
    return AppScaffold(
      title: bytes == null ? 'Flyer design' : 'Place code and QR',
      body: !canManage
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'An owner or manager sets up the flyer design. You can '
                  'still download the flyers from the run.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : bytes == null
          ? _Gallery(error: _error, onPick: _load, onUpload: _upload)
          : _Editor(
              bytes: bytes,
              width: _w,
              height: _h,
              placement: _placement,
              mode: _mode,
              name: _name,
              batch: widget.batch,
              saved: _design != null,
              saving: _saving,
              error: _error,
              onPlacement: (p) => setState(() => _placement = p),
              onMode: (m) => setState(() => _mode = m),
              onSave: _save,
              onCopy: () => _save(asCopy: true),
              onDelete: _delete,
              onChoose: _chooseAnother,
              onReplace: _replacePicture,
            ),
    );
  }
}

// --- Gallery ---------------------------------------------------------------

class _Gallery extends ConsumerWidget {
  const _Gallery({
    required this.error,
    required this.onPick,
    required this.onUpload,
  });

  final String? error;
  final ValueChanged<FlyerDesign> onPick;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final designs = ref.watch(flyerDesignsProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        designs.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => RetryNotice(
            message: "Couldn't load the designs.",
            detail: '$e',
            icon: Icons.cloud_off_outlined,
            onRetry: () => ref.invalidate(flyerDesignsProvider),
          ),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                list.isEmpty
                    ? 'Upload your flyer picture. You will place the code and '
                          'QR on it next, and it is saved for next time.'
                    : 'Reuse a saved design, or upload a new flyer picture.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _Tiles(designs: list, onPick: onPick, onUpload: onUpload),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tiles extends ConsumerWidget {
  const _Tiles({
    required this.designs,
    required this.onPick,
    required this.onUpload,
  });

  final List<FlyerDesign> designs;
  final ValueChanged<FlyerDesign> onPick;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(activeTenantProvider);
    final thumbs = designs.isEmpty || tenant == null
        ? const AsyncData<Map<String, String>>({})
        : ref.watch(_thumbsProvider(designs.map((d) => d.imagePath).toList()));
    final urls = thumbs.valueOrNull ?? const {};
    final theme = Theme.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.74,
      children: [
        _UploadTile(onTap: onUpload),
        for (final d in designs)
          Semantics(
            button: true,
            label: 'Use design ${d.name}',
            child: InkWell(
              onTap: () => onPick(d),
              borderRadius: BorderRadius.circular(12),
              child: Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: urls[d.imagePath] == null
                          ? const Center(
                              child: Icon(Icons.image_outlined, size: 32),
                            )
                          : Image.network(
                              urls[d.imagePath]!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

final _thumbsProvider = FutureProvider.autoDispose
    .family<Map<String, String>, List<String>>((ref, paths) async {
      final tenantId = ref.watch(
        activeTenantProvider.select((m) => m?.tenantId),
      );
      if (tenantId == null) return const {};
      return ref
          .watch(flyerDesignsRepositoryProvider(tenantId))
          .thumbnails(paths);
    });

class _UploadTile extends StatelessWidget {
  const _UploadTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Upload new picture',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_photo_alternate_outlined, size: 32),
                SizedBox(height: 8),
                Text('Upload new picture'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Editor ----------------------------------------------------------------

class _Editor extends ConsumerWidget {
  const _Editor({
    required this.bytes,
    required this.width,
    required this.height,
    required this.placement,
    required this.mode,
    required this.name,
    required this.batch,
    required this.saved,
    required this.saving,
    required this.error,
    required this.onPlacement,
    required this.onMode,
    required this.onSave,
    required this.onCopy,
    required this.onDelete,
    required this.onChoose,
    required this.onReplace,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final FlyerPlacement placement;
  final String mode;
  final TextEditingController name;
  final CouponBatch batch;
  final bool saved;
  final bool saving;
  final String? error;
  final ValueChanged<FlyerPlacement> onPlacement;
  final ValueChanged<String> onMode;
  final VoidCallback onSave;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onChoose;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final slug = ref.watch(activeTenantProvider)?.slug ?? '';
    final sample =
        ref
            .watch(batchCodesProvider(batch.id))
            .valueOrNull
            ?.firstOrNull
            ?.code ??
        'SEKU-A1B2C3';
    final payload = flyerPayload(
      mode: mode,
      origin: Env.appUrl,
      slug: slug,
      code: sample,
    );
    final grid = flyerQrGrid(payload);
    final p = placement;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final noLink = Env.appUrl.isEmpty || slug.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: saving ? null : onChoose,
              icon: const Icon(Icons.collections_outlined),
              label: const Text('Choose a different design'),
            ),
            TextButton.icon(
              onPressed: saving ? null : onReplace,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Replace picture'),
            ),
          ],
        ),
        Text(
          'Drag the code and the QR square where they belong. Pull the corner '
          'dot to resize.',
          style: muted,
        ),
        const SizedBox(height: 8),
        _Canvas(
          bytes: bytes,
          ratio: height / (width == 0 ? 1 : width),
          placement: p,
          sample: sample,
          grid: grid,
          onPlacement: onPlacement,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: name,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Design name',
            hintText: 'Dashain A4',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text('Code colour', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        _Swatches(
          selected: p.codeColor,
          onPick: (c) => onPlacement(p.copyWith(codeColor: c)),
          label: 'code',
        ),
        const SizedBox(height: 12),
        Text('QR colour', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        _Swatches(
          selected: p.qrColor,
          onPick: (c) => onPlacement(p.copyWith(qrColor: c)),
          label: 'QR',
        ),
        Text(
          'Keep the QR dark on a light square so phones read it.',
          style: muted,
        ),
        const SizedBox(height: 12),
        _SliderRow(
          label: 'Code size',
          value: p.codeScale,
          min: 0.3,
          max: 1,
          divisions: 14,
          onChanged: (v) => onPlacement(p.copyWith(codeScale: v)),
        ),
        _SliderRow(
          label: 'QR margin',
          value: p.qrInset,
          min: 0,
          max: 0.15,
          divisions: 15,
          onChanged: (v) => onPlacement(p.copyWith(qrInset: v)),
        ),
        const SizedBox(height: 8),
        Text('What the QR carries', style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AppChoiceChip(
                label: 'Storefront link',
                detail: 'Recommended',
                selected: mode == 'url',
                showCheck: true,
                onSelect: () => onMode('url'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppChoiceChip(
                label: 'Code only',
                selected: mode == 'code',
                showCheck: true,
                onSelect: () => onMode('code'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          mode == 'url' && noLink
              ? 'No storefront address is set on this app, so the QR will '
                    'carry the code only.'
              : 'Sample QR text: $payload',
          style: muted,
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: Tokens.tapTarget + 4,
          child: FilledButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Save design and finish'),
          ),
        ),
        if (saved) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: Tokens.tapTarget,
            child: OutlinedButton(
              onPressed: saving ? null : onCopy,
              child: const Text('Save as a new copy'),
            ),
          ),
          SizedBox(
            height: Tokens.tapTarget,
            child: TextButton(
              onPressed: saving ? null : onDelete,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Delete design'),
            ),
          ),
        ],
      ],
    );
  }
}

class _Canvas extends StatelessWidget {
  const _Canvas({
    required this.bytes,
    required this.ratio,
    required this.placement,
    required this.sample,
    required this.grid,
    required this.onPlacement,
  });

  final Uint8List bytes;
  final double ratio;
  final FlyerPlacement placement;
  final String sample;
  final List<List<bool>> grid;
  final ValueChanged<FlyerPlacement> onPlacement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = w * ratio;
        final p = placement;
        final c = p.code;
        final q = p.qr;
        final outline = theme.colorScheme.primary;
        const handle = 28.0;

        Widget handleDot(void Function(DragUpdateDetails) onDrag) => Semantics(
          label: 'Resize',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: onDrag,
            child: SizedBox.square(
              dimension: handle + 16,
              child: Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  width: handle,
                  height: handle,
                  decoration: BoxDecoration(
                    color: outline,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
          ),
        );

        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ),
              // Code box
              Positioned(
                left: c.x * w,
                top: c.y * h,
                width: c.w * w,
                height: c.h * h,
                child: Semantics(
                  label: 'Code position',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => onPlacement(
                      moveCode(p, d.delta.dx / w, d.delta.dy / h),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: outline, width: 1.5),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: c.h * h * (1 - p.codeScale) / 2,
                        ),
                        child: FittedBox(
                          child: Text(
                            sample,
                            style: TextStyle(
                              color: _hexColor(p.codeColor),
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Helvetica',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (c.x + c.w) * w - handle - 8,
                top: (c.y + c.h) * h - handle - 8,
                child: handleDot(
                  (d) => onPlacement(
                    resizeCode(p, d.delta.dx / w, d.delta.dy / h),
                  ),
                ),
              ),
              // QR square
              Positioned(
                left: q.x * w,
                top: q.y * h,
                width: q.s * w,
                height: q.s * w,
                child: Semantics(
                  label: 'QR position',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => onPlacement(
                      moveQr(p, d.delta.dx / w, d.delta.dy / h, ratio),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: outline, width: 1.5),
                      ),
                      child: CustomPaint(
                        painter: _QrPreview(
                          grid: grid,
                          color: _hexColor(p.qrColor),
                          inset: p.qrInset,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (q.x + q.s) * w - handle - 8,
                top: q.y * h + q.s * w - handle - 8,
                child: handleDot(
                  (d) => onPlacement(
                    resizeQr(p, d.delta.dx / w, d.delta.dy / h, ratio),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QrPreview extends CustomPainter {
  const _QrPreview({
    required this.grid,
    required this.color,
    required this.inset,
  });

  final List<List<bool>> grid;
  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (grid.isEmpty) return;
    final side = size.width;
    final inner = side * (1 - 2 * inset);
    final cell = inner / grid.length;
    final paint = Paint()..color = color;
    final o = side * inset;
    for (final (row, col, len) in qrRuns(grid)) {
      canvas.drawRect(
        Rect.fromLTWH(
          o + col * cell,
          o + row * cell,
          len * cell + 0.4,
          cell + 0.4,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_QrPreview old) =>
      old.grid != grid || old.color != color || old.inset != inset;
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.selected,
    required this.onPick,
    required this.label,
  });

  final String selected;
  final ValueChanged<String> onPick;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final hex in _swatches)
          Semantics(
            button: true,
            selected: hex.toLowerCase() == selected.toLowerCase(),
            label: '$label colour $hex',
            child: InkResponse(
              onTap: () => onPick(hex),
              child: Container(
                width: Tokens.tapTarget,
                height: Tokens.tapTarget,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _hexColor(hex),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: hex.toLowerCase() == selected.toLowerCase()
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: hex.toLowerCase() == selected.toLowerCase() ? 3 : 1,
                  ),
                ),
                // A check, not just a ring: the state survives greyscale.
                child: hex.toLowerCase() == selected.toLowerCase()
                    ? Icon(
                        Icons.check,
                        size: 20,
                        color: _hexColor(hex).computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            semanticFormatterCallback: (v) => '$label ${v.toStringAsFixed(2)}',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
