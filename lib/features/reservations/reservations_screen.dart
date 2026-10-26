import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/format/labels.dart';
import '../../core/format/when.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/notice.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/supabase/reservations_repository.dart';
import '../tenant/tenant_providers.dart';
import 'no_reservation_access.dart';
import 'reservation_sheet.dart';
import 'reservations_providers.dart';

/// Upcoming bookings, grouped by day. `reservations.view` opens the door;
/// `reservations.edit` (or an owner/manager) adds the levers.
class ReservationsScreen extends ConsumerStatefulWidget {
  const ReservationsScreen({super.key});

  @override
  ConsumerState<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends ConsumerState<ReservationsScreen> {
  bool _busy = false;

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setStatus(Reservation r, ReservationStatus next) async {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null || _busy) return;

    if (next == ReservationStatus.cancelled ||
        next == ReservationStatus.noShow) {
      final ok = await _confirm(context, r, next);
      if (!ok || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(reservationsRepositoryProvider(tenant.tenantId))
          .setStatus(r.id, next);
      ref.invalidate(reservationsProvider);
      _say('${r.guestName}: ${reservationStatusLabelFor(next)}.');
    } on PosFailure catch (e) {
      _say(e.message);
    } catch (_) {
      _say("Couldn't update the reservation.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(identityStatusProvider);
    final canView = ref.watch(hasPermissionProvider('reservations.view'));
    final canEdit =
        ref.watch(hasPermissionProvider('reservations.edit')) ||
        ref.watch(isManagerProvider);
    final ready = status == IdentityStatus.ready && canView;

    return AppScaffold(
      title: 'Reservations',
      maxBodyWidth: Breakpoints.reading,
      floatingActionButton: ready && canEdit
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => showReservationSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('New reservation'),
            )
          : null,
      body: switch (status) {
        IdentityStatus.unavailable => Padding(
          padding: const EdgeInsets.all(16),
          child: RetryNotice(
            message: "Couldn't check your access.",
            detail: '${ref.watch(identityErrorProvider)}',
            onRetry: () => ref
              ..invalidate(membershipsProvider)
              ..invalidate(permissionsProvider),
          ),
        ),
        IdentityStatus.ready when !canView => const NoReservationAccess(),
        IdentityStatus.ready => _Body(
          canEdit: canEdit,
          busy: _busy,
          onAction: _setStatus,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

Future<bool> _confirm(
  BuildContext context,
  Reservation r,
  ReservationStatus next,
) async {
  final noShow = next == ReservationStatus.noShow;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(noShow ? 'Mark as no-show?' : 'Cancel reservation?'),
        content: Text(
          '${r.guestName}, party of ${r.partySize}, '
          '${clockTime(r.reservedAt)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(noShow ? 'Mark no-show' : 'Cancel reservation'),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.canEdit,
    required this.busy,
    required this.onAction,
  });

  final bool canEdit;
  final bool busy;
  final void Function(Reservation, ReservationStatus) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(reservationsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(reservationsProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: reservations.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (e, _) => [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: RetryNotice(
                message: "Couldn't load reservations.",
                detail: e is PosFailure ? e.message : null,
                icon: Icons.cloud_off_outlined,
                onRetry: () => ref.invalidate(reservationsProvider),
              ),
            ),
          ],
          data: (list) =>
              list.isEmpty ? const [_Empty()] : _grouped(context, list),
        ),
      ),
    );
  }

  List<Widget> _grouped(BuildContext context, List<Reservation> list) {
    final theme = Theme.of(context);
    final days = <DateTime, List<Reservation>>{};
    for (final r in list) {
      final t = r.reservedAt;
      days.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(r);
    }
    final keys = days.keys.toList()..sort();
    return [
      for (final day in keys) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(dayHeading(day), style: theme.textTheme.titleSmall),
              ),
              Text(
                '${_covers(days[day]!)} covers',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (final r in days[day]!)
          _Tile(
            key: ValueKey(r.id),
            reservation: r,
            canEdit: canEdit,
            busy: busy,
            onAction: onAction,
          ),
      ],
    ];
  }
}

int _covers(List<Reservation> list) => list
    .where(
      (r) =>
          r.status == ReservationStatus.pending ||
          r.status == ReservationStatus.confirmed ||
          r.status == ReservationStatus.seated,
    )
    .fold(0, (sum, r) => sum + r.partySize);

/// "Today", "Tomorrow", else "Thu, Oct 29".
String dayHeading(DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final diff = DateTime(day.year, day.month, day.day).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final date = billDate(day).split(',').first; // "Oct 29"
  return '${wd[day.weekday - 1]}, $date';
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.reservation,
    required this.canEdit,
    required this.busy,
    required this.onAction,
  });

  final Reservation reservation;
  final bool canEdit;
  final bool busy;
  final void Function(Reservation, ReservationStatus) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final r = reservation;
    final next = canEdit ? r.status.nextStatuses : const <ReservationStatus>[];
    final details = [
      'Party of ${r.partySize}',
      if (r.tableLabel != null) 'Table ${r.tableLabel}',
      if (r.guestPhone != null) r.guestPhone!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  clockTime(r.reservedAt),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.guestName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(status: r.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              details,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            if (r.notes != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  r.notes!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            if (next.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in next)
                    _ActionButton(
                      status: s,
                      onPressed: busy ? null : () => onAction(r, s),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.status, required this.onPressed});

  final ReservationStatus status;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final (label, primary) = switch (status) {
      ReservationStatus.confirmed => ('Confirm', true),
      ReservationStatus.seated => ('Seat', true),
      ReservationStatus.noShow => ('No-show', false),
      ReservationStatus.cancelled => ('Cancel', false),
      ReservationStatus.pending => ('Pending', false),
    };
    final size = WidgetStatePropertyAll(const Size(64, Tokens.tapTarget));
    return primary
        ? FilledButton(
            style: ButtonStyle(minimumSize: size),
            onPressed: onPressed,
            child: Text(label),
          )
        : OutlinedButton(
            style: ButtonStyle(minimumSize: size),
            onPressed: onPressed,
            child: Text(label),
          );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReservationStatus status;

  @override
  Widget build(BuildContext context) {
    // Icon + word carry the state; the hue only reinforces.
    final s = context.semantic;
    final (icon, color) = switch (status) {
      ReservationStatus.pending => (Icons.hourglass_empty, s.warningText),
      ReservationStatus.confirmed => (Icons.event_available, s.infoText),
      ReservationStatus.seated => (Icons.check_circle_outline, s.goodText),
      ReservationStatus.cancelled => (Icons.cancel_outlined, s.neutral),
      ReservationStatus.noShow => (Icons.person_off_outlined, s.dangerText),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          reservationStatusLabelFor(status),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          const Icon(Icons.event_seat_outlined, size: 36),
          const SizedBox(height: 12),
          Text('No upcoming reservations', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Bookings for today and later show up here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
