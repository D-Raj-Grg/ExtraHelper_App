import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prefs.dart';

/// Whether this device has been shown the welcome carousel.
///
/// Per **install**, not per session: someone who signs out mid-service is not
/// pitched the app again on their way back in.
const _welcomeSeenKey = 'welcome_seen';

/// The first-launch gate, answered synchronously.
///
/// **This one reads storage once and never listens.** [PrintEnabled] and
/// [AppThemeMode] both carry a `_settled` guard because a tap can land while
/// SharedPreferences is still opening, and a late read would silently undo it.
/// Nothing can be tapped into this value: it is read before the first frame and
/// written exactly once, on the way out. A listener would only add a way for a
/// late answer to yank someone off the login form they are already typing into.
///
/// `ref.read`, deliberately, not `ref.watch` — see above. It is safe because
/// `main()` resolves SharedPreferences before `runApp` and overrides
/// [sharedPreferencesProvider] with the instance, so the value below is real on
/// the first read rather than a placeholder that arrives later.
///
/// **Storage that has not answered is not the same as storage with nothing in
/// it** — the same distinction `app/redirect.dart` draws about memberships, and
/// for the same reason. No stored value is a real answer: this is a fresh
/// install and the carousel is owed. A SharedPreferences that has not resolved
/// is *unknown*, and the honest response to unknown here is to stay out of the
/// way and let the login screen render. Collapsing the two into one `?? true`
/// means a fresh install never sees the carousel at all.
class WelcomeSeen extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.read(sharedPreferencesProvider).valueOrNull;
    // Unknown: do not interrupt someone who may already be typing a password.
    if (prefs == null) return true;
    // Known, and empty: nobody has been shown this yet.
    return prefs.getBool(_welcomeSeenKey) ?? false;
  }

  /// Closes the door behind the carousel.
  ///
  /// State first, disk second, and the order matters: the router listens to
  /// this provider, so setting state synchronously means the bump, the
  /// re-resolved redirect and the move to `/login` all happen on the frame of
  /// the tap. The write lands after. An app killed in between shows the
  /// carousel once more, which is the mildest failure available here.
  Future<void> markSeen() async {
    if (state) return;
    state = true;
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(_welcomeSeenKey, true);
  }
}

final welcomeSeenProvider = NotifierProvider<WelcomeSeen, bool>(
  WelcomeSeen.new,
);
