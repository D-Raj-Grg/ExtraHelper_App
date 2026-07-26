import 'package:extrahelper/core/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Env', () {
    test('assertConfigured agrees with isConfigured', () {
      if (Env.isConfigured) {
        expect(Env.assertConfigured, returnsNormally);
      } else {
        // Fail loudly at startup rather than as an opaque network error later.
        expect(
          Env.assertConfigured,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('--dart-define-from-file=env.json'),
            ),
          ),
        );
      }
    });

    test('isConfigured requires both values', () {
      expect(
        Env.isConfigured,
        Env.supabaseUrl.isNotEmpty && Env.supabasePublishableKey.isNotEmpty,
      );
    });
  });
}
