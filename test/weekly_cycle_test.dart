import 'package:flutter_test/flutter_test.dart';
import 'package:progress_tracker/weekly_cycle.dart';

void main() {
  test('Monday 6am starts the 158-hour cycle', () {
    final cycle = WeeklyCycle(DateTime(2026, 10, 19, 6));
    expect(cycle.active, isTrue);
    expect(cycle.remaining, const Duration(hours: 158));
    expect(cycle.progress, 0);
    expect(cycle.day, 'Monday');
  });
  test('Monday before 6am waits for this week', () {
    final cycle = WeeklyCycle(DateTime(2026, 10, 19, 5, 59, 59));
    expect(cycle.active, isFalse);
    expect(cycle.remaining, const Duration(seconds: 1));
  });
  test('Sunday 8pm ends focus and waits ten hours', () {
    expect(WeeklyCycle(DateTime(2026, 10, 25, 19, 59, 59)).active, isTrue);
    final cycle = WeeklyCycle(DateTime(2026, 10, 25, 20));
    expect(cycle.active, isFalse);
    expect(cycle.remaining, const Duration(hours: 10));
    expect(cycle.day, 'Sunday');
  });
  test('Calendar boundaries roll across year and month', () {
    final cycle = WeeklyCycle(DateTime(2027, 1, 3, 21));
    expect(cycle.nextStart, DateTime(2027, 1, 4, 6));
    expect(WeeklyCycle(DateTime(2026, 11, 1, 12)).day, 'Sunday');
  });
}
