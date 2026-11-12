import 'dart:math' as math;

import '../models/models.dart';
import '../util/dates.dart';

/// Points rules. Kept in one place so they're easy to tune.
///
/// A task's daily value grows with its target, about one point per three
/// minutes, so two hours of work is worth far more than brushing your teeth.
int pointValue(int targetMinutes) => math.max(1, (targetMinutes / 3).round());

/// Freezing one day of a task costs several days of that task's points:
/// five days' worth for short tasks (5 min or less), sliding down to three
/// days' worth for long ones (2 h or more), on a log scale in between.
double freezeDays(int targetMinutes) {
  const short = 5, long = 120;
  final t = targetMinutes.clamp(short, long);
  final f = math.log(t / short) / math.log(long / short);
  return 5 - 2 * f;
}

int freezeCostFor(int targetMinutes) =>
    (pointValue(targetMinutes) * freezeDays(targetMinutes)).ceil();

/// Clean (freeze-free) streak milestones, paid as multiples of the task's
/// daily value. Kept modest: everything up to a year adds up to 38 days'
/// worth, about a tenth of what the practice itself earns, so a milestone
/// buys a few freezes at most.
const _multiplier = {
  10: 1,
  20: 1,
  50: 3,
  100: 5,
  150: 5,
  200: 6,
  300: 7,
  365: 10,
};

/// Bonus multiplier at [cleanStreak], or 0 if it isn't a milestone. Past
/// 300, every hundred is one too.
int _milestoneMultiplier(int cleanStreak) {
  final m = _multiplier[cleanStreak];
  if (m != null) return m;
  return cleanStreak > 300 && cleanStreak % 100 == 0 ? 7 : 0;
}

int milestoneBonus(int cleanStreak, int targetMinutes) =>
    _milestoneMultiplier(cleanStreak) * pointValue(targetMinutes);

bool isMilestone(int cleanStreak) => _milestoneMultiplier(cleanStreak) > 0;

/// The next clean-streak milestone after [cleanStreak].
int nextMilestone(int cleanStreak) {
  for (final m in _multiplier.keys) {
    if (m > cleanStreak) return m;
  }
  return (cleanStreak ~/ 100 + 1) * 100;
}

/// The last milestone at or before [cleanStreak], or 0.
int previousMilestone(int cleanStreak) {
  var best = 0;
  for (final m in _multiplier.keys) {
    if (m <= cleanStreak) best = m;
  }
  final hundred = cleanStreak ~/ 100 * 100;
  return hundred > 300 && hundred > best ? hundred : best;
}

class EvalOutcome {
  const EvalOutcome({
    required this.streak,
    required this.autoFrozen,
    required this.missed,
    required this.lostStreak,
    required this.freezeCost,
  });

  final StreakSnapshot streak;

  /// Missed due days covered by spending points.
  final List<String> autoFrozen;

  /// Missed due days that broke the streak.
  final List<String> missed;

  /// Streak length that was lost (0 if none).
  final int lostStreak;

  /// What one freeze of this task cost.
  final int freezeCost;

  int get pointsSpent => autoFrozen.length * freezeCost;
}

/// Settles every day after [Task.lastChecked] and before [today] (or before
/// [holdFrom], the start date of a still-running session for this task).
///
/// Completed days were already counted when they were completed, so here we
/// only deal with due days that weren't: a frozen day keeps the streak but
/// resets the clean streak; a missed day is auto-frozen if allowed and
/// affordable, otherwise the streak breaks.
EvalOutcome evaluateMissedDays({
  required Task task,
  required Map<String, DayLog> logsByDate,
  required String today,
  required int pointsAvailable,
  required bool autoFreeze,
  String? holdFrom,
}) {
  final end = holdFrom != null && holdFrom.compareTo(today) < 0
      ? holdFrom
      : today;
  var current = task.currentStreak, clean = task.cleanStreak, lost = 0;
  var points = pointsAvailable;
  final autoFrozen = <String>[], missed = <String>[];
  var last = task.lastChecked;
  final cost = freezeCostFor(task.targetMinutes);

  for (final d in daysBetween(addDays(task.lastChecked, 1), end)) {
    last = d;
    if (!task.isDueOn(d)) continue;
    final log = logsByDate[d];
    if (log != null && log.completed) continue;
    if (log != null && log.frozen) {
      clean = 0;
      continue;
    }
    if (autoFreeze && points >= cost) {
      points -= cost;
      autoFrozen.add(d);
      clean = 0;
    } else {
      missed.add(d);
      if (current > 0) lost = current;
      current = 0;
      clean = 0;
    }
  }

  return EvalOutcome(
    streak: StreakSnapshot(
      current: current,
      clean: clean,
      best: task.bestStreak,
      lastChecked: last,
    ),
    autoFrozen: autoFrozen,
    missed: missed,
    lostStreak: lost,
    freezeCost: cost,
  );
}

class CompletionOutcome {
  const CompletionOutcome({
    required this.streak,
    required this.points,
    required this.bonus,
  });

  final StreakSnapshot streak;
  final int points;
  final int bonus;
}

/// A due day just reached its target.
CompletionOutcome applyCompletion(StreakSnapshot s, int targetMinutes) {
  final current = s.current + 1, clean = s.clean + 1;
  return CompletionOutcome(
    streak: StreakSnapshot(
      current: current,
      clean: clean,
      best: current > s.best ? current : s.best,
      lastChecked: s.lastChecked,
    ),
    points: pointValue(targetMinutes),
    bonus: milestoneBonus(clean, targetMinutes),
  );
}

/// Streak as it should be shown today: if today is due and not done yet,
/// the streak is still intact but "at risk".
bool streakAtRisk(Task t, DayLog? todayLog, String today) =>
    t.isDueOn(today) &&
    !(todayLog?.completed ?? false) &&
    !(todayLog?.frozen ?? false);
