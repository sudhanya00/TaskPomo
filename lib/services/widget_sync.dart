import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../logic/week.dart';
import '../models/models.dart';
import '../state/timer_controller.dart';
import '../util/dates.dart';

/// Pushes today's state to the Android homescreen widget
/// (PomoWidgetProvider.kt). The widget sits where anyone can see it, so the
/// payload carries no task names: only minutes, per-task streaks and the week.
class WidgetSync {
  WidgetSync._();

  static const _provider = 'PomoWidgetProvider';
  static String? _last;
  static String? _scheduledFor;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> push({
    required List<Task> tasks,
    required Map<String, DayLog> todayLogs,
    required List<DayCell> week,
    required ActiveSession? session,
  }) async {
    if (!_supported) return;
    final today = todayKey();
    final payload = jsonEncode({
      'date': today,
      'weekStart': weekStart(today),
      'week': [
        for (final d in week) {'k': d.kind.name, 'f': (d.fill * 100).round()},
      ],
      'tasks': [
        for (final t in tasks)
          {
            'id': t.id,
            'target': t.targetMinutes,
            'days': t.days.toList(),
            'created': t.createdDate,
            'doneSec': todayLogs[t.id]?.seconds ?? 0,
            'completed': todayLogs[t.id]?.completed ?? false,
            'frozen': todayLogs[t.id]?.frozen ?? false,
            'streak': t.currentStreak,
          },
      ],
      'session': session == null
          ? null
          : {
              'accumulatedMs': session.accumulatedMs,
              'runningSince': session.runningSince,
            },
    });
    if (payload == _last) return;
    _last = payload;
    try {
      await HomeWidget.saveWidgetData<String>('payload', payload);
      await HomeWidget.updateWidget(androidName: _provider);
      if (_scheduledFor != today) {
        // Redraw when the evening wording changes and at midnight.
        final now = DateTime.now();
        final times = [
          for (final h in [18, 21, 24])
            DateTime(now.year, now.month, now.day, h, 0, 5),
        ].where((t) => t.isAfter(now)).toList();
        await HomeWidget.scheduleWidgetUpdates(times, androidName: _provider);
        _scheduledFor = today;
      }
    } catch (e) {
      debugPrint('Widget update failed: $e');
    }
  }

  /// Empties the widget, e.g. after the account is deleted.
  static Future<void> clear() async {
    if (!_supported) return;
    _last = null;
    try {
      await HomeWidget.saveWidgetData<String>('payload', null);
      await HomeWidget.updateWidget(androidName: _provider);
    } catch (e) {
      debugPrint('Widget clear failed: $e');
    }
  }

  /// Uri the app was opened with from the widget, e.g. taskpomo://timer?task=ID.
  static Future<Uri?> initialLaunch() async =>
      _supported ? HomeWidget.initiallyLaunchedFromHomeWidget() : null;

  static Stream<Uri?> get clicks =>
      _supported ? HomeWidget.widgetClicked : const Stream.empty();
}
