import 'package:extrahelper/core/format/labels.dart';
import 'package:extrahelper/data/supabase/reservations_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Reservation.fromRow', () {
    test('parses a full row with map joins', () {
      final r = Reservation.fromRow({
        'id': 'r-1',
        'table_id': 't-1',
        'party_size': 4,
        'reserved_at': '2026-10-26T13:00:00+00:00',
        'status': 'confirmed',
        'notes': ' Window seat ',
        'customers': {'name': 'Sita Rai', 'phone': '9800000000'},
        'restaurant_tables': {'label': 'T4'},
      });
      expect(r.guestName, 'Sita Rai');
      expect(r.guestPhone, '9800000000');
      expect(r.tableLabel, 'T4');
      expect(r.partySize, 4);
      expect(r.status, ReservationStatus.confirmed);
      expect(r.notes, 'Window seat');
      expect(r.reservedAt.isUtc, isFalse);
      expect(r.reservedAt.toUtc(), DateTime.utc(2026, 10, 26, 13));
    });

    test('tolerates null joins and list-shaped joins', () {
      final bare = Reservation.fromRow({
        'id': 'r-2',
        'table_id': null,
        'party_size': '2',
        'reserved_at': '2026-10-26T13:00:00Z',
        'status': 'weird',
        'notes': null,
        'customers': null,
        'restaurant_tables': null,
      });
      expect(bare.guestName, 'Guest');
      expect(bare.guestPhone, isNull);
      expect(bare.tableLabel, isNull);
      expect(bare.partySize, 2);
      expect(bare.status, ReservationStatus.pending);

      final listy = Reservation.fromRow({
        'id': 'r-3',
        'party_size': 3,
        'reserved_at': '2026-10-26T13:00:00Z',
        'status': 'no_show',
        'customers': [
          {'name': 'Ram', 'phone': null},
        ],
        'restaurant_tables': [
          {'label': 'T1'},
        ],
      });
      expect(listy.guestName, 'Ram');
      expect(listy.tableLabel, 'T1');
      expect(listy.status, ReservationStatus.noShow);
    });
  });

  group('ReservationStatus', () {
    test('wire round-trips', () {
      for (final s in ReservationStatus.values) {
        expect(ReservationStatus.fromWire(s.wire), s);
      }
      expect(ReservationStatus.noShow.wire, 'no_show');
      expect(ReservationStatus.fromWire(null), ReservationStatus.pending);
    });

    test('isOpen and nextStatuses', () {
      expect(ReservationStatus.pending.isOpen, isTrue);
      expect(ReservationStatus.seated.isOpen, isFalse);
      expect(ReservationStatus.pending.nextStatuses, [
        ReservationStatus.confirmed,
        ReservationStatus.cancelled,
      ]);
      expect(ReservationStatus.confirmed.nextStatuses, [
        ReservationStatus.seated,
        ReservationStatus.noShow,
        ReservationStatus.cancelled,
      ]);
      expect(ReservationStatus.cancelled.nextStatuses, isEmpty);
    });

    test('labels', () {
      expect(reservationStatusLabelFor(ReservationStatus.noShow), 'No-show');
      expect(reservationStatusLabel('no_show'), isNotEmpty);
    });
  });

  group('ReservationDraft.validate', () {
    test('requires a name and a sane party', () {
      expect(ReservationDraft(name: ' ').validate(), isNotNull);
      expect(ReservationDraft(name: 'A', partySize: 0).validate(), isNotNull);
      expect(ReservationDraft(name: 'A', partySize: 51).validate(), isNotNull);
      expect(ReservationDraft(name: 'A', partySize: 50).validate(), isNull);
    });
  });
}
