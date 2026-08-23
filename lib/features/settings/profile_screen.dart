import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/supabase/profile_repository.dart';
import '../../data/supabase/supabase_providers.dart';
import 'settings_form.dart';
import 'settings_providers.dart';

/// Who you are, across every restaurant you work in.
///
/// Not tenant-scoped: `profiles` is keyed on the user, so changing a name here
/// changes it everywhere that name appears.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _handle = TextEditingController();

  Profile? _loaded;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onTyped);
    _handle.addListener(_onTyped);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_onTyped)
      ..dispose();
    _handle
      ..removeListener(_onTyped)
      ..dispose();
    super.dispose();
  }

  void _onTyped() => setState(() {});

  void _seed(Profile profile) {
    if (_loaded != null) return;
    _loaded = profile;
    _name.text = profile.fullName ?? '';
    _handle.text = profile.username ?? '';
  }

  bool get _dirty {
    final loaded = _loaded;
    if (loaded == null) return false;
    return _name.text.trim() != (loaded.fullName ?? '') ||
        _handle.text.trim().toLowerCase() != (loaded.username ?? '');
  }

  Future<void> _save() async {
    if (_loaded == null || _busy) return;
    setState(() => _busy = true);
    String message;
    var saved = false;
    try {
      await ref
          .read(profileRepositoryProvider)
          .save(fullName: _name.text, username: _handle.text);
      saved = true;
      message = 'Profile saved.';
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (saved) {
      _loaded = Profile(
        fullName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        username: _handle.text.trim().isEmpty
            ? null
            : _handle.text.trim().toLowerCase(),
        avatarUrl: _loaded?.avatarUrl,
      );
      ref.invalidate(myProfileProvider);
    }

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myProfileProvider);
    final email = ref.watch(currentUserProvider)?.email;

    profile.whenData((value) {
      if (value != null) _seed(value);
    });

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        final navigator = Navigator.of(context);
        if (await confirmDiscard(context)) navigator.pop();
      },
      child: AppScaffold(
        title: 'Profile',
        showDrawer: false,
        bottomNavigationBar: _loaded == null
            ? null
            : SettingsSaveBar(
                canEdit: true,
                dirty: _dirty,
                busy: _busy,
                onSave: _save,
              ),
        body: profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Problem(
            message: '$e',
            onRetry: () => ref.invalidate(myProfileProvider),
          ),
          data: (value) => ListView(
            padding: const EdgeInsets.only(top: 6, bottom: 24),
            children: [
              SettingsSection(
                title: 'You',
                children: [
                  Row(
                    children: [
                      _Avatar(
                        url: value?.avatarUrl,
                        seed: _name.text.trim().isEmpty
                            ? (email ?? '?')
                            : _name.text.trim(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              email ?? 'Signed in',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Change your picture in the web app.',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _name,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      helperText: 'Shown on tickets and in the manager log.',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _handle,
                    // Lowercase is the stored form, so type it that way rather
                    // than correcting it silently after the fact.
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      labelText: 'Handle',
                      prefixText: '@',
                      helperText:
                          'Optional. 3–30 characters: lowercase letters, '
                          'numbers and underscores.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The picture, or the first letter of whatever name we have. Never an empty
/// grey circle — a row with no mark in it reads as a loading state.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.seed});

  final String? url;
  final String seed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = seed.trim().isEmpty ? '?' : seed.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: 28,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      foregroundImage: url == null ? null : NetworkImage(url!),
      child: Text(
        initial,
        style: theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
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
              "Couldn't load your profile.",
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
