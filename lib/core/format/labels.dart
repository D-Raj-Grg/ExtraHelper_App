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

/// Last resort for an enum this build doesn't know: "bill_requested" →
/// "Bill requested". Better than showing the raw value, worse than a real
/// label — add the label when you meet one of these.
String _humanize(String value) {
  if (value.isEmpty) return value;
  final spaced = value.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}
