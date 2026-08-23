import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/notice.dart';
import '../../data/supabase/auth_repository.dart';
import 'auth_validation.dart';

/// Confirm the email address with the code from the signup email.
///
/// This is the screen that makes in-app signup possible without deep links. The
/// same confirmation email carries a link (which the web uses) and a code
/// (which this uses) — the Supabase "Confirm signup" template must render
/// `{{ .Token }}` for the code half to exist.
///
/// The email is passed through the route rather than read back from the client:
/// there is no session yet, so there is no `currentUser` to ask.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();

  bool _busy = false;
  bool _resending = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .verifySignupOtp(email: widget.email, token: _code.text);
      // Verified means signed in, and the router decides where that goes —
      // same contract as the login screen, so there is one place that knows.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .resendSignupOtp(email: widget.email);
      if (mounted) {
        setState(() => _notice = 'Sent. It can take a minute to arrive.');
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Reached without an address to verify — nothing on this screen can work,
    // and asking for a code that was never sent anywhere is a dead end. Send
    // them back to the one place that can put this right.
    if (widget.email.trim().isEmpty) return const _NoEmailState();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.mark_email_unread_outlined,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Check your email',
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'We sent a code to ${widget.email}. Enter it to finish '
                      'setting up your account.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),

                    TextFormField(
                      controller: _code,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        hintText: '123456',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      autofillHints: const [AutofillHints.oneTimeCode],
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        letterSpacing: 8,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      enabled: !_busy,
                      autofocus: true,
                      onFieldSubmitted: (_) => _submit(),
                      validator: validateOtp,
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      ErrorNotice(message: _error!),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 16),
                      _SentNotice(message: _notice!),
                    ],

                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy || _resending ? null : _resend,
                      child: Text(
                        _resending ? 'Sending…' : "Didn't get it? Send again",
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => context.go(Routes.login),
                      child: const Text('Use a different email'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirmation that something was sent. Icon and colour together, so it still
/// reads as "good" in greyscale.
class _SentNotice extends StatelessWidget {
  const _SentNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 20,
          color: context.semantic.goodText,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// The verify screen with no address behind it.
///
/// Only reachable if the route is entered directly, but "states are not
/// optional" and an empty one that teaches the next step costs almost nothing.
class _NoEmailState extends StatelessWidget {
  const _NoEmailState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "We don't know which email to confirm",
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start again and we will send a fresh code.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go(Routes.signup),
                    child: const Text('Create an account'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go(Routes.login),
                    child: const Text('Sign in instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
