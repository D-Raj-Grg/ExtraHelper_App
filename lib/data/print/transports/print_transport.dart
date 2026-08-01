import '../print_models.dart';

/// One way of getting bytes into a printer.
///
/// The bytes are already finished ESC/POS by the time they arrive here; a
/// transport's only job is the wire. That split is what lets a WiFi printer and
/// a Bluetooth printer share every line of ticket-building code.
abstract class PrintTransport {
  /// Which printers this transport is willing to drive. The claim asks for
  /// exactly these, so nothing is taken off the queue that cannot be finished.
  PrinterConnection get connection;

  /// True when this device could use it *right now* — Bluetooth off, or an
  /// unpaired printer, both mean no.
  Future<bool> get available;

  /// Send once. Copies are the caller's loop, deliberately: a printer that
  /// swallowed one copy and choked on the second should report the failure, not
  /// silently print one.
  Future<void> send(RenderedPrinter printer, String base64);
}

/// Thrown when the printer was reachable but said no, or was not reachable at
/// all. The job goes back on the queue as `failed` with this message attached,
/// which is what the Printers screen shows.
class PrintTransportFailure implements Exception {
  const PrintTransportFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
