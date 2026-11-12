import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repo.dart';
import 'logic/session_check.dart';
import 'screens/home_shell.dart';
import 'screens/monthly_recap_screen.dart';
import 'screens/nav.dart';
import 'screens/sign_in_screen.dart';
import 'screens/timer_screen.dart';
import 'services/notifications.dart';
import 'services/scroll_guard.dart';
import 'services/widget_sync.dart';
import 'state/app_controller.dart';
import 'state/timer_controller.dart';
import 'theme.dart';
import 'ui/kit.dart';
import 'util/dates.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class TaskPomoApp extends StatelessWidget {
  const TaskPomoApp({super.key, required this.prefs, this.setupError});

  final SharedPreferences prefs;
  final Object? setupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskPomo',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      home: setupError != null
          ? _SetupNeeded(error: setupError!)
          : StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: SizedBox.shrink());
                }
                final user = snap.data;
                if (user == null) return const SignInScreen();
                return _SignedIn(
                  key: ValueKey(user.uid),
                  uid: user.uid,
                  prefs: prefs,
                );
              },
            ),
    );
  }
}

/// Owns the per-user controllers and keeps the widget, reminders and
/// streak check in step with them.
class _SignedIn extends StatefulWidget {
  const _SignedIn({super.key, required this.uid, required this.prefs});

  final String uid;
  final SharedPreferences prefs;

  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> with WidgetsBindingObserver {
  late final repo = Repo(widget.uid);
  late final timer = TimerController(widget.prefs);
  late final app = AppController(repo)..activeSession = _activeOf(timer);
  StreamSubscription<Uri?>? _clicks;
  StreamSubscription<String>? _taps;
  String? _reminderKey;
  String? _guardKey;

  static ({String taskId, String date})? _activeOf(TimerController t) {
    final s = t.session;
    return s == null ? null : (taskId: s.taskId, date: s.date);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.addListener(_sync);
    timer.addListener(_sync);
    WidgetSync.initialLaunch().then(_openFromWidget);
    _clicks = WidgetSync.clicks.listen(_openFromWidget);
    Notifications.scheduleMonthlyRecap();
    final launched = Notifications.launchPayload;
    Notifications.launchPayload = null;
    if (launched != null) _openFromNotification(launched);
    _taps = Notifications.taps.listen(_openFromNotification);
  }

  void _sync() {
    timer.applyProfile(app.profile);
    app.activeSession = _activeOf(timer);
    if (!app.tasksLoaded || !app.profileLoaded) return;
    final p = app.profile;
    final guardKey =
        '${p.points}|${p.scrollReserve}|${p.scrollApps.map((a) => a.package).join(',')}';
    if (guardKey != _guardKey) {
      _guardKey = guardKey;
      _syncGuard();
    }
    WidgetSync.push(
      tasks: app.tasks,
      todayLogs: app.todayLogs,
      week: app.week,
      session: timer.session,
    );
    final due = app.dueToday;
    final left = due.where((t) {
      final l = app.todayLogs[t.id];
      return !(l?.completed ?? false) && !(l?.frozen ?? false);
    }).length;
    final key =
        '${app.today}|$left|${app.profile.reminderHour}|${app.tasks.length}';
    if (key != _reminderKey) {
      _reminderKey = key;
      Notifications.syncReminders(
        hour: app.profile.reminderHour,
        leftToday: due.isEmpty ? null : left,
        hasDueTasks: (day) => app.tasks.any((t) => t.isDueOn(dateKey(day))),
      );
    }
  }

  void _openFromWidget(Uri? uri) {
    if (uri == null || uri.host != 'timer') return;
    final id = uri.queryParameters['task'];
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav != null) pushPageWith(nav, app, timer, TimerScreen(taskId: id));
    });
  }

  /// 'recap:YYYY-MM' opens that month's recap.
  void _openFromNotification(String payload) {
    if (!payload.startsWith('recap:')) return;
    final month = payload.substring(6);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav != null) {
        pushPageWith(nav, app, timer, MonthlyRecapScreen(month: month));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      app.refresh();
      _syncGuard();
      _collectAway();
    }
  }

  /// Back from another app during a session: time in apps that never count
  /// comes off the clock, and says so.
  Future<void> _collectAway() async {
    final dropped = await timer.collectAway();
    if (dropped.isNotEmpty && mounted) {
      toast(context, '${awaySummary(dropped)}. Not counted.');
    }
  }

  /// Pays for time on limited apps since last time, and updates what the
  /// points buy.
  void _syncGuard() {
    if (!app.profileLoaded || !app.tasksLoaded) return;
    ScrollGuard.sync(repo: repo, profile: app.profile, tasks: app.tasks);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clicks?.cancel();
    _taps?.cancel();
    app.removeListener(_sync);
    timer.removeListener(_sync);
    app.dispose();
    timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: timer),
      ],
      child: const AgedPaper(child: HomeShell()),
    );
  }
}

class _SetupNeeded extends StatelessWidget {
  const _SetupNeeded({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Firebase isn’t set up yet',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Run `flutterfire configure` in the project folder, then restart the app. '
                'README.md has the full steps.',
              ),
              const SizedBox(height: 12),
              Text('$error', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
