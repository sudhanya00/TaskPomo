import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repo.dart';
import '../logic/streaks.dart';
import '../logic/week.dart';
import '../models/models.dart';
import '../util/dates.dart';

/// Holds the live view of the user's data and runs the daily streak check.
class AppController extends ChangeNotifier {
  AppController(this.repo) {
    _start();
  }

  final Repo repo;

  Profile profile = const Profile();
  List<Task> tasks = const [];
  Map<String, DayLog> todayLogs = const {};

  /// Logs from Monday of this week onward, for the week strip.
  List<DayLog> weekLogs = const [];
  String today = todayKey();
  bool tasksLoaded = false;
  bool profileLoaded = false;

  /// Task id and start date of a running focus session; its days are not
  /// settled until the session is logged.
  ({String taskId, String date})? activeSession;

  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<List<DayLog>>? _todaySub;
  StreamSubscription<List<DayLog>>? _weekSub;
  Timer? _clock;
  bool _evaluating = false;
  String? _evaluatedFor;

  void _start() {
    repo.ensureProfile();
    _subs.add(
      repo.profile().listen((p) {
        profile = p;
        profileLoaded = true;
        notifyListeners();
        if (_evaluatedFor != today) evaluateStreaks();
      }),
    );
    _subs.add(
      repo.tasks().listen((t) {
        tasks = t;
        tasksLoaded = true;
        notifyListeners();
        if (_evaluatedFor != today) evaluateStreaks();
      }),
    );
    _watchToday();
    _clock = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkDayChange(),
    );
  }

  void _watchToday() {
    _todaySub?.cancel();
    _todaySub = repo.daysOn(today).listen((logs) {
      todayLogs = {for (final l in logs) l.taskId: l};
      notifyListeners();
    });
    _weekSub?.cancel();
    _weekSub = repo.daysSince(weekStart(today)).listen((logs) {
      weekLogs = logs;
      notifyListeners();
    });
  }

  int _tick = -1;

  void _checkDayChange() {
    // Redraw every five minutes so time-based looks (the paper aging) move.
    final tick = DateTime.now().minute ~/ 5;
    if (tick != _tick) {
      _tick = tick;
      notifyListeners();
    }
    final now = todayKey();
    if (now == today) return;
    today = now;
    todayLogs = const {};
    _watchToday();
    notifyListeners();
    evaluateStreaks();
  }

  /// Also called when the app comes back to the foreground.
  void refresh() => _checkDayChange();

  Task? taskById(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<DayCell> get week =>
      weekCells(tasks: tasks, logs: weekLogs, today: today);

  List<Task> get dueToday => tasks.where((t) => t.isDueOn(today)).toList();
  List<Task> get notToday => tasks.where((t) => !t.isDueOn(today)).toList();

  /// Settle every day since each task was last checked: freeze or break.
  Future<void> evaluateStreaks() async {
    if (_evaluating || !tasksLoaded || !profileLoaded) return;
    _evaluating = true;
    try {
      final yesterday = addDays(today, -1);
      final pending = tasks
          .where((t) => t.lastChecked.compareTo(yesterday) < 0)
          .toList();
      _evaluatedFor = today;
      if (pending.isEmpty) return;
      final from = pending
          .map((t) => t.lastChecked)
          .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
      final logs = await repo.daysAfter(from);
      var points = profile.points;
      for (final t in pending) {
        final outcome = evaluateMissedDays(
          task: t,
          logsByDate: {
            for (final l in logs.where((l) => l.taskId == t.id)) l.date: l,
          },
          today: today,
          pointsAvailable: points,
          autoFreeze: profile.autoFreeze,
          holdFrom: activeSession?.taskId == t.id ? activeSession!.date : null,
        );
        points -= outcome.pointsSpent;
        if (outcome.streak.lastChecked != t.lastChecked) {
          repo.applyEvaluation(t, outcome);
        }
      }
    } catch (e) {
      debugPrint('Streak check failed: $e');
      _evaluatedFor = null;
    } finally {
      _evaluating = false;
    }
  }

  /// Logs focused time against [date] and reports any completion, plus the
  /// session id for attaching a note.
  Future<({CompletionOutcome? outcome, String sessionId})> logTime(
    Task task,
    String date,
    int seconds, {
    required int startedAt,
    bool manual = false,
    int notCountedSeconds = 0,
  }) async {
    final existing = date == today
        ? todayLogs[task.id]
        : await repo.day(task.id, date);
    // Use the freshest streak numbers we have.
    final fresh = taskById(task.id) ?? task;
    return repo.logTime(
      task: fresh,
      date: date,
      existing: existing,
      seconds: seconds,
      startedAt: startedAt,
      manual: manual,
      notCountedSeconds: notCountedSeconds,
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _todaySub?.cancel();
    _weekSub?.cancel();
    _clock?.cancel();
    super.dispose();
  }
}
