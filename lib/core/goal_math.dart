import 'dart:math';

/// Savings goal maths. Pure functions, so they are easy to test and run instantly on the phone.
enum Frequency {
  daily('day', 'days'),
  weekly('week', 'weeks'),
  monthly('month', 'months');

  final String one;
  final String many;
  const Frequency(this.one, this.many);

  static Frequency parse(String s) => Frequency.values.firstWhere((f) => f.name == s, orElse: () => Frequency.weekly);
}

class GoalMath {
  /// Rounds up to an amount people can actually carry: 14,286 -> 14,500.
  static int friendlyUp(int amount) {
    if (amount <= 0) return 0;
    final step = amount <= 1000 ? 100 : (amount <= 20000 ? 500 : 1000);
    return ((amount + step - 1) ~/ step) * step;
  }

  /// Number of pay times between two dates, counting both ends. 7 days daily = 7, 14 days weekly = 2.
  static int periodsBetween(DateTime start, DateTime end, Frequency f) {
    final days = DateTime.utc(end.year, end.month, end.day).difference(DateTime.utc(start.year, start.month, start.day)).inDays + 1;
    if (days <= 0) return 0;
    return switch (f) {
      Frequency.daily => days,
      Frequency.weekly => (days + 6) ~/ 7,
      Frequency.monthly => max(1, (end.year - start.year) * 12 + end.month - start.month + (end.day >= start.day ? 1 : 0)),
    };
  }

  /// Goal + time -> each person brings this much every period (exact, before rounding).
  static int exactPerPerson(int target, int people, int periods) {
    if (target <= 0 || people <= 0 || periods <= 0) return 0;
    return (target + people * periods - 1) ~/ (people * periods);
  }

  /// Goal + time -> friendly amount each person brings every period.
  static int perPerson(int target, int people, int periods) => friendlyUp(exactPerPerson(target, people, periods));

  /// Goal + amount each -> how many periods it takes.
  static int periodsNeeded(int target, int people, int perPerson) {
    if (target <= 0 || people <= 0 || perPerson <= 0) return 0;
    return (target + people * perPerson - 1) ~/ (people * perPerson);
  }

  /// Amount each + time -> total the group reaches.
  static int reach(int people, int perPerson, int periods) => max<int>(0, people) * max<int>(0, perPerson) * max<int>(0, periods);

  /// The day a goal is reached if paying starts on [start] and runs [periods] times.
  static DateTime finishDate(DateTime start, int periods, Frequency f) {
    if (periods <= 0) return start;
    return switch (f) {
      Frequency.daily => start.add(Duration(days: periods - 1)),
      Frequency.weekly => start.add(Duration(days: 7 * (periods - 1))),
      Frequency.monthly => DateTime(start.year, start.month + periods - 1, start.day),
    };
  }

  /// Where the group should be by [day] if it pays evenly from start to end.
  static int plannedBy(int target, DateTime start, DateTime end, DateTime day) {
    final total = end.difference(start).inDays + 1;
    if (total <= 0) return target;
    final done = day.difference(start).inDays + 1;
    if (done <= 0) return 0;
    if (done >= total) return target;
    return (target * done) ~/ total;
  }
}

/// Plain-words progress for one goal.
class GoalStatus {
  final int target;
  final int collected;
  final int left;
  final double percent;
  final int? planned; // null when the goal has no end date
  final int? behindBy; // > 0 behind, < 0 ahead
  final int periodsLeft;
  final int? catchUpEach; // what each person must bring per period from now to finish on time
  const GoalStatus(this.target, this.collected, this.left, this.percent, this.planned, this.behindBy, this.periodsLeft, this.catchUpEach);

  bool get done => collected >= target;
  bool get onTrack => behindBy == null || behindBy! <= 0;

  static GoalStatus of({
    required int target,
    required int collected,
    required int people,
    required DateTime start,
    DateTime? end,
    required Frequency frequency,
    required DateTime today,
  }) {
    final left = max(0, target - collected);
    final percent = target <= 0 ? 0.0 : min(1.0, collected / target);
    if (end == null) return GoalStatus(target, collected, left, percent, null, null, 0, null);
    final planned = GoalMath.plannedBy(target, start, end, today);
    final from = today.isBefore(start) ? start : today;
    final periodsLeft = from.isAfter(end) ? 0 : GoalMath.periodsBetween(from, end, frequency);
    final catchUp = left == 0 || periodsLeft == 0 ? null : GoalMath.perPerson(left, people, periodsLeft);
    return GoalStatus(target, collected, left, percent, planned, planned - collected, periodsLeft, catchUp);
  }
}
