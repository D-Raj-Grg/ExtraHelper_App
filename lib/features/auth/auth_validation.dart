/// Field validation for signup and email verification.
///
/// Pure functions, deliberately: the web enforces these same rules inside
/// server actions (`app/auth/actions.ts`), and the only way to keep two clients
/// agreeing about what a valid account looks like is to write the rules down
/// somewhere a test can reach without a Supabase client or a widget tree.
///
/// Money and percentage rules are **not** here. Service charge and tax rates
/// are already written down once in `features/settings/charges_form.dart`, and
/// onboarding calls those — a second copy would be a second thing to get
/// wrong.
///
/// None of this is the real gate. `provision_tenant` raises on a blank name and
/// Supabase rejects a weak password regardless — these exist so someone gets
/// told what is wrong before a round trip, not to be trusted afterwards.
library;

/// Shape check only, matching `EMAIL_RE` in `app/auth/actions.ts`. The real
/// verdict comes from Supabase, which rejects whole domains this cannot know
/// about.
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Mirrors the web's minimum. Supabase may demand more; [friendlyAuthError]
/// carries that message through when it does.
const kMinPasswordLength = 8;

String? validateEmail(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return 'Enter your email.';
  if (!_emailRe.hasMatch(v)) return 'Enter a valid email address.';
  return null;
}

String? validatePassword(String? raw) {
  final v = raw ?? '';
  if (v.isEmpty) return 'Choose a password.';
  if (v.length < kMinPasswordLength) {
    return 'Password must be at least $kMinPasswordLength characters.';
  }
  return null;
}

String? validateRestaurantName(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return 'Restaurant name is required.';
  return null;
}

/// The 6-digit code from the confirmation email. Length is not asserted beyond
/// "not empty" on purpose — the code length is a Supabase setting, and hard
/// coding 6 here would silently reject a project configured for 8.
String? validateOtp(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty) return 'Enter the code we emailed you.';
  if (!RegExp(r'^\d+$').hasMatch(v)) return 'The code is digits only.';
  return null;
}

/// Parses the free-text service-charge field into the number the server
/// stores. An empty field is zero — most restaurants add no service charge and
/// should not have to type "0". Anything else has already been through
/// `validateServiceCharge` (`features/settings/charges_form.dart`), which is
/// the one place that rule is written down.
double parsePercent(String? raw) => double.tryParse((raw ?? '').trim()) ?? 0;
