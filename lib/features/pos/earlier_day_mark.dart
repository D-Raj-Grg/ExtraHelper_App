import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/when.dart';
import '../../core/widgets/earlier_day_chip.dart';
import 'pos_providers.dart';

/// The "From Aug 19" chip, shown only when the thing really did carry over.
///
/// One widget owns the decision so the three cards that need it cannot answer
/// it differently. It also spares them from threading a day boundary down
/// through the tree for the sake of one chip.
///
/// The boundary is the **trading** day's, not the device's calendar: under a
/// 4am cutoff an order rung up at 23:00 is still today's business at 01:00, and
/// a calendar comparison would wrongly brand it carried over — mid-shift, on
/// the card the cashier is looking at.
class EarlierDayMark extends ConsumerWidget {
  const EarlierDayMark({
    super.key,
    required this.at,
    this.padding = EdgeInsets.zero,
  });

  final DateTime at;

  /// The gap before the chip. Owned here rather than by the caller so that a
  /// card with nothing to carry over collapses completely — a sibling
  /// `SizedBox` would leave a hole on every ordinary order.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayStart = ref.watch(tenantDayStartProvider).valueOrNull;
    if (!isEarlierDay(at, dayStart: dayStart)) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: EarlierDayChip(at: at),
    );
  }
}
