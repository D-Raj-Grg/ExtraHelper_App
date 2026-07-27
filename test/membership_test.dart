import 'package:extrahelper/data/supabase/tenant_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Membership.fromRow', () {
    test('reads currency and timezone from the nested settings', () {
      final m = Membership.fromRow({
        'tenant_id': 't1',
        'role': 'waiter',
        'tenants': {
          'name': 'D raj',
          'slug': 'd-raj',
          'tenant_settings': {'currency': 'NPR', 'timezone': 'Asia/Kathmandu'},
        },
      });
      expect(m.name, 'D raj');
      expect(m.currency, 'NPR');
      expect(m.timezone, 'Asia/Kathmandu');
      expect(m.role, 'waiter');
    });

    test('handles settings arriving as a single-element list', () {
      // PostgREST returns an embedded one-to-one as either shape depending on
      // the relationship it infers — both must work or currency silently
      // falls back to USD for a Nepali restaurant.
      final m = Membership.fromRow({
        'tenant_id': 't1',
        'role': 'manager',
        'tenants': {
          'name': 'D raj',
          'slug': 'd-raj',
          'tenant_settings': [
            {'currency': 'INR', 'timezone': 'Asia/Kolkata'},
          ],
        },
      });
      expect(m.currency, 'INR');
      expect(m.timezone, 'Asia/Kolkata');
    });

    test('a tenant with no settings row falls back, never crashes', () {
      final m = Membership.fromRow({
        'tenant_id': 't1',
        'role': 'waiter',
        'tenants': {'name': 'New place', 'slug': 'new', 'tenant_settings': []},
      });
      expect(m.currency, 'USD');
      expect(m.timezone, 'UTC');
    });

    test('survives a missing tenant embed', () {
      final m = Membership.fromRow({'tenant_id': 't1', 'role': 'waiter'});
      expect(m.tenantId, 't1');
      expect(m.name, '');
      expect(m.currency, 'USD');
    });
  });
}
