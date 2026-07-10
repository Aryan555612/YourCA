import 'package:intl/intl.dart';

abstract class CurrencyUtils {
  static final _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final _formatterNoDecimal = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final _compactFormatter = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 1,
  );

  static String format(double amount) => _formatter.format(amount);
  static String formatNoDecimal(double amount) =>
      _formatterNoDecimal.format(amount);
  static String formatCompact(double amount) =>
      _compactFormatter.format(amount);

  static String formatSigned(double amount) {
    final formatted = _formatterNoDecimal.format(amount.abs());
    return amount >= 0 ? '+$formatted' : '-$formatted';
  }
}

abstract class DateUtils2 {
  static final _dayMonth = DateFormat('d MMM');
  static final _dayMonthYear = DateFormat('d MMM yyyy');
  static final _monthYear = DateFormat('MMMM yyyy');
  static final _shortMonthYear = DateFormat('MMM yy');
  static final _full = DateFormat('EEEE, d MMMM yyyy');
  static final _time = DateFormat('hh:mm a');

  static String toDisplayDate(DateTime dt) => _dayMonthYear.format(dt);
  static String toDayMonth(DateTime dt) => _dayMonth.format(dt);
  static String toMonthYear(DateTime dt) => _monthYear.format(dt);
  static String toShortMonthYear(DateTime dt) => _shortMonthYear.format(dt);
  static String toFullDate(DateTime dt) => _full.format(dt);
  static String toTime(DateTime dt) => _time.format(dt);

  static bool isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  static DateTime firstDayOfMonth(DateTime dt) =>
      DateTime(dt.year, dt.month, 1);

  static DateTime lastDayOfMonth(DateTime dt) =>
      DateTime(dt.year, dt.month + 1, 0, 23, 59, 59);

  static List<DateTime> last6Months(DateTime from) {
    return List.generate(6, (i) {
      final month = from.month - i;
      final year = from.year + (month <= 0 ? -1 : 0);
      final adjustedMonth = month <= 0 ? month + 12 : month;
      return DateTime(year, adjustedMonth, 1);
    }).reversed.toList();
  }

  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return toDisplayDate(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
