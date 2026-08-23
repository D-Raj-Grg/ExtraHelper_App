import 'package:extrahelper/data/supabase/team_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Turning server prose into something a person can act on.
///
/// The ordering inside `friendlyTeamError` is the whole point and the only
/// thing these tests really guard. Every owner guard raises `42501`, and so
/// does the plain "not authorized" gate — so if the generic branch is checked
/// first, "cannot remove the last owner" silently becomes "ask an owner for
/// permission", which is advice that cannot possibly work.

/// The generic authorisation line, so a test can assert something is *not* it.
const _generic =
    'Your role can see the team but not change it. Ask an owner for the '
    '"Manage team & roles" permission.';

void main() {
  group('the owner guards survive the generic 42501 branch', () {
    // Every string here is raised verbatim by a team RPC.
    const guards = {
      'cannot demote the last owner': 'only owner',
      'cannot remove the last owner': 'only owner',
      'you cannot remove yourself': 'your own access',
      'only an owner can assign the owner role': 'hand out the Owner role',
      'only an owner can modify an owner': "another owner's role",
      'only an owner can remove an owner': 'remove another owner',
      'only an owner can approve an owner': 'approve someone joining',
    };

    for (final entry in guards.entries) {
      test('"${entry.key}" says what to do instead', () {
        final friendly = friendlyTeamError(entry.key);
        expect(friendly, isNot(_generic));
        expect(friendly, isNot(entry.key));
        expect(friendly, contains(entry.value));
      });
    }

    test('the seven guards do not collapse into one message', () {
      final messages = guards.keys.map(friendlyTeamError).toSet();
      expect(messages, hasLength(guards.length));
    });
  });

  group('the other server strings', () {
    test('already a member points at the fix, not at permissions', () {
      final friendly = friendlyTeamError('already a member');
      expect(friendly, isNot(_generic));
      expect(friendly, contains('Change their role'));
    });

    test('a duplicate role name names the field to change', () {
      final friendly = friendlyTeamError(
        'duplicate key value violates unique constraint '
        '"roles_tenant_id_name_key"',
      );
      expect(friendly, contains('Pick another name'));
    });

    test('a stale role tells the reader to refresh', () {
      for (final raw in ['invalid role', 'role not found']) {
        expect(friendlyTeamError(raw), contains('Pull to refresh'));
      }
    });

    test('member not found is a staleness problem, not a permission one', () {
      final friendly = friendlyTeamError('member not found');
      expect(friendly, isNot(_generic));
      expect(friendly, contains('Pull to refresh'));
    });

    test('an empty email asks for the email', () {
      expect(friendlyTeamError('email required'), contains('email address'));
    });
  });

  group('the generic branch', () {
    test('catches the bare RPC gate', () {
      expect(friendlyTeamError('not authorized'), _generic);
    });

    test('catches a silent RLS refusal spelled either way', () {
      expect(friendlyTeamError('permission denied for table roles'), _generic);
      expect(
        friendlyTeamError(
          'new row violates row-level security policy for table "roles"',
        ),
        _generic,
      );
    });

    test('is case-insensitive, because Postgres prose is not consistent', () {
      expect(friendlyTeamError('NOT AUTHORIZED'), _generic);
      expect(
        friendlyTeamError('Cannot Remove The Last Owner'),
        isNot(_generic),
      );
    });
  });

  test('anything unrecognised is passed through rather than swallowed', () {
    const raw = 'could not serialize access due to concurrent update';
    expect(friendlyTeamError(raw), raw);
  });
}
