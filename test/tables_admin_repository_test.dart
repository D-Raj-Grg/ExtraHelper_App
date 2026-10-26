import 'package:extrahelper/data/supabase/tables_admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateTableDraft', () {
    test('accepts a normal table', () {
      expect(validateTableDraft('T1', 4), isNull);
      expect(validateTableDraft(' T1 ', 50), isNull);
    });
    test('refuses blank labels and bad capacity', () {
      expect(validateTableDraft('  ', 4), isNotNull);
      expect(validateTableDraft('T1', 0), isNotNull);
      expect(validateTableDraft('T1', 51), isNotNull);
    });
  });
}
