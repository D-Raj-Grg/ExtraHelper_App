import 'package:extrahelper/data/print/print_models.dart';
import 'package:extrahelper/data/print/print_repository.dart';
import 'package:extrahelper/data/print/print_service.dart';
import 'package:extrahelper/data/print/render_client.dart';
import 'package:extrahelper/data/print/transports/print_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  group('PrintService capability gate', () {
    test('a transport for a printer nobody owns is never even asked', () async {
      // Asking the Bluetooth plugin raises a permission dialog. A restaurant
      // with only WiFi printers must never be nagged for Bluetooth, least of
      // all every twenty seconds forever.
      final bluetooth = _SpyTransport(PrinterConnection.bluetooth);
      final service = _service(
        transports: [_SpyTransport(PrinterConnection.network), bluetooth],
        configured: const {PrinterConnection.network},
      );

      await service.drain();

      expect(bluetooth.asked, isFalse);
    });

    test('a configured transport is asked', () async {
      final bluetooth = _SpyTransport(PrinterConnection.bluetooth);
      final service = _service(
        transports: [bluetooth],
        configured: const {PrinterConnection.bluetooth},
      );

      await service.drain();

      expect(bluetooth.asked, isTrue);
    });

    test('nothing available means nothing is claimed', () async {
      // Claiming work this device cannot finish takes the ticket off the queue
      // and produces no paper — worse than leaving it for something that can.
      final offline = _SpyTransport(PrinterConnection.bluetooth, ready: false);
      final service = _service(
        transports: [offline],
        configured: const {PrinterConnection.bluetooth},
      );

      expect(await service.drain(), 0);
      expect(service.lastError, isNull);
    });
  });
}

/// A service pointed at a host that does not resolve.
///
/// Every assertion above is about what happens *before* the claim, and a claim
/// that does go out fails as a transient — which is exactly the shape of a
/// phone with no coverage, and must not throw out of `drain()`.
PrintService _service({
  required List<PrintTransport> transports,
  required Set<PrinterConnection> configured,
}) {
  final client = SupabaseClient(
    'https://nowhere.invalid',
    'test-publishable-key',
  );
  return PrintService(
    repository: PrintRepository(client, 'tenant'),
    renderClient: RenderClient(client, 'tenant'),
    transports: transports,
    claimer: 'test',
    configured: configured,
  );
}

class _SpyTransport implements PrintTransport {
  _SpyTransport(this.connection, {this.ready = true});

  @override
  final PrinterConnection connection;
  final bool ready;
  bool asked = false;

  @override
  Future<bool> get available async {
    asked = true;
    return ready;
  }

  @override
  Future<void> send(RenderedPrinter printer, String base64) async {
    throw StateError('nothing should be sent in these tests');
  }
}
