import 'package:extrahelper/data/supabase/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('friendlyAuthError', () {
    test('turns the common failures into something actionable', () {
      expect(
        friendlyAuthError(
          code: 'invalid_credentials',
          message: 'Invalid login credentials',
        ),
        'That email or password is wrong.',
      );
      expect(
        friendlyAuthError(code: 'email_not_confirmed', message: 'x'),
        contains('Confirm your email'),
      );
      expect(
        friendlyAuthError(code: 'over_request_rate_limit', message: 'x'),
        contains('Too many attempts'),
      );
    });

    test('matches on the message when no code is supplied', () {
      expect(
        friendlyAuthError(message: 'Invalid login credentials'),
        'That email or password is wrong.',
      );
    });

    test('an unmapped error still says something, never an empty string', () {
      const raw = 'Some new server-side failure';
      expect(friendlyAuthError(message: raw), raw);
    });

    test('never leaks a bare exception type to a waiter', () {
      final out = friendlyAuthError(code: 'weak_password', message: 'x');
      expect(out, isNot(contains('Exception')));
      expect(out, isNot(contains('AuthException')));
    });
  });
}
