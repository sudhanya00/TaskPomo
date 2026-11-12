import '../models/models.dart';
import '../util/dates.dart';

class TaskStats {
  TaskStats(this.task);

  final Task task;
  int weekSec = 0, monthSec = 0, yearSec = 0;
  String? bestDay;
  int bestDaySec = 0;
  int dueDays30 = 0, doneDays30 = 0;

  int get allSec => task.totalSeconds;
  double get consistency => dueDays30 == 0 ? 0 : doneDays30 / dueDays30;

  /// Share of the proverbial 10,000 hours.
  double get mastery => allSec / 3600 / 10000;

  Map<String, Object?> toJson() => {
    'skill': task.name,
    'dailyTargetMin': task.targetMinutes,
    'schedule': describeDays(task.days),
    'minutesThisWeek': weekSec ~/ 60,
    'minutesThisMonth': monthSec ~/ 60,
    'minutesThisYear': yearSec ~/ 60,
    'minutesAllTime': allSec ~/ 60,
    'currentStreakDays': task.currentStreak,
    'bestStreakDays': task.bestStreak,
    'consistencyLast30DaysPct': (consistency * 100).round(),
    if (bestDay != null)
      'bestDay': {'date': bestDay, 'minutes': bestDaySec ~/ 60},
  };
}

class Insights {
  Insights(this.tasks, this.last7);

  final List<TaskStats> tasks;

  /// Focused seconds per day for the last 7 days (oldest first).
  final List<MapEntry<String, int>> last7;

  int get yearSec => tasks.fold(0, (s, t) => s + t.yearSec);
  int get weekSec => tasks.fold(0, (s, t) => s + t.weekSec);
}

/// [logs] should cover at least the current year and the last 30 days.
Insights computeInsights(List<Task> tasks, List<DayLog> logs, String today) {
  final wk = weekStart(today), mo = monthStart(today), yr = yearStart(today);
  final from30 = addDays(today, -30);
  final byTask = {for (final t in tasks) t.id: TaskStats(t)};
  final byTaskDate = <String, DayLog>{};
  final perDay = <String, int>{};

  for (final l in logs) {
    final s = byTask[l.taskId];
    if (s == null) continue;
    byTaskDate['${l.taskId}|${l.date}'] = l;
    perDay[l.date] = (perDay[l.date] ?? 0) + l.seconds;
    if (l.date.compareTo(yr) >= 0) s.yearSec += l.seconds;
    if (l.date.compareTo(mo) >= 0) s.monthSec += l.seconds;
    if (l.date.compareTo(wk) >= 0) s.weekSec += l.seconds;
    if (l.seconds > s.bestDaySec) {
      s.bestDaySec = l.seconds;
      s.bestDay = l.date;
    }
  }

  for (final s in byTask.values) {
    final t = s.task;
    final start = t.createdDate.compareTo(from30) > 0 ? t.createdDate : from30;
    for (final d in daysBetween(start, today)) {
      if (!t.isDueOn(d)) continue;
      s.dueDays30++;
      if (byTaskDate['${t.id}|$d']?.completed ?? false) s.doneDays30++;
    }
    // Today counts once it's done, so a fresh day doesn't drag the score.
    if (t.isDueOn(today) &&
        (byTaskDate['${t.id}|$today']?.completed ?? false)) {
      s.dueDays30++;
      s.doneDays30++;
    }
  }

  final last7 = [
    for (var i = 6; i >= 0; i--)
      MapEntry(addDays(today, -i), perDay[addDays(today, -i)] ?? 0),
  ];
  return Insights(byTask.values.toList(), last7);
}
