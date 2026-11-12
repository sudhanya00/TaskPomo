import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/session_check.dart';
import '../models/models.dart';
import '../services/notifications.dart';
import '../services/scroll_guard.dart';
import '../util/dates.dart';

/// A focus session. Time is derived from timestamps, never from ticking, so
/// it stays right if the app is killed or the phone sleeps.
class ActiveSession {
  ActiveSession({
    required this.taskId,
    required this.taskName,
    required this.date,
    required this.startedAt,
    this.accumulatedMs = 0,
    this.runningSince,
    this.breakStartedAt,
    this.breakMs = 0,
    this.pomodorosAcked = 0,
    this.roundMinutes,
    Map<String, AwayApp>? notCounted,
    Map<String, AwayApp>? unsure,
  }) : notCounted = notCounted ?? {},
       unsure = unsure ?? {};

  final String taskId;
  final String taskName;

  /// Day the time is credited to.
  final String date;
  final int startedAt;

  /// Focus time from finished segments.
  int accumulatedMs;

  /// Epoch ms the current focus segment began; null while paused or on break.
  int? runningSince;
  int? breakStartedAt;
  int breakMs;

  /// Pomodoros the user has already answered "break or keep going" for.
  int pomodorosAcked;

  /// Length of one round, fixed when the session starts: the pomodoro length,
  /// or the task's daily target if that's shorter. Null for sessions saved by
  /// older versions, which use the pomodoro length.
  final int? roundMinutes;

  /// Time in other apps that doesn't count (social apps, games, limited
  /// apps, and apps you said no to), by package.
  final Map<String, AwayApp> notCounted;

  /// Time in apps to ask about when the session ends. Counted until then.
  final Map<String, AwayApp> unsure;

  bool get running => runningSince != null;
  bool get onBreak => breakStartedAt != null;

  /// Timer time, before anything is taken off.
  int rawMs(int now) =>
      accumulatedMs + (runningSince != null ? now - runningSince! : 0);

  /// Time that counts: the timer minus time in apps that don't count.
  int focusMs(int now) {
    final ms = rawMs(now) - totalMs(notCounted.values);
    return ms < 0 ? 0 : ms;
  }

  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'taskName': taskName,
    'date': date,
    'startedAt': startedAt,
    'accumulatedMs': accumulatedMs,
    'runningSince': runningSince,
    'breakStartedAt': breakStartedAt,
    'breakMs': breakMs,
    'pomodorosAcked': pomodorosAcked,
    'roundMinutes': roundMinutes,
    'notCounted': [for (final a in notCounted.values) a.toJson()],
    'unsure': [for (final a in unsure.values) a.toJson()],
  };

  static Map<String, AwayApp> _apps(Object? raw) => {
    for (final m in (raw as List?) ?? const [])
      if (AwayApp.fromJson(m as Map<String, dynamic>) case final a)
        a.package: a,
  };

  factory ActiveSession.fromJson(Map<String, dynamic> j) => ActiveSession(
    taskId: j['taskId'] as String,
    taskName: j['taskName'] as String? ?? '',
    date: j['date'] as String,
    startedAt: j['startedAt'] as int,
    accumulatedMs: j['accumulatedMs'] as int? ?? 0,
    runningSince: j['runningSince'] as int?,
    breakStartedAt: j['breakStartedAt'] as int?,
    breakMs: j['breakMs'] as int? ?? 0,
    pomodorosAcked: j['pomodorosAcked'] as int? ?? 0,
    roundMinutes: j['roundMinutes'] as int?,
    notCounted: _apps(j['notCounted']),
    unsure: _apps(j['unsure']),
  );
}

class FinishedSession {
  const FinishedSession(
    this.taskId,
    this.date,
    this.startedAt,
    this.seconds, {
    this.notCounted = const [],
  });

  final String taskId;
  final String date;
  final int startedAt;
  final int seconds;

  /// Apps whose time was left out.
  final List<AwayApp> notCounted;

  int get notCountedSeconds => totalMs(notCounted) ~/ 1000;
}

class TimerController extends ChangeNotifier {
  TimerController(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        session = ActiveSession.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        _tick();
      } catch (_) {
        _prefs.remove(_key);
      }
    }
    ScrollGuard.setSessionRunning(session?.running ?? false);
  }

  static const _key = 'active_session';
  final SharedPreferences _prefs;
  Timer? _ticker;

  ActiveSession? session;
  int focusMinutes = 25;
  int breakMinutes = 5;
  int longBreakMinutes = 15;

  int get _focusLenMs => (session?.roundMinutes ?? focusMinutes) * 60000;

  /// Minutes in one round of the running session.
  int get roundMinutes => session?.roundMinutes ?? focusMinutes;
  int get _now => DateTime.now().millisecondsSinceEpoch;

  bool isActiveFor(String taskId) => session?.taskId == taskId;

  Duration get focus => Duration(milliseconds: session?.focusMs(_now) ?? 0);

  int get pomodorosDone => (session?.focusMs(_now) ?? 0) ~/ _focusLenMs;

  /// 0..1 through the current pomodoro.
  double get pomodoroProgress =>
      ((session?.focusMs(_now) ?? 0) % _focusLenMs) / _focusLenMs;

  Duration get pomodoroLeft => Duration(
    milliseconds: _focusLenMs - (session?.focusMs(_now) ?? 0) % _focusLenMs,
  );

  /// A pomodoro finished and the user hasn't said what to do next.
  bool get pomodoroDue {
    final s = session;
    return s != null && s.running && pomodorosDone > s.pomodorosAcked;
  }

  Duration get breakLeft {
    final s = session;
    if (s == null || s.breakStartedAt == null) return Duration.zero;
    final left = s.breakMs - (_now - s.breakStartedAt!);
    return Duration(milliseconds: left < 0 ? 0 : left);
  }

  double get breakProgress {
    final s = session;
    if (s == null || s.breakStartedAt == null || s.breakMs == 0) return 0;
    return ((_now - s.breakStartedAt!) / s.breakMs).clamp(0.0, 1.0);
  }

  void applyProfile(Profile p) {
    focusMinutes = p.focusMinutes;
    breakMinutes = p.breakMinutes;
    longBreakMinutes = p.longBreakMinutes;
    limitedApps = {for (final a in p.scrollApps) a.package};
  }

  /// Apps points pay for; they never count toward a task.
  Set<String> limitedApps = {};

  // Which apps each task always counts. Kept on the phone only: app names
  // never go to the account.
  static String _appsKey(String taskId) => 'task_apps_$taskId';

  /// Apps [taskId] always counts, package to name.
  Map<String, String> allowedApps(String taskId) => {
    for (final e in _prefs.getStringList(_appsKey(taskId)) ?? const <String>[])
      if (e.split('\t') case [final pkg, final label]) pkg: label,
  };

  void setAllowed(String taskId, String package, String label, bool on) {
    final apps = allowedApps(taskId);
    if (on) {
      apps[package] = label;
    } else {
      apps.remove(package);
    }
    _prefs.setStringList(_appsKey(taskId), [
      for (final e in apps.entries) '${e.key}\t${e.value}',
    ]);
    notifyListeners();
  }

  /// Collects what the guard noted while the timer ran. Time in apps that
  /// never count comes off the clock, and those apps are returned for a
  /// note; apps to ask about wait for the end of the session.
  Future<List<AwayApp>> collectAway() async {
    final log = await ScrollGuard.takeSessionLog();
    final s = session;
    if (s == null || log.isEmpty) return const [];
    final allowed = allowedApps(s.taskId).keys.toSet();
    final dropped = <AwayApp>[];
    for (final a in log) {
      switch (ruleFor(a, allowed: allowed, limited: limitedApps)) {
        case AppRule.never:
          mergeAway(s.notCounted, a);
          dropped.add(a);
        case AppRule.ask:
          mergeAway(s.unsure, a);
        case AppRule.count:
          break;
      }
    }
    _changed();
    return dropped;
  }

  /// Applies the answers from the end of a session: apps in [counted]
  /// keep their time, the rest is left out, and [remember] are always
  /// counted for this task from now on.
  void decide({required Set<String> counted, required Set<String> remember}) {
    final s = session;
    if (s == null) return;
    for (final a in s.unsure.values) {
      if (counted.contains(a.package)) {
        if (remember.contains(a.package)) {
          setAllowed(s.taskId, a.package, a.label, true);
        }
      } else {
        mergeAway(s.notCounted, a);
      }
    }
    s.unsure.clear();
    _changed();
  }

  void start(Task task) {
    final now = _now;
    session = ActiveSession(
      taskId: task.id,
      taskName: task.name,
      date: todayKey(),
      startedAt: now,
      runningSince: now,
      roundMinutes: task.targetMinutes < focusMinutes
          ? task.targetMinutes
          : focusMinutes,
    );
    Notifications.requestPermission();
    _changed();
  }

  void pause() {
    final s = session;
    if (s == null || !s.running) return;
    s.accumulatedMs = s.rawMs(_now);
    s.runningSince = null;
    _changed();
  }

  void resume() {
    final s = session;
    if (s == null || s.running) return;
    s.breakStartedAt = null;
    s.pomodorosAcked = pomodorosDone;
    s.runningSince = _now;
    _changed();
  }

  void keepGoing() {
    final s = session;
    if (s == null) return;
    s.pomodorosAcked = pomodorosDone;
    _changed();
  }

  void takeBreak() {
    final s = session;
    if (s == null) return;
    final n = pomodorosDone;
    s.accumulatedMs = s.rawMs(_now);
    s.runningSince = null;
    s.pomodorosAcked = n;
    s.breakStartedAt = _now;
    s.breakMs = (n > 0 && n % 4 == 0 ? longBreakMinutes : breakMinutes) * 60000;
    _changed();
  }

  /// Ends the session and returns what to log (null if nothing was running).
  FinishedSession? stop() {
    final s = session;
    if (s == null) return null;
    final result = FinishedSession(
      s.taskId,
      s.date,
      s.startedAt,
      s.focusMs(_now) ~/ 1000,
      notCounted: s.notCounted.values.toList(),
    );
    session = null;
    _changed();
    return result;
  }

  void _changed() {
    final s = session;
    ScrollGuard.setSessionRunning(s?.running ?? false);
    if (s == null) {
      _prefs.remove(_key);
    } else {
      _prefs.setString(_key, jsonEncode(s.toJson()));
    }
    _tick();
    _syncNotifications();
    notifyListeners();
  }

  void _tick() {
    _ticker?.cancel();
    if (session == null) return;
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
  }

  /// Notifications show on the lock screen, so they never name the task.
  void _syncNotifications() {
    final s = session;
    if (s == null) {
      Notifications.clearSession();
      return;
    }
    final now = _now;
    final round = pomodorosDone + 1;
    if (s.running) {
      Notifications.showSession(
        title: 'Focus session',
        body: 'Round $round',
        runningSince: DateTime.fromMillisecondsSinceEpoch(now - s.focusMs(now)),
      );
      Notifications.scheduleBell(
        DateTime.fromMillisecondsSinceEpoch(now + pomodoroLeft.inMilliseconds),
        'Round $round done',
        'Take a break, or keep going.',
      );
    } else if (s.onBreak) {
      Notifications.showSession(
        title: 'On a break',
        body: '${formatClock(focus)} focused so far',
      );
      Notifications.scheduleBell(
        DateTime.fromMillisecondsSinceEpoch(s.breakStartedAt! + s.breakMs),
        'Break over',
        'Ready for the next round?',
      );
    } else {
      Notifications.showSession(
        title: 'Session paused',
        body: '${formatClock(focus)} focused',
      );
      Notifications.cancelBell();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
