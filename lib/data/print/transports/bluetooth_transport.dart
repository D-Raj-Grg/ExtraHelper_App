import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../print_models.dart';
import 'print_transport.dart';

/// A paired thermal printer over Bluetooth.
///
/// The address lives on the printer row, because it is the same everywhere. The
/// *pairing* is per device and belongs to the operating system, which is why
/// [available] gates the claim rather than letting jobs fail one by one.
///
/// Android only. iOS classic Bluetooth needs an MFi chip these printers do not
/// carry; the plugin falls back to BLE there and reports *nearby* devices with
/// CoreBluetooth UUIDs rather than the MAC address a printer row holds. WiFi is
/// the answer on iPhone, and [supportedPlatform] is what keeps the app from
/// pretending otherwise.
///
/// **Two plugin traps, both paid for by reading its source:**
///
/// 1. Its permission request is commented out. On Android 12+ it only *checks*,
///    so without [requestPermission] the answer is "denied" forever and nothing
///    ever prints.
/// 2. When the permission is missing it returns from the method handler
///    *without completing the result*, so the Dart future never resolves. Every
///    call here is therefore given a timeout — an un-completing future would
///    otherwise wedge the drain loop and kill printing on the device until the
///    app was restarted.
class BluetoothPrintTransport implements PrintTransport {
  BluetoothPrintTransport();

  /// Bluetooth printing is an Android answer. See the class doc.
  static bool get supportedPlatform => Platform.isAndroid;

  static const _quick = Duration(seconds: 5);
  static const _slow = Duration(seconds: 15);

  /// The address currently connected. Reconnecting per job costs seconds and
  /// makes a three-station fire feel broken, so the link is kept while it works.
  String? _connectedTo;

  @override
  PrinterConnection get connection => PrinterConnection.bluetooth;

  @override
  Future<bool> get available async {
    if (!supportedPlatform) return false;
    try {
      // Order matters: everything below the permission check can hang when the
      // permission is missing, so the permission is what gets asked first.
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted
          .timeout(_quick);
      if (!granted) return false;
      return await PrintBluetoothThermal.bluetoothEnabled.timeout(_quick);
    } catch (_) {
      return false;
    }
  }

  /// Ask for "Nearby devices", once, from a button someone pressed.
  ///
  /// Deliberately not called from the drain loop: a permission dialog that
  /// appears on its own mid-service, over and over, is worse than no Bluetooth.
  Future<bool> requestPermission() async {
    if (!supportedPlatform) return false;
    try {
      final results = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();
      return results[Permission.bluetoothConnect]?.isGranted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// True when the user said no permanently — the only fix is system settings,
  /// so the UI needs to say that instead of offering the button again.
  Future<bool> get permanentlyDenied async {
    if (!supportedPlatform) return false;
    try {
      return await Permission.bluetoothConnect.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  /// Printers this device has paired with, for the settings screen.
  Future<List<({String name, String address})>> pairedPrinters() async {
    if (!supportedPlatform) return const [];
    try {
      final list = await PrintBluetoothThermal.pairedBluetooths.timeout(_quick);
      return [for (final d in list) (name: d.name, address: d.macAdress)];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> send(RenderedPrinter printer, String base64) async {
    if (!supportedPlatform) {
      throw PrintTransportFailure(
        '${printer.name} is a Bluetooth printer, which an iPhone cannot drive. '
        'Print it from an Android phone, or give the printer a WiFi address.',
      );
    }

    final address = printer.btAddress;
    if (address == null || address.isEmpty) {
      throw PrintTransportFailure(
        '${printer.name} has no Bluetooth address set.',
      );
    }

    await _ensureConnected(printer, address);

    bool ok;
    try {
      ok = await PrintBluetoothThermal.writeBytes(
        base64Decode(base64),
      ).timeout(_slow);
    } on TimeoutException {
      _connectedTo = null;
      throw PrintTransportFailure(
        '${printer.name} stopped responding mid-ticket. Check it is switched on '
        'and still paired.',
      );
    }

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
        if (await PrintBluetoothThermal.connectionStatus.timeout(_quick)) {
          return;
        }
      } catch (_) {
        // Treated as disconnected — falling through reconnects.
      }
      _connectedTo = null;
    }

    // A link to another printer has to go first: the plugin holds one at a time.
    if (_connectedTo != null) {
      await _disconnectQuietly();
    }

    bool connected;
    try {
      connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: address,
      ).timeout(_slow);
    } on TimeoutException {
      connected = false;
    }

    if (!connected) {
      throw PrintTransportFailure(
        'Could not connect to ${printer.name} ($address). '
        "Pair it in the phone's Bluetooth settings first, and check it is on.",
      );
    }
    _connectedTo = address;
  }

  Future<void> _disconnectQuietly() async {
    _connectedTo = null;
    try {
      await PrintBluetoothThermal.disconnect.timeout(_quick);
    } catch (_) {
      // Already gone, or wedged. Either way there is nothing to salvage.
    }
  }

  Future<void> dispose() async {
    if (_connectedTo == null) return;
    await _disconnectQuietly();
  }
}
