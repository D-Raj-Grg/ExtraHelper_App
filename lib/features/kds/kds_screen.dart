import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_scaffold.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_chip.dart';
import '../../data/supabase/kds_repository.dart';
import '../tenant/tenant_providers.dart';
import 'kds_constants.dart';
import 'kds_providers.dart';
import 'line_status_sheet.dart';
import 'ticket_card.dart';

/// The kitchen board.
///
/// Built for a tablet propped on a shelf and a phone in an apron pocket: one
/// column of tickets on a phone, more as the screen allows. Nothing here needs
/// a keyboard and nothing needs precision — the smallest thing a cook taps is
/// the 44px advance button on a dish.
class KdsScreen extends ConsumerStatefulWidget {
  const KdsScreen({super.key});

  @override
  ConsumerState<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends ConsumerState<KdsScreen> {
  /// Ticket age is the board's most important number and it moves on its own,
  /// so the screen ticks even when nothing changes.
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    final error = await action();
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(kdsTicketsProvider);
    final board = ref.watch(kdsBoardProvider);
    final rail = ref.watch(kdsDishRailProvider);
    final canBump = ref.watch(hasPermissionProvider('kds.bump'));
    final actions = ref.watch(kdsActionsProvider);

    return AppScaffold(
      title: 'Kitchen',
      body: RefreshIndicator(
        onRefresh: () => ref.read(kdsTicketsProvider.notifier).refresh(),
        child: tickets.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Message(
            icon: Icons.cloud_off,
            title: "Couldn't load the board",
            body: '$e',
            onRetry: () => ref.read(kdsTicketsProvider.notifier).refresh(),
          ),
          data: (_) => CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: _StationFilter()),
              if (rail.isNotEmpty)
                SliverToBoxAdapter(child: _DishRail(rows: rail)),
              if (board.live.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Message(
                    icon: Icons.done_all,
                    title: 'Nothing on the pass',
                    body:
                        'Tickets land here the moment a waiter fires an order. '
                        'Pull down to check for new ones.',
                  ),
                )
              else
                _TicketGrid(
                  tickets: board.live,
                  now: _now,
                  canBump: canBump,
                  onAdvanceLine: (line, status) =>
                      _run(() => actions.setLineStatus(line.id, status)),
                  onAdvanceTicket: (ticket, status) =>
                      _run(() => actions.setTicketStatus(ticket.id, status)),
                  onLineLongPress: (line) async {
                    final picked = await showLineStatusSheet(context, line);
                    if (picked == null || picked == line.status) return;
                    await _run(() => actions.setLineStatus(line.id, picked));
                  },
                ),
              if (board.recallable.isNotEmpty)
                SliverToBoxAdapter(
                  child: _Recall(
                    tickets: board.recallable,
                    canBump: canBump,
                    onRecall: (ticket) => _run(() => actions.recall(ticket.id)),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which section this screen is watching. A kitchen screen is bolted to one
/// station, so the choice sticks across restarts.
class _StationFilter extends ConsumerWidget {
  const _StationFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(kitchenStationsProvider).valueOrNull ?? const [];
    final selected = ref.watch(kdsStationProvider);
    final notifier = ref.read(kdsStationProvider.notifier);

    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          AppChoiceChip(
            label: 'All',
            selected: selected == kdsAllStations,
            onSelect: () => notifier.select(kdsAllStations),
          ),
          for (final station in stations) ...[
            const SizedBox(width: 8),
            AppChoiceChip(
              label: station.name,
              selected: selected == station.id,
              onSelect: () => notifier.select(station.id),
            ),
          ],
          const SizedBox(width: 8),
          // Dishes that route to no station land on their own ticket. The web
          // board calls that "Expo" and so does this.
          AppChoiceChip(
            label: 'Expo',
            selected: selected == kdsExpo,
            onSelect: () => notifier.select(kdsExpo),
          ),
        ],
      ),
    );
  }
}

/// All-day counts, so the pass can batch: "6 momo" across three tickets is one
/// pan, not three.
class _DishRail extends StatelessWidget {
  const _DishRail({required this.rows});

  final List<DishTally> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('All day', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final row in rows)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: BorderRadius.circular(Tokens.radiusSm),
                      ),
                      child: Text(
                        '${row.qty}× ${row.name}',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketGrid extends StatelessWidget {
  const _TicketGrid({
    required this.tickets,
    required this.now,
    required this.canBump,
    required this.onAdvanceLine,
    required this.onAdvanceTicket,
    required this.onLineLongPress,
  });

  final List<KdsTicket> tickets;
  final DateTime now;
  final bool canBump;
  final void Function(KdsLine, KotStatus) onAdvanceLine;
  final void Function(KdsTicket, KotStatus) onAdvanceTicket;
  final void Function(KdsLine) onLineLongPress;

  @override
  Widget build(BuildContext context) {
    // A ticket is a column of dishes, so its height varies wildly — a fixed
    // grid would leave a card with two lines the same height as one with eight.
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1100 ? 3 : (width >= 700 ? 2 : 1);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      sliver: SliverList.separated(
        itemCount: (tickets.length / columns).ceil(),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, row) {
          final slice = tickets.skip(row * columns).take(columns).toList();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: i < slice.length
                      ? TicketCard(
                          ticket: slice[i],
                          now: now,
                          canBump: canBump,
                          onAdvanceLine: onAdvanceLine,
                          onAdvanceTicket: (status) =>
                              onAdvanceTicket(slice[i], status),
                          onLineLongPress: onLineLongPress,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Recently bumped, still recallable. A ticket sent away by mistake is a real
/// event in a kitchen and the way back should not be a phone call to the till.
class _Recall extends StatelessWidget {
  const _Recall({
    required this.tickets,
    required this.canBump,
    required this.onRecall,
  });

  final List<KdsTicket> tickets;
  final bool canBump;
  final void Function(KdsTicket) onRecall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Just sent', style: theme.textTheme.titleSmall),
          Text(
            'Bumped in the last 20 minutes — tap to put one back on the board.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ticket in tickets)
                OutlinedButton.icon(
                  onPressed: canBump ? () => onRecall(ticket) : null,
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text('${ticket.destination} · ${ticket.station}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, Tokens.tapTarget),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
