import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Ticket flow, ported from the web's `lib/kds-constants.ts`.
///
/// One place decides what a status is called, which icon carries it, what a tap
/// on it does and what tone it wears — the board, the line button, the dish
/// rail and the status sheet all read this, so the two clients cannot drift
/// into calling the same state different things.
enum KotStatus { newTicket, preparing, ready, served, recalled }

/// The bump flow. `recalled` is a real status but not a step in it: a recalled
/// ticket is back on the board, being cooked, and advances from there.
const kotFlow = [
  KotStatus.newTicket,
  KotStatus.preparing,
  KotStatus.ready,
  KotStatus.served,
];

KotStatus kotStatusFrom(String raw) => switch (raw) {
  'new' => KotStatus.newTicket,
  'preparing' => KotStatus.preparing,
  'ready' => KotStatus.ready,
  'served' => KotStatus.served,
  'recalled' => KotStatus.recalled,
  _ => KotStatus.newTicket,
};

String kotStatusWire(KotStatus s) => switch (s) {
  KotStatus.newTicket => 'new',
  KotStatus.preparing => 'preparing',
  KotStatus.ready => 'ready',
  KotStatus.served => 'served',
  KotStatus.recalled => 'recalled',
};

/// Next status in the bump flow, or null when there is nowhere further to go.
KotStatus? nextKotStatus(KotStatus s) {
  // A recalled ticket rejoins the flow at "cooking" — it is back on the pass.
  if (s == KotStatus.recalled) return KotStatus.ready;
  final i = kotFlow.indexOf(s);
  if (i < 0 || i >= kotFlow.length - 1) return null;
  return kotFlow[i + 1];
}

/// Where a status sits when a ticket is derived from its lines. Mirrors the
/// rank ladder inside `set_kot_item_status`, so the optimistic answer on the
/// phone matches the one the server writes.
int kotStatusRank(KotStatus s) => switch (s) {
  KotStatus.newTicket => 1,
  KotStatus.preparing => 2,
  KotStatus.recalled => 2,
  KotStatus.ready => 3,
  KotStatus.served => 4,
};

KotStatus kotStatusOfRank(int rank) => switch (rank) {
  1 => KotStatus.newTicket,
  2 => KotStatus.preparing,
  3 => KotStatus.ready,
  _ => KotStatus.served,
};

/// Everything a surface needs to render a status. Colour is never the only
/// carrier: every consumer pairs [tone] with [icon] and [label], so the board
/// survives a greyscale screenshot.
class KotStatusMeta {
  const KotStatusMeta({
    required this.label,
    required this.icon,
    required this.hint,
    required this.action,
  });

  /// Plain English. A cook never sees `bill_requested` or `new`.
  final String label;
  final IconData icon;

  /// What this status means, for the status sheet.
  final String hint;

  /// Verb on the button that moves a line *into* this status.
  final String action;
}

const kotStatusMeta = <KotStatus, KotStatusMeta>{
  KotStatus.newTicket: KotStatusMeta(
    label: 'New',
    icon: Icons.schedule,
    hint: 'Waiting on the kitchen',
    action: 'Reset',
  ),
  KotStatus.preparing: KotStatusMeta(
    label: 'Cooking',
    icon: Icons.local_fire_department,
    hint: 'On the pass right now',
    action: 'Start',
  ),
  KotStatus.ready: KotStatusMeta(
    label: 'Ready',
    icon: Icons.notifications_active,
    hint: 'Plated, waiting for pickup',
    action: 'Ready',
  ),
  KotStatus.served: KotStatusMeta(
    label: 'Served',
    icon: Icons.check_circle,
    hint: 'Delivered to the guest',
    action: 'Served',
  ),
  KotStatus.recalled: KotStatusMeta(
    label: 'Recalled',
    icon: Icons.undo,
    hint: 'Pulled back onto the board',
    action: 'Recall',
  ),
};

/// Status tone. Semantic colours only — `context.semantic`, never a raw
/// `Colors.green`.
Color kotStatusColor(BuildContext context, KotStatus s) {
  final semantic = context.semantic;
  return switch (s) {
    KotStatus.newTicket => semantic.infoText,
    KotStatus.preparing => semantic.warningText,
    KotStatus.ready => semantic.goodText,
    KotStatus.served => semantic.neutral,
    KotStatus.recalled => semantic.attentionText,
  };
}

/// How long a ticket has been open.
///
/// Stated in minutes **and** carried by an icon, because a kitchen screen is
/// read across a room, often by someone colourblind, and "the red one" is not
/// a specification.
class TicketAge {
  const TicketAge({
    required this.minutes,
    required this.label,
    required this.late,
  });

  final int minutes;
  final String label;
  final bool late;

  IconData get icon => late ? Icons.warning_amber : Icons.schedule;
}

TicketAge ticketAge(DateTime createdAt, DateTime now) {
  final mins = now.difference(createdAt).inMinutes;
  return TicketAge(
    minutes: mins,
    label: mins <= 0 ? 'just now' : '${mins}m',
    late: mins >= 10,
  );
}

Color ticketAgeColor(BuildContext context, TicketAge age) {
  final semantic = context.semantic;
  if (age.minutes < 5) return semantic.goodText;
  if (age.minutes < 10) return semantic.warningText;
  return semantic.dangerText;
}

/// The board's query shape. Shared by the first load and every realtime
/// refetch — if the two diverge, the first ping visibly strips the tickets.
const kdsSelect =
    'id, status, created_at, printed_at, station_id, order_id, '
    'kitchen_stations(name), '
    'orders(status, table_id, restaurant_tables!orders_table_id_fkey(label)), '
    'kot_items(id, qty, status, '
    'order_items(id, name_snapshot, is_void, notes, '
    'order_item_modifiers(name_snapshot, qty)))';

/// How far back a served ticket stays recallable. Matches the web board.
const recallWindow = Duration(minutes: 20);
