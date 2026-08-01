import 'dart:convert';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../print_models.dart';
import 'print_transport.dart';

/// A paired thermal printer over Bluetooth.
///
/// The address lives on the printer row, because it is the same everywhere. The
/// *pairing* is per device and belongs to the operating system: a phone that
/// has never paired with the printer cannot open it, which is why
/// [available] gates the claim rather than letting jobs fail one by one.
///
/// Android is the reliable platform here — classic SPP, the profile these
/// printers speak. On iOS the plugin talks BLE and lists nearby devices rather
/// than paired ones, so it works only with a printer that exposes a BLE serial
/// service. WiFi is the answer on iPhone.
class BluetoothPrintTransport implements PrintTransport {
  BluetoothPrintTransport();

  /// The address currently connected. Reconnecting per job costs seconds and
  /// makes a three-station fire feel broken, so the link is kept while it works.
  String? _connectedTo;

  @override
  PrinterConnection get connection => PrinterConnection.bluetooth;

  @override
  Future<bool> get available async {
    try {
      if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
        return false;
      }
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Printers this device has paired with, for the settings screen. On iOS this
  /// is "nearby", not "paired" — the plugin's own distinction.
  Future<List<({String name, String address})>> pairedPrinters() async {
    try {
      final list = await PrintBluetoothThermal.pairedBluetooths;
      return [for (final d in list) (name: d.name, address: d.macAdress)];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> send(RenderedPrinter printer, String base64) async {
    final address = printer.btAddress;
    if (address == null || address.isEmpty) {
      throw PrintTransportFailure(
        '${printer.name} has no Bluetooth address set.',
      );
    }

    await _ensureConnected(printer, address);

    final ok = await PrintBluetoothThermal.writeBytes(base64Decode(base64));
    if (!ok) {
      // The link looked open but the write did not land — most often the
      // printer went to sleep. Drop it so the next attempt reconnects properly
      // instead of writing into a dead socket forever.
      _connectedTo = null;
      throw PrintTransportFailure(
        '${printer.name} did not accept the ticket. '
        'Check it is switched on, has paper, and is still paired.',
      );
    }
  }

  Future<void> _ensureConnected(RenderedPrinter printer, String address) async {
    if (_connectedTo == address) {
      try {
        if (await PrintBluetoothThermal.connectionStatus) return;
      } catch (_) {
        // Treated as disconnected — falling through reconnects.
      }
      _connectedTo = null;
    }

    // A link to another printer has to go first: the plugin holds one at a time.
    if (_connectedTo != null) {
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {
        // Already gone. Nothing to clean up.
      }
      _connectedTo = null;
    }

    final connected = await PrintBluetoothThermal.connect(
      macPrinterAddress: address,
    );
    if (!connected) {
      throw PrintTransportFailure(
        'Could not connect to ${printer.name} ($address). '
        'Pair it in the phone\'s Bluetooth settings first, and check it is on.',
      );
    }
    _connectedTo = address;
  }

  Future<void> dispose() async {
    if (_connectedTo == null) return;
    _connectedTo = null;
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {
      // Shutting down anyway.
    }
  }
}
