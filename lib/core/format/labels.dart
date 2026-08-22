/// Plain-English labels for the shared DB enums.
///
/// **Enum values never reach staff.** `bill_requested` becomes "Bill requested"
/// through a map, not a string replace — the fallback exists only so an enum
/// added server-side degrades readably instead of rendering raw snake_case.
///
/// Mirrors the web's `lib/table-constants.ts` and `lib/order-constants.ts`.
library;

const _tableStateLabels = {
  'free': 'Free',
  'occupied': 'Occupied',
  'reserved': 'Reserved',
  'bill_requested': 'Bill requested',
  'cleaning': 'Cleaning',
};

String tableStateLabel(String state) =>
    _tableStateLabels[state] ?? _humanize(state);

const _orderStatusLabels = {
  'draft': 'Draft',
  'placed': 'Placed',
  'in_kitchen': 'In kitchen',
  'preparing': 'Preparing',
  'ready': 'Ready',
  'served': 'Served',
  'billed': 'Billed',
  'closed': 'Closed',
  'cancelled': 'Cancelled',
};

String orderStatusLabel(String status) =>
    _orderStatusLabels[status] ?? _humanize(status);

const _orderTypeLabels = {
  'dine_in': 'Dine in',
  'pickup': 'Takeaway',
  'delivery': 'Delivery',
  'qr': 'QR order',
};

String orderTypeLabel(String type) => _orderTypeLabels[type] ?? _humanize(type);

const _billStatusLabels = {
  'open': 'Unpaid',
  'partial': 'Part paid',
  'paid': 'Paid',
  'void': 'Void',
  'refunded': 'Refunded',
};

String billStatusLabel(String status) =>
    _billStatusLabels[status] ?? _humanize(status);

const _paymentMethodLabels = {
  'cash': 'Cash',
  'card': 'Card',
  // Taken through a payment gateway on the web. The phone records it but never
  // offers it — there is no RPC behind the charge, only the web's server-side
  // adapter, so an app that offered "Card (online)" would log money it never
  // collected. See `TASKS.md`.
  'online': 'Card (online)',
  // Record-only: nothing is charged, the cashier records what the guest's
  // confirmation screen showed. Safe on the phone, unlike `online`.
  'esewa': 'eSewa',
  'fonepay': 'FonePay',
  'bank': 'Bank transfer',
  'wallet': 'Wallet',
  'points': 'Loyalty points',
};

String paymentMethodLabel(String method) =>
    _paymentMethodLabels[method] ?? _humanize(method);

const _roleLabels = {
  'owner': 'Owner',
  'manager': 'Manager',
  'receptionist': 'Receptionist',
  'cashier': 'Cashier',
  'waiter': 'Waiter',
  'kitchen': 'Kitchen',
  'inventory': 'Inventory',
};

String roleLabel(String role) => _roleLabels[role] ?? _humanize(role);

const _reservationStatusLabels = {
  'pending': 'Not confirmed',
  'confirmed': 'Confirmed',
  'seated': 'Seated',
  'cancelled': 'Cancelled',
  'no_show': 'No show',
};

String reservationStatusLabel(String status) =>
    _reservationStatusLabels[status] ?? _humanize(status);

/// When the trading day turns over, said the way a person would.
///
/// 240 → "4:00 am". Null at zero, because "starts at midnight" is the ordinary
/// case and saying it out loud only adds noise to a screen that has plenty.
///
/// 12-hour on screen deliberately, matching the web sheet; the thermal slip
/// prints 24-hour, where column width matters more than familiarity.
String? cutoffLabel(int minutes) {
  if (minutes <= 0) return null;
  final hour24 = minutes ~/ 60;
  final minute = minutes % 60;
  final period = hour24 < 12 ? 'am' : 'pm';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $period';
}

/// Last resort for an enum this build doesn't know: "bill_requested" →
/// "Bill requested". Better than showing the raw value, worse than a real
/// label — add the label when you meet one of these.
String _humanize(String value) {
  if (value.isEmpty) return value;
  final spaced = value.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}
