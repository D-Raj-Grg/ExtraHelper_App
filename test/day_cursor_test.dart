import 'package:extrahelper/features/reports/day_report_providers.dart';
import 'package:extrahelper/features/tenant/tenant_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The cursor watches the active tenant so switching restaurants resets it;
/// nothing else here needs a network.
ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [activeTenantProvider.overrideWithValue(null)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('shiftDay', () {
    test('steps a day either way', () {
      expect(shiftDay('2026-08-22', -1), '2026-08-21');
      expect(shiftDay('2026-08-22', 1), '2026-08-23');
      expect(shiftDay('2026-08-22', 0), '2026-08-22');
    });

    test('crosses months and years', () {
      expect(shiftDay('2026-08-31', 1), '2026-09-01');
      expect(shiftDay('2026-09-01', -1), '2026-08-31');
      expect(shiftDay('2026-12-31', 1), '2027-01-01');
      expect(shiftDay('2027-01-01', -1), '2026-12-31');
    });

    test('handles February, leap and otherwise', () {
      expect(shiftDay('2028-02-28', 1), '2028-02-29');
      expect(shiftDay('2026-02-28', 1), '2026-03-01');
    });

    test('pads to a shape Postgres will accept back', () {
      expect(shiftDay('2026-01-09', 1), '2026-01-10');
      expect(shiftDay('2026-03-01', -1), '2026-02-28');
      expect(shiftDay('2026-09-30', 1), '2026-10-01');
    });

    test('survives a DST transition, because it never involves a zone', () {
      // Kathmandu has no DST, but tenants elsewhere do. A date string names a
      // day, not an instant, so the 25-hour day is simply not this function's
      // problem — which is exactly why the arithmetic is UTC.
      expect(shiftDay('2026-03-08', 1), '2026-03-09'); // US spring forward
      expect(shiftDay('2026-11-01', 1), '2026-11-02'); // US fall back
    });

    test('a malformed date comes back untouched rather than guessed at', () {
      expect(shiftDay('', 1), '');
      expect(shiftDay('today', 1), 'today');
      expect(shiftDay('2026-08', 1), '2026-08');
    });
  });

  group('DayCursorState', () {
    test('a null selection means today', () {
      const s = DayCursorState(knownToday: '2026-08-22');
      expect(s.isToday, isTrue);
      expect(s.canGoForward, isFalse);
    });

    test('forward is allowed only towards a known today', () {
      const s = DayCursorState(
        selected: '2026-08-20',
        knownToday: '2026-08-22',
      );
      expect(s.isToday, isFalse);
      expect(s.canGoForward, isTrue);
    });

    test('cannot page past today', () {
      const s = DayCursorState(
        selected: '2026-08-22',
        knownToday: '2026-08-22',
      );
      expect(s.isToday, isTrue);
      expect(s.canGoForward, isFalse);
    });

    test('an unknown today fails safe, rather than paging into tomorrow', () {
      // Before the first payload lands the app genuinely does not know what
      // day it is — it cannot work one out — so forward stays shut.
      const s = DayCursorState(selected: '2026-08-20');
      expect(s.canGoForward, isFalse);
      expect(s.isToday, isFalse);
    });

    test('string comparison orders days correctly across a month end', () {
      const s = DayCursorState(
        selected: '2026-08-31',
        knownToday: '2026-09-01',
      );
      expect(s.canGoForward, isTrue);
    });
  });

  group('DayCursor', () {
    test('starts on today, with today still unknown', () {
      final c = _container();
      final state = c.read(dayCursorProvider);
      expect(state.selected, isNull);
      expect(state.knownToday, isNull);
      expect(state.canGoBack, isFalse, reason: 'nothing to step back from yet');
      expect(state.canGoForward, isFalse);
    });

    test('remembering today does not change which day is asked for', () {
      // The invariant behind `dayReportProvider` watching `select(selected)`:
      // recording the server's answer must not look like a new request, or the
      // screen fetches the same day twice every time it opens.
      final c = _container();
      final before = c.read(dayCursorProvider).selected;
      c.read(dayCursorProvider.notifier).rememberToday('2026-08-22');
      final after = c.read(dayCursorProvider);

      expect(after.selected, before);
      expect(after.knownToday, '2026-08-22');
      expect(after.isToday, isTrue);
      expect(after.canGoBack, isTrue);
    });

    test('stepping back from today names the day before it', () {
      final c = _container();
      final cursor = c.read(dayCursorProvider.notifier);
      cursor.rememberToday('2026-08-22');
      cursor.previous();

      expect(c.read(dayCursorProvider).selected, '2026-08-21');
      expect(c.read(dayCursorProvider).isToday, isFalse);
      expect(c.read(dayCursorProvider).canGoForward, isTrue);
    });

    test('forward stops at today and cannot overshoot it', () {
      final c = _container();
      final cursor = c.read(dayCursorProvider.notifier);
      cursor.rememberToday('2026-08-22');
      cursor.previous();
      cursor.next();
      expect(c.read(dayCursorProvider).selected, '2026-08-22');

      cursor.next(); // already there
      expect(c.read(dayCursorProvider).selected, '2026-08-22');
    });

    test('back to today clears the date so the server re-resolves it', () {
      // Not "set selected to knownToday": a day boundary can pass while the
      // app is open, and only the server knows when.
      final c = _container();
      final cursor = c.read(dayCursorProvider.notifier);
      cursor.rememberToday('2026-08-22');
      cursor.previous();
      cursor.today();

      expect(c.read(dayCursorProvider).selected, isNull);
      expect(c.read(dayCursorProvider).knownToday, '2026-08-22');
    });

    // The screen feeds *every* payload's `day` into `rememberToday`, and a past
    // day's payload names that past day — not today. Recording it would collapse
    // `canGoForward` and strand the user on the day they stepped back to.
    test('a past day\'s payload does not become today', () {
      final c = _container();
      final cursor = c.read(dayCursorProvider.notifier);
      cursor.rememberToday('2026-08-22'); // payload for the null request
      cursor.previous();
      cursor.rememberToday('2026-08-21'); // payload for the past day

      final s = c.read(dayCursorProvider);
      expect(s.knownToday, '2026-08-22');
      expect(s.isToday, isFalse, reason: '"Back to today" must stay reachable');
      expect(s.canGoForward, isTrue);
    });

    test('stepping back repeatedly still leaves a way forward', () {
      final c = _container();
      final cursor = c.read(dayCursorProvider.notifier);
      cursor.rememberToday('2026-08-22');
      for (var i = 0; i < 3; i++) {
        cursor.previous();
        // What the screen's listener does on every refetch.
        cursor.rememberToday(c.read(dayCursorProvider).selected!);
      }
      expect(c.read(dayCursorProvider).selected, '2026-08-19');
      expect(c.read(dayCursorProvider).canGoForward, isTrue);

      for (var i = 0; i < 3; i++) {
        cursor.next();
        cursor.rememberToday(c.read(dayCursorProvider).selected!);
      }
      expect(c.read(dayCursorProvider).selected, '2026-08-22');
      expect(c.read(dayCursorProvider).canGoForward, isFalse);
    });

    test('back to today re-learns the day after a boundary passes', () {
      // The guard must not freeze `knownToday` forever: once the selection is
      // cleared, the next payload is an answer about today again.
      final c = _container();
      final cursor = c.read(dayCursorProvider.notifier);
      cursor.rememberToday('2026-08-22');
      cursor.previous();
      cursor.today();
      cursor.rememberToday('2026-08-23');

      expect(c.read(dayCursorProvider).knownToday, '2026-08-23');
    });

    test('stepping back before any payload does nothing', () {
      final c = _container();
      c.read(dayCursorProvider.notifier).previous();
      expect(c.read(dayCursorProvider).selected, isNull);
    });
  });
}
