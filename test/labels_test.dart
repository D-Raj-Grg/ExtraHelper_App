import 'package:extrahelper/core/format/labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('labels', () {
    test('enum values never reach staff', () {
      expect(tableStateLabel('bill_requested'), 'Bill requested');
      expect(orderStatusLabel('in_kitchen'), 'In kitchen');
      expect(orderTypeLabel('pickup'), 'Takeaway'); // not "Pickup"
      expect(billStatusLabel('open'), 'Unpaid'); // not "Open"
    });

    test('every DB enum value has a real label, not the fallback', () {
      const tableStates = [
        'free',
        'occupied',
        'reserved',
        'bill_requested',
        'cleaning',
      ];
      const orderStatuses = [
        'draft',
        'placed',
        'in_kitchen',
        'preparing',
        'ready',
        'served',
        'billed',
        'closed',
        'cancelled',
      ];
      const orderTypes = ['dine_in', 'delivery', 'pickup', 'qr'];
      const billStatuses = ['open', 'partial', 'paid', 'void'];
      const roles = [
        'owner',
        'manager',
        'receptionist',
        'cashier',
        'waiter',
        'kitchen',
        'inventory',
      ];

      for (final v in tableStates) {
        expect(tableStateLabel(v), isNot(contains('_')));
      }
      for (final v in orderStatuses) {
        expect(orderStatusLabel(v), isNot(contains('_')));
      }
      for (final v in orderTypes) {
        expect(orderTypeLabel(v), isNot(contains('_')));
      }
      for (final v in billStatuses) {
        expect(billStatusLabel(v), isNot(contains('_')));
      }
      for (final v in roles) {
        expect(roleLabel(v), isNot(contains('_')));
      }
      // Every `payment_method` the DB can hold, including `online` — the phone
      // never offers it, but a bill settled on the web can carry one and the
      // payments list must not print the raw enum at the guest.
      for (final v in ['cash', 'card', 'online', 'wallet', 'points']) {
        expect(paymentMethodLabel(v), isNot(contains('_')));
      }
      expect(paymentMethodLabel('points'), 'Loyalty points');
    });

    test('an enum added server-side degrades readably', () {
      expect(tableStateLabel('being_scrubbed'), 'Being scrubbed');
    });
  });
}
