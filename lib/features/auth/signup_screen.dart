import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/widgets/notice.dart';
import '../../data/supabase/auth_repository.dart';
import 'auth_validation.dart';

/// Create an ExtraHelper account.
///
/// Ports the web's `components/signup-form.tsx`, with one deliberate
/// difference: where the web ends on "check your inbox and click the link",
/// this hands off to [VerifyEmailScreen] to collect the code from the same
/// email. A phone can type six digits; making it follow a link back into an app
/// costs Universal Links, App Links and a signed domain file for a screen
/// someone sees once.
///
/// The restaurant name is optional here and only stashed in user metadata — the
/// restaurant itself is created on the onboarding screen after the email is
/// verified, because `provision_tenant` needs an authenticated caller.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _restaurantName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _restaurantName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final signedIn = await ref
          .read(authRepositoryProvider)
          .signUp(
            email: _email.text,
            password: _password.text,
            fullName: _fullName.text,
            restaurantName: _restaurantName.text,
          );
      if (!mounted) return;
      // A session already means confirmations are off on this project: the
      // router has taken over and pushing a code screen would strand someone in
      // front of an email that never arrives.
      if (signedIn) return;
      context.go(
        '${Routes.verify}?email=${Uri.encodeComponent(_email.text.trim())}',
      );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    Text(
                      'Create your account',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Set up a restaurant, or join one you have been invited to.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),

                    TextFormField(
                      controller: _fullName,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        hintText: 'Jane Doe',
                      ),
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.next,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _restaurantName,
                      decoration: const InputDecoration(
                        labelText: 'Restaurant name',
                        hintText: 'Acme Diner',
                        helperText: 'Optional — you can set this up next.',
                      ),
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.organizationName],
                      textInputAction: TextInputAction.next,
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@restaurant.com',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enabled: !_busy,
                      validator: validateEmail,
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: 'At least $kMinPasswordLength characters.',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                        ),
                      ),
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      enabled: !_busy,
                      onFieldSubmitted: (_) => _submit(),
                      validator: validatePassword,
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      ErrorNotice(message: _error!),
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
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : () => context.go(Routes.login),
                      child: const Text('Already have an account? Sign in'),
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
