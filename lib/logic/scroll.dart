import 'dart:math' as math;

import '../models/models.dart';
import 'streaks.dart';

/// Points double as minutes on the apps you choose to limit: one point buys
/// one minute, across all of them combined.
const minutesPerPoint = 1;

/// Grace when you hit zero: once a day, repaid from future points.
const graceMinutes = 5;

/// Points scrolling can't touch unless you change it: enough for two freezes
/// of your biggest task, rounded up to ten.
int defaultReserve(List<Task> tasks) {
  final biggest = tasks.fold<int>(
    0,
    (m, t) => math.max(m, freezeCostFor(t.targetMinutes)),
  );
  return ((biggest * 2 + 9) ~/ 10) * 10;
}

/// Seconds of scrolling the points above the reserve buy. Negative when
/// you're below the reserve (grace minutes are repaid from here).
int allowanceSeconds(int points, int reserve) =>
    (points - reserve) * minutesPerPoint * 60;

/// "Instagram 8, YouTube 4": where the minutes went, biggest first.
String spendSummary(Map<String, int> secondsByApp) {
  final parts = secondsByApp.entries.where((e) => e.value >= 30).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return parts.map((e) => '${e.key} ${(e.value / 60).round()}').join(', ');
}
