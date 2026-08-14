import 'package:extrahelper/features/pos/bill_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the Bills tab asks the server for.
///
/// Two rules live here, and both are the kind that fail quietly: a debt that
/// disappears at midnight, and a status Postgres has never heard of.

void main() {
  group('BillFilter', () {
    test('what is owed is never capped to today', () {
      // A table that walked out on a part-paid bill last night is still money
      // owed this morning. Day-bounding it would put that bill out of reach.
      expect(BillFilter.owed.dayBound, isFalse);
      expect(BillFilter.owed.statuses, ['open', 'partial']);
    });

    test('settled bills are capped to today', () {
      // Otherwise the query grows for the life of the restaurant to answer a
      // question the reports answer better.
      expect(BillFilter.paid.dayBound, isTrue);
      expect(BillFilter.voided.dayBound, isTrue);
      expect(BillFilter.today.dayBound, isTrue);
    });

    test('no filter asks for a status the enum does not have', () {
      // `bill_status` is open | partial | paid | void. "Refunded" is a label
      // the app can render but not a value it can filter on — asking for it is
      // a runtime 22P02, not a compile error, so this is the guard.
      const real = {'open', 'partial', 'paid', 'void'};
      for (final filter in BillFilter.values) {
        expect(
          filter.statuses.every(real.contains),
          isTrue,
          reason: '${filter.name} asks for something outside bill_status',
        );
        expect(filter.statuses, isNot(contains('refunded')));
      }
    });

    test('every status a bill can hold is reachable from some filter', () {
      // The whole point of the tab: a bill paid five minutes ago used to be
      // unreachable from the phone.
      final reachable = {for (final f in BillFilter.values) ...f.statuses};
      expect(reachable, containsAll(['open', 'partial', 'paid', 'void']));
    });

    test('the tab opens on what is owed', () {
      expect(BillFilter.values.first, BillFilter.owed);
    });
  });
}
