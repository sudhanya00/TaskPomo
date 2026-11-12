import '../models/models.dart';
import '../util/dates.dart';
import 'streaks.dart';

/// One CSV cell: quoted when it holds a comma, quote or line break.
String csvCell(Object? v) {
  if (v == null) return '';
  final s = '$v';
  if (s.contains(RegExp(r'[",\r\n]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String csv(List<List<Object?>> rows) =>
    '${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';

/// ISO 8601 local time with the UTC offset, e.g. 2026-10-23T22:04:10+05:30.
String isoWithOffset(DateTime t) {
  final o = t.timeZoneOffset;
  final sign = o.isNegative ? '-' : '+';
  final h = o.inHours.abs().toString().padLeft(2, '0');
  final m = (o.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final base = t.toIso8601String().split('.').first;
  return '$base$sign$h:$m';
}

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

double _min(int seconds) => (seconds / 60 * 10).round() / 10;

/// Builds the export: file name -> contents. [tasks] should include removed
/// tasks so old history keeps its names.
Map<String, String> buildExport({
  required List<Task> tasks,
  required List<DayLog> days,
  required List<Session> sessions,
  required List<LedgerEntry> ledger,
  required String today,
}) {
  final names = {for (final t in tasks) t.id: t.name};
  final logs = {for (final d in days) DayLog.idFor(d.taskId, d.date): d};

  final taskRows = <List<Object?>>[
    [
      'task_id',
      'task',
      'icon',
      'target_minutes',
      'days',
      'created',
      'current_streak',
      'clean_streak',
      'best_streak',
      'total_minutes',
      'points_per_day',
      'freeze_cost',
      'archived',
    ],
    for (final t in tasks)
      [
        t.id,
        t.name,
        t.icon,
        t.targetMinutes,
        (t.days.toList()..sort()).map((d) => _weekdayNames[d - 1]).join(';'),
        t.createdDate,
        t.currentStreak,
        t.cleanStreak,
        t.bestStreak,
        _min(t.totalSeconds),
        pointValue(t.targetMinutes),
        freezeCostFor(t.targetMinutes),
        t.archived,
      ],
  ];

  // Every task-day from creation to today, including missed and rest days,
  // so the ledger is complete for analysis.
  final dayRows = <List<Object?>>[
    [
      'task_id',
      'task',
      'date',
      'weekday',
      'due',
      'target_minutes',
      'minutes',
      'completed',
      'frozen',
      'freeze_paid',
    ],
  ];
  for (final t in tasks) {
    for (final d in daysBetween(t.createdDate, addDays(today, 1))) {
      final l = logs[DayLog.idFor(t.id, d)];
      dayRows.add([
        t.id,
        t.name,
        d,
        _weekdayNames[weekdayOf(d) - 1],
        t.isDueOn(d),
        t.targetMinutes,
        _min(l?.seconds ?? 0),
        l?.completed ?? false,
        l?.frozen ?? false,
        l?.freezePaid,
      ]);
    }
  }
  // Days logged against tasks that no longer exist.
  for (final d in days.where((d) => !names.containsKey(d.taskId))) {
    dayRows.add([
      d.taskId,
      '',
      d.date,
      _weekdayNames[weekdayOf(d.date) - 1],
      '',
      '',
      _min(d.seconds),
      d.completed,
      d.frozen,
      d.freezePaid,
    ]);
  }

  final sorted = [...sessions]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final sessionRows = <List<Object?>>[
    [
      'session_id',
      'task_id',
      'task',
      'date',
      'started_at',
      'seconds',
      'minutes',
      'source',
      'note',
    ],
    for (final s in sorted)
      [
        s.id,
        s.taskId,
        names[s.taskId] ?? '',
        s.date,
        s.startedAt > 0
            ? isoWithOffset(DateTime.fromMillisecondsSinceEpoch(s.startedAt))
            : '',
        s.seconds,
        _min(s.seconds),
        s.manual ? 'manual' : 'timer',
        s.note,
      ],
  ];

  var balance = 0;
  final pointRows = <List<Object?>>[
    ['at', 'amount', 'balance', 'reason'],
    for (final e in [...ledger]..sort((a, b) => a.at.compareTo(b.at)))
      [
        isoWithOffset(DateTime.fromMillisecondsSinceEpoch(e.at)),
        e.amount,
        balance += e.amount,
        e.reason,
      ],
  ];

  return {
    'README.txt': _readme(today),
    'tasks.csv': csv(taskRows),
    'days.csv': csv(dayRows),
    'sessions.csv': csv(sessionRows),
    'points.csv': csv(pointRows),
  };
}

String _readme(String today) =>
    '''
TaskPomo export, $today

Four CSV files, UTF-8, comma-separated, RFC 4180 quoting, one header row.
Dates are local calendar days (YYYY-MM-DD). Timestamps are ISO 8601 with the
UTC offset. Minutes are rounded to 0.1.

tasks.csv - one row per task, including removed ones (archived = true)
  task_id         stable id; joins the other files
  task            name
  icon            icon key
  target_minutes  daily target
  days            weekdays the task is due, Mon..Sun, ';'-separated
  created         date the task was created
  current_streak  due days in a row done or frozen, as of export
  clean_streak    the same, but reset by freezes
  best_streak     longest streak so far
  total_minutes   all time logged
  points_per_day  points earned for a day that meets the target
  freeze_cost     points to freeze one day
  archived        removed from the app's lists

days.csv - one row per task per calendar day, from the task's creation to
today, including missed and rest days (the full ledger)
  due             the task was scheduled that day
  minutes         time logged that day (0 if none)
  completed       the target was met
  frozen          the day was frozen with points (streak kept)
  freeze_paid     points paid for that freeze
  A due day that is neither completed nor frozen, before today, was missed.

sessions.csv - one row per timer session or manual entry
  started_at      when it started (manual entries: when they were logged)
  seconds         focused time (pauses and breaks excluded)
  source          timer or manual
  note            what the user wrote about the session, if anything

points.csv - every points change
  amount          positive when earned, negative when spent
  balance         running total within this file
  reason          e.g. "Read done", "Auto-freeze x1 - Read"
''';
