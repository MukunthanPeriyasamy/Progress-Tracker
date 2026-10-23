/// A calendar-based local weekly window. Calendar construction preserves the
/// requested wall-clock boundaries even across daylight-saving transitions.
class WeeklyCycle {
  WeeklyCycle(this.now) {
    final monday = now.day - now.weekday + DateTime.monday;
    start = DateTime(now.year, now.month, monday, 6);
    end = DateTime(now.year, now.month, monday + 6, 20);
    active = !now.isBefore(start) && now.isBefore(end);
    nextStart = now.isBefore(start)
        ? start
        : DateTime(now.year, now.month, monday + 7, 6);
  }

  final DateTime now;
  late final DateTime start, end, nextStart;
  late final bool active;
  Duration get remaining => (active ? end : nextStart).difference(now);
  double get progress => active
      ? (now.difference(start).inSeconds / end.difference(start).inSeconds)
            .clamp(0.0, 1.0)
      : 0;
  String get day => days[now.weekday - 1];
  String get countdown {
    final seconds = remaining.inSeconds;
    return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
  }

  static const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
}
