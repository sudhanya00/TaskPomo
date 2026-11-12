import '../models/models.dart';

/// How yellowed the ledger paper should look right now, 0 (fresh) to 1
/// (old). It ages through the day only while work is left: the share of
/// today's target minutes still to do, times how far the day has gone
/// (fresh at 9 am, oldest at midnight). Finish everything and it's fresh.
///
/// The widget mirrors this in PomoWidgetProvider.kt.
double paperAge({
  required List<Task> tasks,
  required Map<String, DayLog> todayLogs,
  required String today,
  required DateTime now,
}) {
  var target = 0, left = 0.0;
  for (final t in tasks.where((t) => t.isDueOn(today))) {
    final l = todayLogs[t.id];
    target += t.targetMinutes;
    if ((l?.completed ?? false) || (l?.frozen ?? false)) continue;
    left += (t.targetMinutes - (l?.seconds ?? 0) / 60).clamp(
      0,
      t.targetMinutes,
    );
  }
  if (target == 0 || left == 0) return 0;
  final hours = now.hour + now.minute / 60;
  final dayGone = ((hours - 9) / 15).clamp(0.0, 1.0);
  return dayGone * left / target;
}
