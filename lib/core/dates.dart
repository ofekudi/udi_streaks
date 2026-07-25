/// Day-granularity date helpers.
///
/// The app reasons about habits and measurements in whole days, but stores
/// timestamps as ISO-8601 strings. These helpers are the single place where
/// that truncation and formatting happens — previously the midnight-truncation
/// idiom was written out eight times in `db_helper.dart` and "format as
/// yyyy-MM-dd" had four different spellings across the codebase.
library;

/// Midnight at the start of [d], discarding any time component.
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Midnight at the start of today.
DateTime todayStart() => startOfDay(DateTime.now());

/// Whole days from [from] to [to], comparing dates only.
int daysBetween(DateTime from, DateTime to) =>
    startOfDay(to).difference(startOfDay(from)).inDays;

/// `yyyy-MM-dd`. The canonical date format for display and for the
/// home-widget payload.
String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
