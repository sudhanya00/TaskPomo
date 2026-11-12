import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../logic/scroll.dart';
import '../logic/session_check.dart';
import '../models/models.dart';
import '../util/dates.dart';

class InstalledApp {
  const InstalledApp(this.package, this.label);

  final String package;
  final String label;
}

class GuardState {
  const GuardState({
    this.enabled = false,
    this.unsyncedSeconds = 0,
    this.balanceSeconds = 0,
    this.graceAvailable = true,
    this.perApp = const {},
  });

  final bool enabled;
  final int unsyncedSeconds;
  final int balanceSeconds;
  final bool graceAvailable;
  final Map<String, int> perApp;
}

/// Bridge to the Android scroll guard (ScrollGuardService.kt). The service
/// does the counting and blocking on the phone; this side pays for what it
/// counted, in points, and tells it how much the points buy.
class ScrollGuard {
  ScrollGuard._();

  static const _ch = MethodChannel('taskpomo/guard');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isEnabled() async =>
      supported && (await _ch.invokeMethod<bool>('isEnabled') ?? false);

  static Future<void> openAccessibilitySettings() =>
      _ch.invokeMethod('openAccessibilitySettings');

  static Future<void> openAppInfo() => _ch.invokeMethod('openAppInfo');

  static List<InstalledApp>? _lastApps;

  /// The last list read, so the picker can open on it while a fresh read
  /// (which picks up newly installed apps) runs.
  static List<InstalledApp>? get lastApps => _lastApps;

  static Future<List<InstalledApp>> installedApps() async {
    if (!supported) return const [];
    final raw =
        await _ch.invokeListMethod<Map<Object?, Object?>>('installedApps') ??
        const [];
    return _lastApps = [
      for (final m in raw)
        InstalledApp(m['package'] as String, m['label'] as String),
    ];
  }

  static final _icons = <String, Future<Uint8List?>>{};
  static final _iconBytes = <String, Uint8List?>{};

  /// An app's icon as PNG, read once and kept for the session.
  static Future<Uint8List?> appIcon(String package) => _icons.putIfAbsent(
    package,
    () => _ch
        .invokeMethod<Uint8List>('appIcon', {'package': package})
        .catchError((_) => null)
        .then((b) => _iconBytes[package] = b),
  );

  /// The icon if it was already read, so a row scrolled back into view
  /// doesn't flash blank.
  static Uint8List? cachedIcon(String package) => _iconBytes[package];

  static Future<GuardState> state() async {
    if (!supported) return const GuardState();
    final m = await _ch.invokeMapMethod<String, Object?>('state') ?? const {};
    return GuardState(
      enabled: m['enabled'] as bool? ?? false,
      unsyncedSeconds: (m['unsyncedSeconds'] as num?)?.toInt() ?? 0,
      balanceSeconds: (m['balanceSeconds'] as num?)?.toInt() ?? 0,
      graceAvailable: m['graceAvailable'] as bool? ?? true,
      perApp: {
        for (final e in ((m['perApp'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num).toInt(),
      },
    );
  }

  /// Forgets limited apps, usage and allowance on the phone.
  static Future<void> reset() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('reset');
    } catch (e) {
      debugPrint('Scroll guard reset failed: $e');
    }
  }

  static bool? _sessionRunning;

  /// Tells the guard whether a focus session's timer is running, so it notes
  /// time in other apps.
  static Future<void> setSessionRunning(bool running) async {
    if (!supported || running == _sessionRunning) return;
    _sessionRunning = running;
    try {
      await _ch.invokeMethod('sessionRunning', {'running': running});
    } catch (_) {
      _sessionRunning = null;
    }
  }

  /// Time per app the guard noted during sessions since last asked.
  static Future<List<AwayApp>> takeSessionLog() async {
    if (!supported) return const [];
    try {
      final raw =
          await _ch.invokeListMethod<Map<Object?, Object?>>('takeSessionLog') ??
          const [];
      return [
        for (final m in raw)
          AwayApp(
            package: m['package'] as String,
            label: m['label'] as String,
            kind: appKindFrom(m['kind'] as String?),
            ms: (m['ms'] as num).toInt(),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static bool _syncing = false;

  /// Pays for counted time and refreshes what the points buy. Safe to call
  /// often; it does nothing while a sync is already running.
  static Future<void> sync({
    required Repo repo,
    required Profile profile,
    required List<Task> tasks,
  }) async {
    if (!supported || _syncing) return;
    _syncing = true;
    try {
      var points = profile.points;
      final reserve = profile.scrollReserve ?? defaultReserve(tasks);
      final s = await state();
      final minutes = s.unsyncedSeconds ~/ 60;
      if (minutes > 0) {
        final labels = {for (final a in profile.scrollApps) a.package: a.label};
        final detail = spendSummary({
          for (final e in s.perApp.entries) labels[e.key] ?? e.key: e.value,
        });
        repo.spendScroll(minutes, detail, todayKey());
        await _ch.invokeMethod('consume', {'seconds': minutes * 60});
        points -= minutes;
      }
      // What today's scrolling has cost so far, so the phone's timer
      // notification shows the same "used today" as the app. Skipped if the
      // ledger can't be read; the phone keeps its last figure.
      final today = todayKey();
      int? paid;
      try {
        paid = await repo
            .scrollMinutesOn(today)
            .first
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      await _ch.invokeMethod('configure', {
        'apps': [for (final a in profile.scrollApps) a.toMap()],
        'allowanceSeconds': allowanceSeconds(points, reserve),
        if (paid != null) ...{'paidDate': today, 'paidSeconds': paid * 60},
      });
    } catch (e) {
      debugPrint('Scroll guard sync failed: $e');
    } finally {
      _syncing = false;
    }
  }
}
