import '../models/models.dart';
import '../util/dates.dart';

/// The time windows Insights can look at.
enum Span { week, month, year, all }

/// Inclusive date range of day keys.
class DateRange {
  const DateRange(this.from, this.to);

  final String from;
  final String to;

  bool contains(String d) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0;

  int get days => daysBetween(from, addDays(to, 1)).length;

  /// Calendar month 'YYYY-MM'.
  factory DateRange.month(String ym) {
    final start = '$ym-01';
    final next = parseKey(start);
    return DateRange(
      start,
      addDays(dateKey(DateTime(next.year, next.month + 1, 1)), -1),
    );
  }

  factory DateRange.year(int y) => DateRange('$y-01-01', '$y-12-31');

  @override
  String toString() => '$from..$to';
}

/// The range for [s], never starting before [earliest] (your first task),
/// so "days showed up" counts only days you could have.
DateRange rangeFor(Span s, String today, String earliest) {
  final from = switch (s) {
    Span.week => weekStart(today),
    Span.month => monthStart(today),
    Span.year => yearStart(today),
    Span.all => earliest,
  };
  final floor = earliest.compareTo(today) < 0 ? earliest : today;
  return DateRange(from.compareTo(floor) < 0 ? floor : from, today);
}

/// One unbroken streak: consecutive due days done (or frozen), with no due
/// day missed in between. Days a task isn't due never break a run.
class Run {
  const Run(this.start, this.end, this.length);

  final String start;
  final String end;

  /// Due days in the run.
  final int length;

  @override
  String toString() => '$start..$end($length)';
}

/// Time grouped for the "where the time went" chart.
class Bucket {
  const Bucket(this.start, this.label, this.perTask);

  final String start;
  final String label;

  /// Seconds per task, in task order.
  final List<int> perTask;

  int get total => perTask.fold(0, (s, x) => s + x);
}

class Analytics {
  Analytics._(this.tasks, this.range);

  final List<Task> tasks;
  final DateRange range;

  /// Seconds per day (all tasks) and per task per day.
  final perDay = <String, int>{};
  final perTaskDay = <String, Map<String, int>>{};

  int totalSec = 0;
  int daysShowed = 0;
  int sessions = 0;
  double medianSessionMin = 0;
  String? bestDay;
  int bestDaySec = 0;

  /// Minutes started per weekday (0 = Monday) and hour.
  final focus = List.generate(7, (_) => List.filled(24, 0));

  /// Session counts in 5-minute bins; the last bin is 75 minutes and up.
  final lengthBins = List.filled(16, 0);

  /// Average minutes on a due day, and that as a share of the target.
  late final List<double> avgDueMin;
  late final List<double> targetRatio;

  late final List<List<Run>> runs;
  late final List<int> bestRun;

  /// Share of settled due days that were done (or frozen).
  late final List<double> completion;

  /// Settled due days per task (today counts once done).
  late final List<int> dueDays;

  /// together[i][j]: on days task i was completed, how often task j (when
  /// due) was completed too. Frozen days don't count. NaN where there's no
  /// data.
  late final List<List<double>> together;

  late final List<Bucket> buckets;

  /// Seconds per task over the whole range.
  late final List<int> taskTotals;
}

/// Everything Insights needs for [range], computed once. [today] limits
/// "due" to days that have happened; today itself only counts once done.
Analytics analyze({
  required List<Task> tasks,
  required List<DayLog> days,
  required List<Session> sessions,
  required DateRange range,
  required String today,
}) {
  final a = Analytics._(tasks, range);
  final ids = {for (var i = 0; i < tasks.length; i++) tasks[i].id: i};
  final logs = <String, DayLog>{};
  for (final d in days) {
    if (!ids.containsKey(d.taskId) || !range.contains(d.date)) continue;
    logs[DayLog.idFor(d.taskId, d.date)] = d;
    if (d.seconds <= 0) continue;
    a.perDay[d.date] = (a.perDay[d.date] ?? 0) + d.seconds;
    (a.perTaskDay[d.taskId] ??= {})[d.date] = d.seconds;
    a.totalSec += d.seconds;
  }
  a.daysShowed = a.perDay.length;
  for (final e in a.perDay.entries) {
    if (e.value > a.bestDaySec) {
      a.bestDaySec = e.value;
      a.bestDay = e.key;
    }
  }

  final lengths = <int>[];
  for (final s in sessions) {
    if (!ids.containsKey(s.taskId) ||
        !range.contains(s.date) ||
        s.seconds <= 0) {
      continue;
    }
    a.sessions++;
    lengths.add(s.seconds);
    final mins = s.seconds ~/ 60;
    a.lengthBins[(mins ~/ 5).clamp(0, 15)]++;
    if (s.startedAt > 0 && !s.manual) {
      final t = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
      a.focus[t.weekday - 1][t.hour] += mins;
    }
  }
  lengths.sort();
  if (lengths.isNotEmpty) {
    final mid = lengths.length ~/ 2;
    final m = lengths.length.isOdd
        ? lengths[mid].toDouble()
        : (lengths[mid - 1] + lengths[mid]) / 2;
    a.medianSessionMin = m / 60;
  }

  // Per-task day-by-day pass: due days, completion, runs, averages.
  bool ok(int i, String d) {
    final l = logs[DayLog.idFor(tasks[i].id, d)];
    return (l?.completed ?? false) || (l?.frozen ?? false);
  }

  final end = range.to.compareTo(today) < 0 ? range.to : today;
  final dates = daysBetween(range.from, addDays(end, 1)).toList();
  final avg = <double>[], ratio = <double>[], comp = <double>[], best = <int>[];
  final dueCounts = <int>[];
  final allRuns = <List<Run>>[];
  for (var i = 0; i < tasks.length; i++) {
    final t = tasks[i];
    var due = 0, done = 0, sec = 0;
    final rs = <Run>[];
    String? start, last;
    var len = 0;
    void close() {
      if (start != null && len > 0) rs.add(Run(start!, last!, len));
      start = null;
      len = 0;
    }

    for (final d in dates) {
      if (!t.isDueOn(d)) continue;
      final settled = ok(i, d);
      // Today doesn't count against you until it's over.
      if (d == today && !settled) continue;
      due++;
      sec += logs[DayLog.idFor(t.id, d)]?.seconds ?? 0;
      if (settled) {
        done++;
        start ??= d;
        last = d;
        len++;
      } else {
        close();
      }
    }
    close();
    avg.add(due == 0 ? 0 : sec / 60 / due);
    ratio.add(due == 0 ? 0 : sec / 60 / due / t.targetMinutes);
    comp.add(due == 0 ? 0 : done / due);
    best.add(rs.fold(0, (m, r) => r.length > m ? r.length : m));
    dueCounts.add(due);
    allRuns.add(rs);
  }
  a.avgDueMin = avg;
  a.targetRatio = ratio;
  a.completion = comp;
  a.dueDays = dueCounts;
  a.bestRun = best;
  a.runs = allRuns;

  // Which habits travel together. Only real completions count here: a
  // frozen day was skipped on purpose.
  bool completed(int i, String d) =>
      logs[DayLog.idFor(tasks[i].id, d)]?.completed ?? false;
  a.together = [
    for (var i = 0; i < tasks.length; i++)
      [
        for (var j = 0; j < tasks.length; j++)
          () {
            if (i == j) return double.nan;
            var base = 0, both = 0;
            for (final d in dates) {
              if (!tasks[i].isDueOn(d) ||
                  !tasks[j].isDueOn(d) ||
                  !completed(i, d)) {
                continue;
              }
              base++;
              if (completed(j, d)) both++;
            }
            return base == 0 ? double.nan : both / base;
          }(),
      ],
  ];

  a.taskTotals = [
    for (final t in tasks)
      (a.perTaskDay[t.id]?.values ?? const <int>[]).fold(0, (s, x) => s + x),
  ];
  a.buckets = _buckets(a, dates);
  return a;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String shortDate(String key) {
  final d = parseKey(key);
  return '${d.day} ${_months[d.month - 1]}';
}

/// Days for a month or less, weeks up to half a year, months beyond.
List<Bucket> _buckets(Analytics a, List<String> dates) {
  if (dates.isEmpty) return const [];
  String keyOf(String d) {
    if (dates.length <= 31) return d;
    if (dates.length <= 26 * 7) return weekStart(d);
    return monthStart(d);
  }

  final order = <String>[];
  final sums = <String, List<int>>{};
  for (final d in dates) {
    final k = keyOf(d);
    if (!sums.containsKey(k)) {
      order.add(k);
      sums[k] = List.filled(a.tasks.length, 0);
    }
    for (var i = 0; i < a.tasks.length; i++) {
      sums[k]![i] += a.perTaskDay[a.tasks[i].id]?[d] ?? 0;
    }
  }
  final monthly = dates.length > 26 * 7;
  return [
    for (final k in order)
      Bucket(
        k,
        monthly
            ? '${_months[parseKey(k).month - 1]} ${k.substring(2, 4)}'
            : shortDate(k),
        sums[k]!,
      ),
  ];
}

/// Busiest two-hour window for starting sessions, as its first hour.
int peakStartHour(Analytics a) {
  final byHour = List.filled(24, 0);
  for (final row in a.focus) {
    for (var h = 0; h < 24; h++) {
      byHour[h] += row[h];
    }
  }
  var best = 0, at = 9;
  for (var h = 0; h < 23; h++) {
    final v = byHour[h] + byHour[h + 1];
    if (v > best) {
      best = v;
      at = h;
    }
  }
  return at;
}

/// The longest run across all tasks: (task index, run), or null.
(int, Run)? longestRun(Analytics a) {
  (int, Run)? best;
  for (var i = 0; i < a.runs.length; i++) {
    for (final r in a.runs[i]) {
      if (best == null || r.length > best.$2.length) best = (i, r);
    }
  }
  return best;
}

/// 'YYYY-MM' of the month before [ym].
String previousMonth(String ym) {
  final d = parseKey('$ym-01');
  final p = DateTime(d.year, d.month - 1, 1);
  return '${p.year}-${p.month.toString().padLeft(2, '0')}';
}

/// Months with any history, newest first, from [earliest] up to the last
/// finished month before [today].
List<String> finishedMonths(String earliest, String today) {
  final out = <String>[];
  var ym = previousMonth(today.substring(0, 7));
  final first = earliest.substring(0, 7);
  while (ym.compareTo(first) >= 0) {
    out.add(ym);
    ym = previousMonth(ym);
  }
  return out;
}

String monthName(String ym) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return names[int.parse(ym.substring(5, 7)) - 1];
}
