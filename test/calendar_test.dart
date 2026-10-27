import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/subscriptions/domain/calendar.dart';

void main() {
  group('Calendar membership boundaries', () {
    test('January 1 plus three months has March 31 as final day', () {
      final end = MembershipCalendar.endExclusive(
        DateTime.utc(2026, 1, 1),
        3,
        DurationUnit.months,
      );
      expect(end, DateTime.utc(2026, 4, 1));
      expect(end.subtract(const Duration(days: 1)), DateTime.utc(2026, 3, 31));
    });
    test('20 paused days restore exactly 20 unused days', () {
      expect(
        MembershipCalendar.effectiveEnd(DateTime.utc(2026, 4, 1), [
          PausePeriod(DateTime.utc(2026, 2, 1), DateTime.utc(2026, 2, 21)),
        ], DateTime.utc(2026, 3, 1)),
        DateTime.utc(2026, 4, 21),
      );
    });
    test('Multiple pauses including adjacent half-open periods', () {
      expect(
        MembershipCalendar.effectiveEnd(DateTime.utc(2026, 4, 1), [
          PausePeriod(DateTime.utc(2026, 2, 1), DateTime.utc(2026, 2, 11)),
          PausePeriod(DateTime.utc(2026, 2, 11), DateTime.utc(2026, 2, 21)),
        ], DateTime.utc(2026, 3, 1)),
        DateTime.utc(2026, 4, 21),
      );
    });
    test('Overlapping and reversed pauses are rejected', () {
      expect(
        () => MembershipCalendar.effectiveEnd(DateTime.utc(2026, 4, 1), [
          PausePeriod(DateTime.utc(2026, 2, 1), DateTime.utc(2026, 2, 11)),
          PausePeriod(DateTime.utc(2026, 2, 10), DateTime.utc(2026, 2, 21)),
        ], DateTime.utc(2026, 3, 1)),
        throwsArgumentError,
      );
      expect(
        () => MembershipCalendar.effectiveEnd(DateTime.utc(2026, 4, 1), [
          PausePeriod(DateTime.utc(2026, 2, 10), DateTime.utc(2026, 2, 1)),
        ], DateTime.utc(2026, 3, 1)),
        throwsArgumentError,
      );
    });
    test('Month-end clamping and leap years', () {
      expect(
        MembershipCalendar.endExclusive(
          DateTime.utc(2026, 1, 31),
          1,
          DurationUnit.months,
        ),
        DateTime.utc(2026, 2, 28),
      );
      expect(
        MembershipCalendar.endExclusive(
          DateTime.utc(2024, 1, 31),
          1,
          DurationUnit.months,
        ),
        DateTime.utc(2024, 2, 29),
      );
      expect(
        MembershipCalendar.endExclusive(
          DateTime.utc(2024, 2, 29),
          1,
          DurationUnit.years,
        ),
        DateTime.utc(2025, 2, 28),
      );
    });
    test('Open pause uses supplied gym date deterministically', () {
      expect(
        MembershipCalendar.effectiveEnd(DateTime.utc(2026, 4, 1), [
          PausePeriod(DateTime.utc(2026, 2, 1)),
        ], DateTime.utc(2026, 2, 21)),
        DateTime.utc(2026, 4, 21),
      );
    });
    test('Nonpositive duration rejected', () {
      expect(
        () => MembershipCalendar.endExclusive(
          DateTime.utc(2026),
          0,
          DurationUnit.months,
        ),
        throwsArgumentError,
      );
    });
  });
}
