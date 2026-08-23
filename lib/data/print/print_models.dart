/// Types shared by the printing layer.
///
/// Deliberately a plain module: the transports, the repository, the service and
/// the settings screen all import it, and none of them should drag Supabase or
/// Flutter in through the back door.
library;

/// How a printer is wired.
///
/// `usb` and `system` exist so the app can *recognise* a printer it cannot
/// drive and say so, rather than showing an unexplained gap in the list. Only a
/// desktop host can reach those, which this app is not.
enum PrinterConnection { network, usb, system, bluetooth }

PrinterConnection printerConnectionFrom(String? wire) => switch (wire) {
  'usb' => PrinterConnection.usb,
  'system' => PrinterConnection.system,
  'bluetooth' => PrinterConnection.bluetooth,
  _ => PrinterConnection.network,
};

String printerConnectionWire(PrinterConnection c) => switch (c) {
  PrinterConnection.network => 'network',
  PrinterConnection.usb => 'usb',
  PrinterConnection.system => 'system',
  PrinterConnection.bluetooth => 'bluetooth',
};

String printerConnectionLabel(PrinterConnection c) => switch (c) {
  PrinterConnection.network => 'WiFi / network',
  PrinterConnection.usb => 'USB',
  PrinterConnection.system => 'System printer',
  PrinterConnection.bluetooth => 'Bluetooth',
};

/// Text is ESC/POS characters; image is a rasterised ticket, which this app
/// cannot draw yet (see TASKS — Devanagari is phase 2). Knowing the mode is
/// what lets the claim ask only for work it can finish.
enum PrinterRenderMode { text, image }

PrinterRenderMode printerRenderModeFrom(String? wire) =>
    wire == 'image' ? PrinterRenderMode.image : PrinterRenderMode.text;

String printerRenderModeWire(PrinterRenderMode m) =>
    m == PrinterRenderMode.image ? 'image' : 'text';

/// A printer as the registry holds it. Same row the web settings screen edits;
/// this app only reads it.
class PrintPrinter {
  const PrintPrinter({
    required this.id,
    required this.name,
    required this.connection,
    required this.port,
    required this.paperWidth,
    required this.renderMode,
    required this.isActive,
    this.host,
    this.systemName,
    this.btAddress,
    this.branchId,
  });

  final String id;
  final String name;
  final PrinterConnection connection;
  final String? host;
  final int port;
  final String? systemName;
  final String? btAddress;
  final int paperWidth;
  final PrinterRenderMode renderMode;
  final bool isActive;
  final String? branchId;

  /// What this app can put on paper: a socket to port 9100, or a paired
  /// Bluetooth printer on Android. USB and system printers need a computer.
  bool get drivableHere =>
      connection == PrinterConnection.network ||
      connection == PrinterConnection.bluetooth;

  /// How it is addressed, for display.
  String get target => switch (connection) {
    PrinterConnection.network => '${host ?? '—'}:$port',
    PrinterConnection.bluetooth => btAddress ?? '—',
    PrinterConnection.system => systemName ?? '—',
    PrinterConnection.usb => 'USB',
  };

  static PrintPrinter fromJson(Map<String, dynamic> j) => PrintPrinter(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    connection: printerConnectionFrom(j['connection'] as String?),
    host: j['host'] as String?,
    port: (j['port'] as num?)?.toInt() ?? 9100,
    systemName: j['system_name'] as String?,
    btAddress: j['bt_address'] as String?,
    paperWidth: (j['paper_width'] as num?)?.toInt() ?? 80,
    renderMode: printerRenderModeFrom(j['render_mode'] as String?),
    isActive: (j['is_active'] as bool?) ?? true,
    branchId: j['branch_id'] as String?,
  );
}

/// A row of the queue, for the settings screen's job list.
class PrintJob {
  const PrintJob({
    required this.id,
    required this.doc,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.error,
    this.printerName,
    this.claimedBy,
  });

  final String id;
  final String doc;
  final String status;
  final int attempts;
  final DateTime createdAt;
  final String? error;
  final String? printerName;
  final String? claimedBy;

  static PrintJob fromJson(Map<String, dynamic> j) => PrintJob(
    id: (j['id'] as String?) ?? '',
    doc: (j['doc'] as String?) ?? '',
    status: (j['status'] as String?) ?? 'queued',
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    createdAt:
        DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal() ??
        DateTime.now(),
    error: j['error'] as String?,
    printerName: (j['printers'] as Map<String, dynamic>?)?['name'] as String?,
    claimedBy: j['claimed_by'] as String?,
  );
}

/// A printer a document is bound for, and how many copies that printer is
/// configured to run. A manual reprint has to honour "two copies of every bill"
/// exactly as auto-print does, so the count travels with the target.
class PrintTarget {
  const PrintTarget({required this.printerId, required this.copies});

  final String printerId;
  final int copies;
}

/// What asking for paper produced.
///
/// `noPrinter` is not a failure: nothing is *set up* to print this document,
/// which the web answers with a browser fallback page. A phone has no such
/// page, so the caller says so and stops.
sealed class EnqueueOutcome {
  const EnqueueOutcome();
}

class PrintQueued extends EnqueueOutcome {
  const PrintQueued(this.jobIds);

  final List<String> jobIds;
}

class PrintNoPrinter extends EnqueueOutcome {
  const PrintNoPrinter();
}

/// A job this device has taken off the queue and now owes paper for.
class ClaimedPrintJob {
  const ClaimedPrintJob({required this.id, required this.doc, this.printerId});

  final String id;
  final String doc;
  final String? printerId;

  static ClaimedPrintJob fromJson(Map<String, dynamic> j) => ClaimedPrintJob(
    id: (j['id'] as String?) ?? '',
    doc: (j['doc'] as String?) ?? '',
    printerId: j['printer_id'] as String?,
  );
}

/// What `/api/print/render` hands back: finished ESC/POS, the printer it is
/// addressed to, and how many copies that printer is configured for.
class PreparedPrintJob {
  const PreparedPrintJob({
    required this.jobId,
    required this.copies,
    required this.label,
    this.printer,
    this.base64,
    this.isImagePayload = false,
  });

  final String jobId;
  final int copies;
  final String label;
  final RenderedPrinter? printer;

  /// Null when the payload was an image document — this app has no rasteriser
  /// yet, so it declines the job with a sentence instead of printing nothing.
  final String? base64;
  final bool isImagePayload;

  static PreparedPrintJob fromJson(Map<String, dynamic> j) {
    final payload = (j['payload'] as Map<String, dynamic>?) ?? const {};
    final printer = j['printer'] as Map<String, dynamic>?;
    return PreparedPrintJob(
      jobId: (j['jobId'] as String?) ?? '',
      copies: (j['copies'] as num?)?.toInt() ?? 1,
      label: (j['label'] as String?) ?? 'ticket',
      printer: printer == null ? null : RenderedPrinter.fromJson(printer),
      base64: payload['kind'] == 'raw' ? payload['base64'] as String? : null,
      isImagePayload: payload['kind'] == 'image',
    );
  }
}

/// The printer as the render endpoint describes it — camelCase, unlike the
/// table row, because it comes from the TypeScript `PrinterRef`.
class RenderedPrinter {
  const RenderedPrinter({
    required this.id,
    required this.name,
    required this.connection,
    required this.port,
    this.host,
    this.btAddress,
  });

  final String id;
  final String name;
  final PrinterConnection connection;
  final String? host;
  final int port;
  final String? btAddress;

  static RenderedPrinter fromJson(Map<String, dynamic> j) => RenderedPrinter(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    connection: printerConnectionFrom(j['connection'] as String?),
    host: j['host'] as String?,
    port: (j['port'] as num?)?.toInt() ?? 9100,
    btAddress: j['btAddress'] as String?,
  );
}

/// What each print document is called on screen. Mirrors the web's `DOC_LABELS`
/// (`lib/print/types.ts`) — a ticket is described the same way whichever client
/// someone is looking at when they ring up about it.
const printDocLabels = <String, String>{
  'kot': 'Kitchen ticket',
  'bot': 'Bar ticket',
  'full_kot': 'Full ticket',
  'order_slip': 'Order slip',
  'bill': 'Bill',
  'receipt': 'Receipt',
  'day_report': 'Day close (Z)',
  'test': 'Test page',
};

String printDocLabel(String doc) => printDocLabels[doc] ?? doc;

/// One document a printer is set to fire on its own, and how many copies.
///
/// **Assigning a document to a printer is the auto-print switch.** A printer
/// with no documents still exists and can be picked by hand; it simply never
/// fires by itself.
class PrinterDocAssignment {
  const PrinterDocAssignment({required this.doc, required this.copies});

  final String doc;
  final int copies;

  static PrinterDocAssignment fromJson(Map<String, dynamic> j) =>
      PrinterDocAssignment(
        doc: (j['doc'] as String?) ?? '',
        copies: switch (j['copies']) {
          int n => n,
          num n => n.round(),
          _ => 1,
        },
      );

  String get label =>
      copies > 1 ? '${printDocLabel(doc)} ×$copies' : printDocLabel(doc);
}

/// A printer as the settings screen shows it: the printer plus the documents it
/// is bound to. The print loop uses the narrower [PrintPrinter] — it does not
/// care what a printer is *for*, only how to reach it.
class PrinterRegistryRow {
  const PrinterRegistryRow({required this.printer, required this.docs});

  final PrintPrinter printer;
  final List<PrinterDocAssignment> docs;

  static PrinterRegistryRow fromJson(Map<String, dynamic> j) {
    final docs = j['printer_documents'];
    return PrinterRegistryRow(
      printer: PrintPrinter.fromJson(j),
      docs: docs is List
          ? docs
                .whereType<Map<String, dynamic>>()
                .map(PrinterDocAssignment.fromJson)
                .toList()
          : const [],
    );
  }
}
