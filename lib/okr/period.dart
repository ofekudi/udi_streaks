/// A calendar quarter, e.g. 2026-Q3. Used for windows, renewal and grade history.
class Period {
  final int year;
  final int quarter; // 1..4

  const Period(this.year, this.quarter);

  static Period current() => ofDate(DateTime.now());

  static Period ofDate(DateTime d) => Period(d.year, ((d.month - 1) ~/ 3) + 1);

  static Period? parse(String s) {
    final m = RegExp(r'^(\d{4})-Q([1-4])$').firstMatch(s);
    if (m == null) return null;
    return Period(int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  String get id => '$year-Q$quarter';

  String get label => 'Q$quarter $year';

  DateTime get start => DateTime(year, (quarter - 1) * 3 + 1, 1);

  /// Inclusive end — last second of the quarter. Month `quarter*3 + 1`
  /// normalises past December into the next year automatically.
  DateTime get end =>
      DateTime(year, quarter * 3 + 1, 1).subtract(const Duration(seconds: 1));

  Period get next => quarter == 4 ? Period(year + 1, 1) : Period(year, quarter + 1);

  double get fractionElapsed {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 1;
    final elapsed = DateTime.now().difference(start).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  @override
  String toString() => id;
}
