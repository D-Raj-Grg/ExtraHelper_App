import 'package:extrahelper/data/print/print_routing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Routing decides which machine a reprint comes out of, and a wrong answer is
/// paper in the wrong room. These are the rules the web already settled, ported
/// here — if the two clients disagree, one of them is printing bar drinks on
/// the kitchen roll.

void main() {
  group('kot routing', () {
    test('a bar station makes it a BOT, whatever the caller asked for', () {
      final routing = kotRoutingFrom({
        'kitchen_stations': {'kind': 'bar', 'printer_id': null},
        'orders': {'branch_id': null},
      });

      expect(routing.doc, 'bot');
    });

    test('a kitchen station makes it a KOT', () {
      final routing = kotRoutingFrom({
        'kitchen_stations': {'kind': 'kitchen', 'printer_id': null},
        'orders': {'branch_id': null},
      });

      expect(routing.doc, 'kot');
    });

    test('a missing row still names a document rather than throwing', () {
      // A ticket deleted between tapping and asking is a real race, and the
      // answer is a queued job nobody claims, not a crash on the pass.
      expect(kotRoutingFrom(null).doc, 'kot');
      expect(kotRoutingFrom(null).station, isNull);
    });

    test("the station's own printer routes it, one copy", () {
      final routing = kotRoutingFrom({
        'kitchen_stations': {'kind': 'kitchen', 'printer_id': 'p-grill'},
        'orders': {'branch_id': 'b1'},
      });

      expect(routing.station?.printerId, 'p-grill');
      expect(routing.station?.copies, 1);
      expect(routing.branchId, 'b1');
    });
  });

  group('printer_documents targets', () {
    Map<String, dynamic> row(
      String id, {
      int copies = 1,
      bool active = true,
      String? branch,
    }) => {
      'printer_id': id,
      'copies': copies,
      'printers': {'is_active': active, 'branch_id': branch},
    };

    test('copies travel with the target', () {
      // "Two copies of every bill" is a printer setting, and a manual reprint
      // has to honour it exactly as auto-print does.
      final targets = printerDocumentTargets([row('p1', copies: 2)]);

      expect(targets.single.printerId, 'p1');
      expect(targets.single.copies, 2);
    });

    test('an inactive printer is skipped', () {
      expect(printerDocumentTargets([row('p1', active: false)]), isEmpty);
    });

    test("another branch's printer is skipped", () {
      final targets = printerDocumentTargets([
        row('here', branch: 'b1'),
        row('elsewhere', branch: 'b2'),
        row('everywhere'),
      ], branchId: 'b1');

      expect(targets.map((t) => t.printerId), ['here', 'everywhere']);
    });

    test('a document with no branch prints on every branch printer', () {
      // A test page and a bill with no branch belong to the whole restaurant.
      final targets = printerDocumentTargets([
        row('b1p', branch: 'b1'),
        row('b2p', branch: 'b2'),
      ]);

      expect(targets.length, 2);
    });

    test('nothing configured resolves to no targets, not a wrong one', () {
      expect(printerDocumentTargets(const []), isEmpty);
    });
  });
}
