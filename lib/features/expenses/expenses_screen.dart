import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scaffold.dart';
import '../../app/router.dart';
import '../../core/format/money.dart';
import '../../core/format/when.dart';
import '../../core/widgets/photo_picker.dart';
import '../../data/supabase/expenses_repository.dart';
import '../../data/supabase/pos_repository.dart' show PosFailure;
import '../../data/sync/outbox.dart';
import '../../data/sync/sync_providers.dart';
import '../reports/day_report_providers.dart' show shiftDay;
import '../tenant/tenant_providers.dart';
import 'expense_sheet.dart';
import 'expenses_providers.dart';

/// The daily book: rice, gas, a ride home for the dishwasher — logged by
/// whoever paid, totalled for the night count on Day close.
///
/// Adding goes through the outbox, so it works with no signal and replays
/// under its idempotency key. Edit and void are online-only: they change a row
/// someone else may already be counting against.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  bool _busy = false;

  ExpensesRepository? get _repo {
    final tenant = ref.read(activeTenantProvider);
    if (tenant == null) return null;
    return ref.read(expensesRepositoryProvider(tenant.tenantId));
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _refresh() {
    ref.invalidate(expenseRangeProvider);
    ref.invalidate(expenseDayProvider);
    ref.invalidate(pendingExpensesProvider);
  }

  Future<void> _add(ExpenseDay? day) async {
    final tenant = ref.read(activeTenantProvider);
    final queue = ref.read(orderQueueProvider);
    if (tenant == null || queue == null || _busy) return;

    List<ExpenseCategory> categories;
    try {
      categories = (await ref.read(
        expenseCategoriesProvider.future,
      )).where((c) => !c.archived).toList();
    } on PosFailure catch (e) {
      _say(e.message);
      return;
    }
    if (!mounted) return;
    if (categories.isEmpty) {
      _say('No categories yet. Ask a manager to add one.');
      return;
    }

    final draft = await showExpenseSheet(
      context,
      categories: categories,
      currency: tenant.currency,
    );
    if (draft == null) return;

    // Only a manager may add to an earlier day; the RPC says so if not.
    final backdate = day != null && !day.isToday ? day.day : null;
    setState(() => _busy = true);
    final outcome = await queue.recordExpense(
      categoryId: draft.categoryId,
      amountCents: draft.amountCents,
      note: draft.note,
      paidFrom: draft.paidFrom.wire,
      businessDate: backdate,
    );
    if (mounted) setState(() => _busy = false);
    _refresh();
    if (outcome.isRejected) {
      _say(outcome.error!);
      return;
    }
    final photo = draft.photo;
    if (photo == null) {
      _say(
        outcome.synced
            ? 'Expense logged.'
            : "Saved on this phone — it'll send when you're back online.",
      );
      return;
    }
    if (!outcome.synced) {
      _say(
        "Saved on this phone. Attach the receipt photo from the expense's "
        'menu once it has sent.',
      );
      return;
    }
    // Online: find the row the outbox key became, then attach the photo.
    final repo = _repo;
    if (repo == null) return;
    await _run(() async {
      final key = outcome.orderRef.substring('expense:'.length);
      final id = await repo.idForClientKey(key);
      if (id == null) {
        throw const PosFailure(
          'Expense logged, but the photo could not be attached. Try from '
          "the expense's menu.",
        );
      }
      await repo.attachReceipt(
        expenseId: id,
        bytes: photo.bytes,
        contentType: photo.contentType,
        ext: photo.ext,
      );
    }, 'Expense logged with its receipt.');
  }

  Future<void> _attach(Expense e) async {
    final repo = _repo;
    if (repo == null || _busy) return;
    final photo = await pickPhoto(context);
    if (photo == null) return;
    await _run(
      () => repo.attachReceipt(
        expenseId: e.id,
        bytes: photo.bytes,
        contentType: photo.contentType,
        ext: photo.ext,
      ),
      'Receipt attached.',
    );
  }

  Future<void> _removePhoto(Expense e) async {
    final repo = _repo;
    if (repo == null || _busy) return;
    await _run(() => repo.removeReceipt(e.id), 'Receipt removed.');
  }

  Future<void> _viewPhoto(Expense e) async {
    final repo = _repo;
    final path = e.receiptPath;
    if (repo == null || path == null) return;
    try {
      final url = await repo.receiptUrl(path);
      if (!mounted) return;
      await showPhotoViewer(context, url, title: 'Receipt');
    } on PosFailure catch (err) {
      _say(err.message);
    }
  }

  Future<void> _edit(Expense e) async {
    final tenant = ref.read(activeTenantProvider);
    final repo = _repo;
    if (tenant == null || repo == null || _busy) return;
    final categories = (await ref.read(
      expenseCategoriesProvider.future,
    )).where((c) => !c.archived).toList();
    if (!mounted) return;
    final draft = await showExpenseSheet(
      context,
      categories: categories,
      currency: tenant.currency,
      editing: e,
    );
    if (draft == null) return;
    await _run(
      () => repo.update(
        id: e.id,
        categoryId: draft.categoryId,
        amountCents: draft.amountCents,
        note: draft.note,
        paidFrom: draft.paidFrom,
      ),
      'Expense updated.',
    );
  }

  Future<void> _void(Expense e, String currency) async {
    final repo = _repo;
    if (repo == null || _busy) return;
    final reason = await showVoidExpenseDialog(
      context,
      title: 'Void ${money(e.amountCents, currency)} — ${e.note}?',
    );
    if (reason == null) return;
    await _run(
      () => repo.voidExpense(id: e.id, reason: reason),
      'Expense voided.',
    );
  }

  Future<void> _run(Future<void> Function() work, String success) async {
    setState(() => _busy = true);
    String message;
    try {
      await work();
      message = success;
      _refresh();
    } on PosFailure catch (e) {
      message = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    _say(message);
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(activeTenantProvider);
    final currency = tenant?.currency ?? 'USD';
    final dayAsync = ref.watch(expenseDayProvider);
    // Loaded now, not on the tap: the add sheet must open with no signal.
    ref.watch(expenseCategoriesProvider);
    final pending = ref.watch(pendingExpensesProvider).valueOrNull ?? const [];
    final day = dayAsync.valueOrNull;
    final canManage = day?.canManage ?? false;

    return AppScaffold(
      title: 'Expenses',
      actions: [
        if (canManage)
          IconButton(
            tooltip: 'Categories',
            icon: const Icon(Icons.sell_outlined),
            onPressed: () => context.push(Routes.expenseCategories),
          ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _add(day),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: dayAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Problem(
            message: '$e',
            pending: pending,
            currency: currency,
            onRetry: _refresh,
          ),
          data: (d) => ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              _DayBar(day: d),
              const SizedBox(height: 8),
              _Summary(day: d, currency: currency),
              // Range totals need reports.view, the same key as Day close.
              if (d.canCloseDay) ...[
                const SizedBox(height: 8),
                const _RangeTotals(),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => context.go(Routes.dayClose),
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Count cash on Day close'),
                ),
              ],
              const SizedBox(height: 12),
              for (final p in pending)
                _PendingCard(entry: p, currency: currency),
              if (d.items.isEmpty && pending.isEmpty)
                const _Empty()
              else
                for (final e in d.items)
                  _ExpenseCard(
                    key: ValueKey(e.id),
                    expense: e,
                    currency: currency,
                    showBy: d.canViewAll,
                    busy: _busy,
                    onEdit: () => _edit(e),
                    onVoid: () => _void(e, currency),
                    onAttach: () => _attach(e),
                    onRemovePhoto: () => _removePhoto(e),
                    onViewPhoto: () => _viewPhoto(e),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayBar extends ConsumerWidget {
  const _DayBar({required this.day});

  final ExpenseDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cursor = ref.read(expenseDayCursorProvider.notifier);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous day',
          iconSize: 28,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => cursor.show(shiftDay(day.day, -1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            day.isToday ? 'Today · ${day.dayLabel}' : day.dayLabel,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          iconSize: 28,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: day.isToday
              ? null
              : () {
                  final next = shiftDay(day.day, 1);
                  cursor.show(next.compareTo(day.today) >= 0 ? null : next);
                },
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.day, required this.currency});

  final ExpenseDay day;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    final count = day.live.length;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              day.canViewAll ? 'Spent this day' : 'You logged this day',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              money(day.totalCents, currency),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: tabular,
              ),
            ),
            Text(
              '$count ${count == 1 ? 'entry' : 'entries'}',
              style: theme.textTheme.bodySmall,
            ),
            if (count > 0) ...[
              const Divider(height: 20),
              for (final p in PaidFrom.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(p.label)),
                      Text(
                        money(day.totalFrom(p), currency),
                        style: const TextStyle(fontFeatures: tabular),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Last 7 and last 30 days — the web Reports page's week and month windows,
/// bucketed by business day on the server.
class _RangeTotals extends ConsumerWidget {
  const _RangeTotals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(activeTenantProvider)?.currency ?? 'USD';
    return Row(
      children: [
        Expanded(
          child: _RangeTile(
            label: 'Last 7 days',
            range: ref.watch(expenseRangeProvider(7)),
            currency: currency,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RangeTile(
            label: 'Last 30 days',
            range: ref.watch(expenseRangeProvider(30)),
            currency: currency,
          ),
        ),
      ],
    );
  }
}

class _RangeTile extends StatelessWidget {
  const _RangeTile({
    required this.label,
    required this.range,
    required this.currency,
  });

  final String label;
  final AsyncValue<ExpenseRange?> range;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final r = range.valueOrNull;
    final top = r == null || r.byCategory.isEmpty ? null : r.byCategory.first;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 4),
            Text(
              range.hasError
                  ? '—'
                  : r == null
                  ? '…'
                  : money(r.totalCents, currency),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              range.hasError
                  ? "Couldn't load"
                  : r == null
                  ? ' '
                  : top == null
                  ? 'No expenses'
                  : 'Most on ${top.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    super.key,
    required this.expense,
    required this.currency,
    required this.showBy,
    required this.busy,
    required this.onEdit,
    required this.onVoid,
    required this.onAttach,
    required this.onRemovePhoto,
    required this.onViewPhoto,
  });

  final Expense expense;
  final String currency;
  final bool showBy;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onVoid;
  final VoidCallback onAttach;
  final VoidCallback onRemovePhoto;
  final VoidCallback onViewPhoto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = expense;
    final muted = theme.colorScheme.onSurfaceVariant;
    final strike = e.voided ? TextDecoration.lineThrough : null;
    final meta = [
      clockTime(e.createdAt),
      e.category,
      e.paidFrom.label,
      if (showBy && e.by != null) e.by!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.note,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      decoration: strike,
                      color: e.voided ? muted : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  if (e.voided)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.block, size: 14, color: muted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Voided${e.voidReason == null ? '' : ' — ${e.voidReason}'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (e.hasReceipt)
              IconButton(
                tooltip: 'View receipt photo',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onViewPhoto,
                icon: const Icon(Icons.receipt_long_outlined),
              ),
            Text(
              money(e.amountCents, currency),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                decoration: strike,
                color: e.voided ? muted : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (!e.voided && (e.editable || e.canAttach))
              PopupMenuButton<String>(
                tooltip: 'Actions for ${e.note}',
                enabled: !busy,
                onSelected: (v) => switch (v) {
                  'edit' => onEdit(),
                  'attach' => onAttach(),
                  'remove_photo' => onRemovePhoto(),
                  _ => onVoid(),
                },
                itemBuilder: (_) => [
                  if (e.editable)
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                  if (e.canAttach)
                    PopupMenuItem(
                      value: 'attach',
                      child: ListTile(
                        leading: const Icon(Icons.add_a_photo_outlined),
                        title: Text(
                          e.hasReceipt
                              ? 'Replace receipt photo'
                              : 'Attach receipt photo',
                        ),
                      ),
                    ),
                  if (e.canAttach && e.hasReceipt)
                    const PopupMenuItem(
                      value: 'remove_photo',
                      child: ListTile(
                        leading: Icon(Icons.hide_image_outlined),
                        title: Text('Remove receipt photo'),
                      ),
                    ),
                  if (e.editable)
                    const PopupMenuItem(
                      value: 'void',
                      child: ListTile(
                        leading: Icon(Icons.block),
                        title: Text('Void'),
                      ),
                    ),
                ],
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Logged on this phone, not yet on the server. Greyed and labelled in words
/// so nobody logs it a second time thinking the first tap was lost.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.entry, required this.currency});

  final OutboxEntry entry;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final cents = (entry.payload['amount_cents'] as num?)?.toInt() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        leading: Icon(Icons.cloud_upload_outlined, color: muted),
        title: Text(entry.payload['note'] as String? ?? ''),
        subtitle: const Text('Waiting to send — saved on this phone'),
        trailing: Text(
          money(cents, currency),
          style: theme.textTheme.titleMedium?.copyWith(
            color: muted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
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
          const Icon(Icons.receipt_long_outlined, size: 36),
          const SizedBox(height: 12),
          Text(
            'Nothing logged for this day',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Every time someone spends restaurant money — rice, gas, a ride '
            "for staff — tap Add expense. It lands in tonight's count.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.message,
    required this.pending,
    required this.currency,
    required this.onRetry,
  });

  final String message;
  final List<OutboxEntry> pending;
  final String currency;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 96),
      children: [
        const Icon(Icons.cloud_off_outlined, size: 36),
        const SizedBox(height: 12),
        Text(
          "Couldn't load the day's expenses. You can still add one — it "
          'saves on this phone and sends when the connection is back.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ),
        const SizedBox(height: 16),
        for (final p in pending) _PendingCard(entry: p, currency: currency),
      ],
    );
  }
}
