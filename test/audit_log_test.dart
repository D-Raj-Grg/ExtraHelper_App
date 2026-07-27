import 'package:extrahelper/features/pos/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The manager log is only useful if every row names a thing and a person.
/// These are the shapes the server actually writes.
void main() {
  PosAuditEntry entry(
    String action,
    Map<String, dynamic> metadata, {
    Map<String, dynamic>? actor,
  }) => PosAuditEntry.fromRow({
    'id': 'a1',
    'action': action,
    'created_at': '2026-07-27T04:26:28.000Z',
    'metadata': metadata,
    'actor': actor,
  });

  group('subject', () {
    test('an 86 names the dish', () {
      expect(
        entry('item_86', {'name': 'Sukuti Sadeko', 'is_86': true}).subject,
        'Sukuti Sadeko',
      );
    });

    test('a table change names the table', () {
      expect(
        entry('table_state', {'label': 'A1', 'state': 'cleaning'}).subject,
        'A1',
      );
    });

    test('a void names the line once the repository merges it in', () {
      expect(
        entry('void', {
          'reason': 'guest changed their mind',
          'name_snapshot': 'Buff Sekuwa (KG)',
        }).subject,
        'Buff Sekuwa (KG)',
      );
    });

    test('a discount describes itself when there is nothing else', () {
      expect(
        entry('discount', {'type': 'percent', 'value': 10}).subject,
        '10% off',
      );
      expect(
        entry('discount', {'type': 'percent', 'value': 12.5}).subject,
        '12.5% off',
      );
      expect(
        entry('discount', {'type': 'flat', 'value': 50}).subject,
        '50 off',
      );
    });

    test('an unrecognised row degrades to a dash, never a crash', () {
      expect(entry('something_new', const {}).subject, '—');
    });
  });

  group('actor and reason', () {
    test('the username stands in when nobody set a full name', () {
      expect(
        entry(
          'void',
          {'reason': 'x'},
          actor: {'full_name': null, 'username': 'clixacom_a132'},
        ).actorName,
        'clixacom_a132',
      );
    });

    test('a full name wins when there is one', () {
      expect(
        entry(
          'void',
          {'reason': 'x'},
          actor: {'full_name': 'Dev Raj', 'username': 'devraj'},
        ).actorName,
        'Dev Raj',
      );
    });

    test('a blank reason reads as no reason, not an empty line', () {
      expect(entry('void', {'reason': '   '}).reason, isNull);
      expect(entry('discount', {'reason': null}).reason, isNull);
      expect(entry('void', {'reason': ' guest left '}).reason, 'guest left');
    });
  });
}
