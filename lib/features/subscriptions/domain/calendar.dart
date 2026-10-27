enum DurationUnit { days, weeks, months, years }

abstract final class MembershipCalendar {
  static DateTime date(DateTime d) => DateTime.utc(d.year, d.month, d.day);
  static DateTime endExclusive(DateTime start, int value, DurationUnit unit) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'value', 'Must be positive');
    }
    final d = date(start);
    if (unit == DurationUnit.days || unit == DurationUnit.weeks) {
      return d.add(
        Duration(days: value * (unit == DurationUnit.weeks ? 7 : 1)),
      );
    }
    final target = DateTime.utc(
      d.year,
      d.month + value * (unit == DurationUnit.years ? 12 : 1),
    );
    final lastDay = DateTime.utc(target.year, target.month + 1, 0).day;
    return DateTime.utc(target.year, target.month, d.day.clamp(1, lastDay));
  }

  static DateTime effectiveEnd(
    DateTime original,
    List<PausePeriod> pauses,
    DateTime asOf,
  ) {
    final sorted = [...pauses]..sort((a, b) => a.start.compareTo(b.start));
    DateTime? previousEnd;
    var days = 0;
    for (final p in sorted) {
      final start = date(p.start), end = date(p.end ?? asOf);
      if (end.isBefore(start)) {
        throw ArgumentError('Resume date precedes pause');
      }
      if (previousEnd != null && start.isBefore(previousEnd)) {
        throw ArgumentError('Overlapping pauses');
      }
      days += end.difference(start).inDays;
      previousEnd = p.end == null ? DateTime.utc(9999) : end;
    }
    return date(original).add(Duration(days: days));
  }
}

class PausePeriod {
  const PausePeriod(this.start, [this.end]);
  final DateTime start;
  final DateTime? end;
}
