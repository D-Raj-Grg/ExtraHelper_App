/// Build-time configuration, supplied via `--dart-define-from-file=env.json`.
///
/// Only the Supabase **publishable** key belongs here. RLS is the gate — see
/// `CLAUDE.md` rule 2. The service role key must never reach a client.
library;

class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Where the Next.js app is served, e.g. `https://app.extrahelper.io`.
  ///
  /// Printing needs it: a claimed job is rendered to ESC/POS by
  /// `POST /api/print/render`, so a ticket printed from a phone is byte-identical
  /// to one printed by the till. Optional — everything else in the app works
  /// without it, and the printing screen says plainly when it is missing.
  static const appUrl = String.fromEnvironment('APP_URL');

  static bool get canPrint => appUrl.isNotEmpty;

  /// Whether both values were supplied at build time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Fails loudly at startup rather than surfacing as an opaque network error
  /// on the first query.
  static void assertConfigured() {
    if (isConfigured) return;
    throw StateError(
      'Supabase config missing. Run with:\n'
      '  flutter run --dart-define-from-file=env.json\n'
      'See env.example.json and README.md.',
    );
  }
}
