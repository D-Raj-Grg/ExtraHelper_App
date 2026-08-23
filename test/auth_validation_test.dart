import 'package:extrahelper/features/auth/auth_validation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Signup validation, held to the web's rules.
///
/// The sentences and the bounds both come from `app/auth/actions.ts`. Two
/// clients that disagree about what a valid password is means someone is told
/// their account was created and then cannot sign in.
void main() {
  group('email', () {
    test('accepts an ordinary address', () {
      expect(validateEmail('jane@restaurant.com'), isNull);
    });

    test('trims before judging', () {
      expect(validateEmail('  jane@restaurant.com  '), isNull);
    });

    test('asks for an email when the field is empty', () {
      expect(validateEmail(''), 'Enter your email.');
      expect(validateEmail(null), 'Enter your email.');
      expect(validateEmail('   '), 'Enter your email.');
    });

    test('rejects the shapes the web regex rejects', () {
      for (final bad in [
        'jane',
        'jane@',
        '@restaurant.com',
        'jane@restaurant',
        'jane doe@restaurant.com',
        'jane@rest aurant.com',
      ]) {
        expect(
          validateEmail(bad),
          'Enter a valid email address.',
          reason: '$bad should not pass the shape check',
        );
      }
    });
  });

  group('password', () {
    test('accepts the web minimum exactly', () {
      expect(kMinPasswordLength, 8);
      expect(validatePassword('12345678'), isNull);
    });

    test('rejects one character short', () {
      expect(
        validatePassword('1234567'),
        'Password must be at least 8 characters.',
      );
    });

    test('asks for one when empty', () {
      expect(validatePassword(''), 'Choose a password.');
      expect(validatePassword(null), 'Choose a password.');
    });

    test('never trims — a space is a character in a password', () {
      expect(validatePassword('       a'), isNull);
    });
  });

  group('otp', () {
    test('accepts a six digit code', () {
      expect(validateOtp('123456'), isNull);
    });

    test('accepts a code with stray whitespace around it', () {
      expect(validateOtp(' 123456 '), isNull);
    });

    test('does not assume six digits — the length is a project setting', () {
      expect(validateOtp('12345678'), isNull);
    });

    test('rejects anything that is not digits', () {
      expect(validateOtp('12a456'), 'The code is digits only.');
      expect(validateOtp('123-456'), 'The code is digits only.');
    });

    test('asks for the code when empty', () {
      expect(validateOtp(''), 'Enter the code we emailed you.');
      expect(validateOtp(null), 'Enter the code we emailed you.');
    });
  });

  group('parsePercent', () {
    test('a blank service charge is zero, not an error', () {
      expect(parsePercent(''), 0);
      expect(parsePercent(null), 0);
      expect(parsePercent('  '), 0);
    });

    test('reads a whole number and a decimal', () {
      expect(parsePercent('10'), 10);
      expect(parsePercent('12.5'), 12.5);
    });

    test('surrounding whitespace does not change the number', () {
      expect(parsePercent(' 7 '), 7);
    });
  });
}
