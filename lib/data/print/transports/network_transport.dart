import 'dart:convert';
import 'dart:io';

import '../print_models.dart';
import 'print_transport.dart';

/// A thermal printer on the shop's WiFi, spoken to directly on port 9100.
///
/// This is the whole answer to "the printer does not support browser print": a
/// browser has no raw socket, and a native app does. Nothing is installed on
/// any computer, and the phone does not need to be able to reach the internet
/// once the ticket has been rendered — only the printer.
class NetworkPrintTransport implements PrintTransport {
  const NetworkPrintTransport({
    this.timeout = const Duration(seconds: 10),
    this.drainDelay = const Duration(milliseconds: 250),
  });

  final Duration timeout;

  /// A moment between the last byte and the FIN. Closing immediately is how a
  /// ticket ends up truncated on a printer whose buffer had not caught up.
  final Duration drainDelay;

  @override
  PrinterConnection get connection => PrinterConnection.network;

  /// A socket needs no permission and no pairing; whether *this* printer
  /// answers is discovered by trying, and that failure is per-job.
  @override
  Future<bool> get available async => true;

  @override
  Future<void> send(RenderedPrinter printer, String base64) async {
    final host = printer.host;
    if (host == null || host.isEmpty) {
      throw PrintTransportFailure('${printer.name} has no IP address set.');
    }

    Socket? socket;
    try {
      // Deliberately not a kept-open connection. A thermal printer that has sat
      // idle for an hour will often accept bytes on a stale socket and print
      // nothing at all, with no way to tell from this side.
      socket = await Socket.connect(host, printer.port, timeout: timeout);
      socket.add(base64Decode(base64));
      await socket.flush().timeout(timeout);
      await Future<void>.delayed(drainDelay);
    } on SocketException catch (e) {
      throw PrintTransportFailure(
        '${printer.name} at $host:${printer.port} did not answer '
        '(${e.osError?.message ?? 'no route'}). '
        'Check it is switched on and on this WiFi.',
      );
    } catch (e) {
      throw PrintTransportFailure('${printer.name}: $e');
    } finally {
      socket?.destroy();
    }
  }

  /// Is anything listening? Used by the Printers screen so a bad address shows
  /// up before service, not during it.
  Future<bool> reachable(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
