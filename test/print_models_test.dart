import 'package:extrahelper/data/print/print_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The printing layer's parsing rules, which decide two things that matter on
/// paper: what this device is willing to claim, and how a printer is addressed.
void main() {
  group('PrintPrinter', () {
    test('a WiFi printer is drivable and addressed by host:port', () {
      final p = PrintPrinter.fromJson({
        'id': 'p1',
        'name': 'Kitchen',
        'connection': 'network',
        'host': '192.168.1.50',
        'port': 9100,
        'paper_width': 80,
        'render_mode': 'text',
        'is_active': true,
      });

      expect(p.connection, PrinterConnection.network);
      expect(p.drivableHere, isTrue);
      expect(p.target, '192.168.1.50:9100');
    });

    test('a Bluetooth printer is drivable and addressed by its MAC', () {
      final p = PrintPrinter.fromJson({
        'id': 'p2',
        'name': 'Counter',
        'connection': 'bluetooth',
        'bt_address': '66:32:B1:00:1A:2C',
        'paper_width': 58,
        'render_mode': 'text',
        'is_active': true,
      });

      expect(p.drivableHere, isTrue);
      expect(p.target, '66:32:B1:00:1A:2C');
    });

    test('USB and system printers are recognised but not drivable', () {
      for (final wire in ['usb', 'system']) {
        final p = PrintPrinter.fromJson({
          'id': 'p3',
          'name': 'Back office',
          'connection': wire,
          'system_name': 'EPSON TM-T88VI',
          'paper_width': 80,
          'render_mode': 'text',
          'is_active': true,
        });
        expect(p.drivableHere, isFalse, reason: wire);
      }
    });

    test('an unknown connection falls back to network, never to null', () {
      final p = PrintPrinter.fromJson({
        'id': 'p4',
        'connection': 'carrier-pigeon',
      });
      expect(p.connection, PrinterConnection.network);
      expect(p.port, 9100);
      expect(p.paperWidth, 80);
    });
  });

  group('PreparedPrintJob', () {
    test('a raw payload carries the bytes to send', () {
      final job = PreparedPrintJob.fromJson({
        'jobId': 'j1',
        'copies': 2,
        'label': 'KOT · Grill',
        'printer': {
          'id': 'p1',
          'name': 'Kitchen',
          'connection': 'network',
          'host': '192.168.1.50',
          'port': 9100,
        },
        'payload': {'kind': 'raw', 'base64': 'GyFA'},
      });

      expect(job.base64, 'GyFA');
      expect(job.isImagePayload, isFalse);
      expect(job.copies, 2);
      expect(job.printer?.host, '192.168.1.50');
    });

    test('an image payload has no bytes, so the service can decline it', () {
      // This is the Devanagari path: the ticket is drawn by a browser, and this
      // app has no rasteriser yet. Declining with a sentence beats printing
      // question marks.
      final job = PreparedPrintJob.fromJson({
        'jobId': 'j2',
        'copies': 1,
        'label': 'Bill',
        'printer': {'id': 'p1', 'name': 'Counter', 'connection': 'network'},
        'payload': {
          'kind': 'image',
          'doc': {'blocks': []},
          'paperWidthMm': 80,
        },
      });

      expect(job.isImagePayload, isTrue);
      expect(job.base64, isNull);
    });
  });
}
