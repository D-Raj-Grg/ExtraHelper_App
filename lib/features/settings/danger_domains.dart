/// The wipeable domains, in the order the web's reset dialog lists them.
///
/// A port of `extrahelper/lib/danger-constants.ts`. The keys are the contract —
/// `reset_tenant` matches on them — so they are copied verbatim rather than
/// derived.
class ResetDomain {
  const ResetDomain(this.key, this.label, this.detail);

  final String key;

  /// Staff-facing name. Enum values never reach the UI.
  final String label;

  /// What gets wiped, one short line.
  final String detail;
}

const resetDomains = <ResetDomain>[
  ResetDomain('menu', 'Menu', 'Dishes, categories, prices, recipes'),
  ResetDomain('tables', 'Tables', 'Tables & reservations'),
  ResetDomain('finance', 'Finance', 'Bills, payments, cash sessions'),
  ResetDomain('space', 'Space', 'Floors & layout'),
  ResetDomain('customers', 'Customers', 'Guests, loyalty, feedback'),
  ResetDomain('suppliers', 'Suppliers', 'Vendors & purchase orders'),
  ResetDomain('inventory', 'Inventory', 'Stock, counts, wastage'),
  ResetDomain('website', 'Website', 'Online orders & delivery'),
  ResetDomain('staff', 'Staff Members', 'Team, invites, shifts (not you)'),
  ResetDomain('orders', 'Orders', 'Orders & KOT tickets'),
  ResetDomain('activity', 'Activity', 'Audit log history'),
];

/// Sentinel domain: expands to every domain server-side.
const resetEverything = 'everything';
