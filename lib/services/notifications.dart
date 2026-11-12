import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Android notifications: a live session timer in the shade, pomodoro and
/// break bells, and an evening nudge when tasks are left. No-ops elsewhere.
class Notifications {
  Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _sessionId = 1;
  static const _bellId = 2;
  static const _reminderBase = 100; // +0..6 for the next 7 days

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> init() async {
    if (!_supported || _ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_mark'),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) _taps.add(r.payload!);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      launchPayload = launch!.notificationResponse?.payload;
    }
    _ready = true;
  }

  static final _taps = StreamController<String>.broadcast();

  /// Payloads of notifications tapped while the app is running.
  static Stream<String> get taps => _taps.stream;

  /// Payload of the notification that opened the app, if one did.
  static String? launchPayload;

  static const _monthlyId = 300;

  static const _monthlyDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'recap',
      'Monthly recap',
      channelDescription: 'Your month in the ledger, on the 1st',
      importance: Importance.defaultImportance,
    ),
  );

  /// The 1st of next month, 9 am: last month's recap is ready. Never names
  /// a task. Payload 'recap:YYYY-MM' opens that month.
  static Future<void> scheduleMonthlyRecap() async {
    if (!_ready) return;
    final now = DateTime.now();
    final at = DateTime(now.year, now.month + 1, 1, 9);
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    await _plugin.cancel(id: _monthlyId);
    await _plugin.zonedSchedule(
      id: _monthlyId,
      title: 'Your month is in the ledger',
      body: 'A page for the month that just ended.',
      payload: 'recap:$month',
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _monthlyDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> requestPermission() async {
    if (!_ready) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static const _sessionChannel = AndroidNotificationDetails(
    'session',
    'Focus session',
    channelDescription: 'Shows the running timer',
    importance: Importance.low,
    priority: Priority.low,
  );

  static const _bellDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'bell',
      'Pomodoro bell',
      channelDescription: 'End of a pomodoro or a break',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminder',
      'Streak reminder',
      channelDescription: 'Evening nudge when tasks are left',
      importance: Importance.defaultImportance,
    ),
  );

  /// Ongoing notification. With [runningSince] it ticks on its own via the
  /// system chronometer, so nothing has to run in the background.
  static Future<void> showSession({
    required String title,
    required String body,
    DateTime? runningSince,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      id: _sessionId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _sessionChannel.channelId,
          _sessionChannel.channelName,
          channelDescription: _sessionChannel.channelDescription,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: runningSince != null,
          visibility: NotificationVisibility.private,
          usesChronometer: runningSince != null,
          when: runningSince?.millisecondsSinceEpoch,
        ),
      ),
    );
  }

  static Future<void> scheduleBell(
    DateTime at,
    String title,
    String body,
  ) async {
    if (!_ready) return;
    await _plugin.cancel(id: _bellId);
    if (!at.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id: _bellId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: _bellDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Cancels everything shown or scheduled.
  static Future<void> cancelAll() async {
    if (!_supported) return;
    await _plugin.cancelAll();
  }

  static Future<void> cancelBell() async {
    if (_ready) await _plugin.cancel(id: _bellId);
  }

  static Future<void> clearSession() async {
    if (!_ready) return;
    await _plugin.cancel(id: _sessionId);
    await _plugin.cancel(id: _bellId);
  }

  /// Schedules the evening nudge for the next 7 days, skipping today if
  /// everything is already done. [leftToday] is null when nothing is due.
  static Future<void> syncReminders({
    required int hour,
    required int? leftToday,
    required bool Function(DateTime day) hasDueTasks,
  }) async {
    if (!_ready) return;
    for (var i = 0; i < 7; i++) {
      await _plugin.cancel(id: _reminderBase + i);
    }
    if (hour < 0) return;
    final now = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final at = DateTime(now.year, now.month, now.day + i, hour);
      if (!at.isAfter(now) || !hasDueTasks(at)) continue;
      if (i == 0 && (leftToday ?? 0) == 0) continue;
      await _plugin.zonedSchedule(
        id: _reminderBase + i,
        title: i == 0 && leftToday == 1
            ? 'One left today'
            : 'Still some left today',
        body: 'A few minutes keeps the streak going.',
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: _reminderDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
