import '../models/models.dart';
import '../util/dates.dart';

enum DayKind {
  /// A past day with something due.
  past,

  /// Nothing was due.
  rest,

  /// Today, still open.
  today,

  /// Later this week.
  future,
}

/// One square in the Monday-to-Sunday strip. Streaks belong to tasks, so a
/// day isn't pass/fail: [fill] is how much of that day's work got done.
class DayCell {
  const DayCell(this.kind, this.fill);

  final DayKind kind;

  /// 0..1, weighted by each task's target so a two-hour task counts for more
  /// than a five-minute one. Done or frozen tasks count in full.
  final double fill;

  @override
  bool operator ==(Object other) =>
      other is DayCell && other.kind == kind && other.fill == fill;

  @override
  int get hashCode => Object.hash(kind, fill);

  @override
  String toString() => '${kind.name}:${fill.toStringAsFixed(2)}';
}

/// How much of [date]'s due work is done, weighted by target minutes.
double dayFill(
  List<Task> tasks,
  Map<String, DayLog> logsByTaskDate,
  String date,
) {
  var target = 0, done = 0.0;
  for (final t in tasks.where((t) => t.isDueOn(date))) {
    final l = logsByTaskDate[DayLog.idFor(t.id, date)];
    target += t.targetMinutes;
    if ((l?.completed ?? false) || (l?.frozen ?? false)) {
      done += t.targetMinutes;
    } else {
      done += ((l?.seconds ?? 0) / 60).clamp(0, t.targetMinutes);
    }
  }
  return target == 0 ? 0 : done / target;
}

List<DayCell> weekCells({
  required List<Task> tasks,
  required List<DayLog> logs,
  required String today,
}) {
  final byKey = {for (final l in logs) DayLog.idFor(l.taskId, l.date): l};
  final start = weekStart(today);
  return [
    for (var i = 0; i < 7; i++)
      () {
        final d = addDays(start, i);
        if (d.compareTo(today) > 0) return const DayCell(DayKind.future, 0);
        final fill = dayFill(tasks, byKey, d);
        if (d == today) return DayCell(DayKind.today, fill);
        if (!tasks.any((t) => t.isDueOn(d))) {
          return const DayCell(DayKind.rest, 0);
        }
        return DayCell(DayKind.past, fill);
      }(),
  ];
}
