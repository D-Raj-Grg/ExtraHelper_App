import 'package:intl/intl.dart';

/// Dates and times, said the same way everywhere.
///
/// Formatted in the **device** timezone, not the tenant's. `package:intl`
/// carries no IANA database (the same reason `PosRepository` asks Postgres for
/// the day boundary rather than computing one), and a till stands in the
/// restaurant it bills for — its clock is the restaurant's clock. Text that
/// must be right in the tenant's zone regardless of where it is read is built
/// server-side with `to_char(... at time zone _tz ...)`, as the dashboard does.
///
/// Locale is pinned to `en_US` for the same reason [money] pins it: a bill on
/// the phone and the same bill on the counter screen have to read alike.
final _dateTime = DateFormat('MMM d, yyyy, h:mm a', 'en_US');
final _date = DateFormat('MMM d, yyyy', 'en_US');

/// "Aug 20, 2026, 7:42 PM" — a bill's own timestamp, printed beside its number.
String billDateTime(DateTime at) => _dateTime.format(at.toLocal());

/// "Aug 20, 2026" — the day alone, for the badge on a bill left overnight.
String billDate(DateTime at) => _date.format(at.toLocal());

/// "7:42 PM" — a payment's time, on a bill whose date is already on screen.
String clockTime(DateTime at) => DateFormat.jm('en_US').format(at.toLocal());

/// Whether [at] belongs to an earlier **trading** day than the one running now.
///
/// Trading day, not 24 hours: a bill opened at 23:50 is "yesterday's" at 00:10,
/// which is exactly the case that makes a cashier walk past it.
///
/// [dayStart] is the server's `tenant_day_start` and is what makes this correct
/// under a cutoff. A restaurant whose day starts at 4am is still on Friday's
/// takings at 01:00 on Saturday, and a plain calendar comparison would call
/// that order "carried over" when the shift has not even ended. The phone
/// cannot work that boundary out for itself — see the note at the top of this
/// file — so it is passed in.
///
/// Falls back to the device's calendar day when [dayStart] is unknown (offline,
/// or before the first fetch). That is the old behaviour: right for the
/// midnight tenants, an hour or two out for the rest, and better than showing
/// nothing.
bool isEarlierDay(DateTime at, {DateTime? dayStart, DateTime? now}) {
  if (dayStart != null) return at.toLocal().isBefore(dayStart.toLocal());

  final a = at.toLocal();
  final b = (now ?? DateTime.now()).toLocal();
  final day = DateTime(a.year, a.month, a.day);
  final today = DateTime(b.year, b.month, b.day);
  return day.isBefore(today);
}
