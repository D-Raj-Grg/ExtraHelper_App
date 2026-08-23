import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase/tenant_repository.dart';
import 'router.dart';

/// Where a user belongs, decided from state alone so it can be tested without
/// a Supabase client, a router, or a widget tree.
///
/// **"I don't know yet" is not "you belong to nowhere."** Collapsing the two is
/// what put an owner of a live restaurant on the "Join a restaurant" screen
/// while the server was answering every one of their requests with the
/// membership: the memberships read resolved to an empty list whenever auth had
/// not yet produced a user, and an empty list is indistinguishable from a real
/// answer. Only [memberships] holding an actual — empty — list means the user
/// is in no restaurant. A null value, an error, or a first load still in flight
/// all mean *unknown*, and the honest response to unknown is to hold position.
///
/// The routes a signed-out user is allowed to stand on.
///
/// Before in-app signup existed this was just `/login`, and the rule was "not
/// signed in → login". Creating an account needs two more screens that by
/// definition happen before there is a session, so the rule is now a set. Keep
/// it a set: an `if` per public route is how one of them ends up bouncing to
/// login and nobody notices until someone cannot finish signing up.
const _publicRoutes = {Routes.login, Routes.signup, Routes.verify};

/// Returns the location to redirect to, or null to stay put.
String? resolveRedirect({
  required bool signedIn,
  required AsyncValue<List<Membership>?> memberships,
  required Set<String>? permissions,
  required String location,
}) {
  if (!signedIn) {
    return _publicRoutes.contains(location) ? null : Routes.login;
  }

  // Unknown: hold. A failed read is a failed read — not a demotion.
  final known = memberships.valueOrNull;
  if (known == null) return null;

  if (known.isEmpty) {
    return location == Routes.join ? null : Routes.join;
  }

  // In a restaurant: signing up and joining are behind them now.
  if (_publicRoutes.contains(location) || location == Routes.join) {
    return Routes.home;
  }

  // Home is the POS, which a kitchen role cannot use — `Kitchen` holds
  // `kds.view` and `kds.bump` and nothing else, so before this the app opened
  // on "No ordering access" and was a dead end for exactly the person you want
  // holding the kitchen tablet. Send them to their board.
  if (location == Routes.home && permissions != null) {
    final canUsePos =
        permissions.contains('tables.view') ||
        permissions.contains('order.create');
    if (!canUsePos && permissions.contains('kds.view')) return Routes.kds;
  }

  return null;
}
