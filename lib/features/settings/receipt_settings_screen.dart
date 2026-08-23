import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/supabase/settings_repository.dart';
import '../tenant/tenant_providers.dart';
import 'brand_image_card.dart';
import 'settings_form.dart';
import 'settings_providers.dart';

/// What a guest is handed at the end.
///
/// Text and branding save separately: an image upload is a three-step job with
/// its own failure modes (too big, won't scan, storage refused), and holding it
/// behind the same Save button as three text fields means one of them fails and
/// neither is saved.
class ReceiptSettingsScreen extends ConsumerStatefulWidget {
  const ReceiptSettingsScreen({super.key});

  @override
  ConsumerState<ReceiptSettingsScreen> createState() =>
      _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState extends ConsumerState<ReceiptSettingsScreen> {
  final _header = TextEditingController();
  final _footer = TextEditingController();
  final _terms = TextEditingController();
  final _caption = TextEditingController();

  ReceiptTemplate? _loaded;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [_header, _footer, _terms, _caption]) {
      controller.addListener(_onTyped);
    }
  }

  @override
  void dispose() {
    for (final controller in [_header, _footer, _terms, _caption]) {
      controller
        ..removeListener(_onTyped)
        ..dispose();
    }
    super.dispose();
  }

  void _onTyped() => setState(() {});

  void _seed(ReceiptTemplate receipt) {
    if (_loaded != null) return;
    _loaded = receipt;
    _header.text = receipt.header;
    _footer.text = receipt.footer;
    _terms.text = receipt.terms;
    _caption.text = receipt.qrCaption;
  }

  bool get _dirty {
    final loaded = _loaded;
    if (loaded == null) return false;
    return _header.text.trim() != loaded.header ||
        _footer.text.trim() != loaded.footer ||
        _terms.text.trim() != loaded.terms ||
        _caption.text.trim() != loaded.qrCaption;
  }

  Future<void> _save() async {
    final tenant = ref.read(activeTenantProvider);
    if (_loaded == null || tenant == null || _busy) return;

    setState(() => _busy = true);
    String message;
    var saved = false;
    try {
      await ref
          .read(settingsRepositoryProvider(tenant.tenantId))
          .saveReceiptText(
            header: _header.text,
            footer: _footer.text,
            terms: _terms.text,
            qrCaption: _caption.text,
          );
      saved = true;
      message = 'Receipt saved.';
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (saved) {
      final loaded = _loaded!;
      _loaded = ReceiptTemplate(
        header: _header.text.trim(),
        footer: _footer.text.trim(),
        terms: _terms.text.trim(),
        qrCaption: _caption.text.trim(),
        logoUrl: loaded.logoUrl,
        qrUrl: loaded.qrUrl,
        printAssets: loaded.printAssets,
      );
      ref.invalidate(tenantSettingsProvider);
    }

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(hasPermissionProvider('settings.edit'));
    // Branding is a heavier change than wording, and the bucket's own policy
    // lets any member write into the tenant folder — the gate that actually
    // holds is `merge_receipt_template`, which is owner|manager. Ask the same
    // question here so nobody is offered a control that will be refused.
    final canBrand = canEdit && ref.watch(isManagerProvider);
    final settings = ref.watch(tenantSettingsProvider);

    settings.whenData((value) {
      if (value != null) _seed(value.receipt);
    });

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        final navigator = Navigator.of(context);
        if (await confirmDiscard(context)) navigator.pop();
      },
      child: AppScaffold(
        title: 'Receipt & branding',
        showDrawer: false,
        bottomNavigationBar: _loaded == null
            ? null
            : SettingsSaveBar(
                canEdit: canEdit,
                dirty: _dirty,
                busy: _busy,
                onSave: _save,
                label: 'Save wording',
              ),
        body: settings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Problem(
            message: '$e',
            onRetry: () => ref.invalidate(tenantSettingsProvider),
          ),
          data: (value) => ListView(
            padding: const EdgeInsets.only(top: 6, bottom: 24),
            children: [
              SettingsSection(
                title: 'Wording',
                detail: 'Printed on every bill and receipt.',
                children: [
                  TextField(
                    controller: _header,
                    enabled: canEdit,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Header',
                      hintText: 'Address, phone, tax number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _footer,
                    enabled: canEdit,
                    minLines: 2,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Footer',
                      hintText: 'Thank you — see you again',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _terms,
                    enabled: canEdit,
                    minLines: 3,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Terms',
                      hintText: 'Refund policy, small print',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _caption,
                    enabled: canEdit,
                    // Anything longer wraps past the roll and the QR ends up
                    // captioned by half a sentence.
                    maxLength: 40,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Payment QR caption',
                      hintText: 'Scan to pay',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              if (value != null) ...[
                BrandImageCard(
                  kind: 'logo',
                  settings: value,
                  canEdit: canBrand,
                ),
                BrandImageCard(kind: 'qr', settings: value, canEdit: canBrand),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Text(
                    'Images are converted to the black-and-white form a thermal '
                    'printer needs, at every paper width, when you upload them. '
                    'A payment QR is scanned back afterwards to prove it still '
                    'reads.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your receipt settings.",
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
