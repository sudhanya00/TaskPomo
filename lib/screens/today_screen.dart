import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/headline.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../state/timer_controller.dart';
import '../theme.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import 'nav.dart';
import 'task_editor_screen.dart';
import 'timer_screen.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final timer = context.watch<TimerController>();
    final l = Ledger.of(context);
    final session = timer.session;
    final head = headlineFor(
      tasks: app.tasks,
      todayLogs: app.todayLogs,
      today: app.today,
      now: DateTime.now(),
    );

    Widget row(Task t, {bool dimmed = false}) {
      final active = timer.isActiveFor(t.id);
      return TaskRow(
        task: t,
        log: app.todayLogs[t.id],
        liveSeconds: active && session!.date == app.today
            ? timer.focus.inSeconds
            : 0,
        running: active && session!.running,
        dimmed: dimmed,
        onTap: () => pushPage(context, TimerScreen(taskId: t.id)),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
          children: [
            Eyebrow(DateFormat('EEEE d MMMM').format(DateTime.now())),
            const SizedBox(height: 14),
            Text(head.line, style: Typo.serif(42, color: l.ink)),
            Text(
              head.aside,
              style: Typo.serif(42, color: l.muted, italic: true),
            ),
            const SizedBox(height: 26),
            if (!app.tasksLoaded)
              const SizedBox(height: 120)
            else if (app.tasks.isEmpty)
              _Empty()
            else ...[
              _TodayLine(
                app: app,
                liveSeconds: session != null && session.date == app.today
                    ? timer.focus.inSeconds
                    : 0,
              ),
              for (final t in app.dueToday) row(t),
              if (app.notToday.isNotEmpty) ...[
                const SizedBox(height: 30),
                const Eyebrow('Not today'),
                for (final t in app.notToday) row(t, dimmed: true),
              ],
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => pushPage(context, const TaskEditorScreen()),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Ic.plus, size: 16, color: l.muted),
                        const SizedBox(width: 8),
                        Text(
                          'New task',
                          style: Typo.sans(14.5, weight: 500, color: l.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Today's effort at a glance. Streaks belong to tasks and sit on each row;
/// this line is about the day: minutes put in and how the week is filling.
class _TodayLine extends StatelessWidget {
  const _TodayLine({required this.app, required this.liveSeconds});

  final AppController app;
  final int liveSeconds;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    final logged = app.todayLogs.values.fold<int>(0, (s, x) => s + x.seconds);
    final minutes = (logged + liveSeconds) ~/ 60;
    final due = app.dueToday;
    final settled = due.where((t) {
      final x = app.todayLogs[t.id];
      return (x?.completed ?? false) || (x?.frozen ?? false);
    }).length;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: l.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$minutes',
            style: Typo.serif(68, color: l.ink).copyWith(height: .82),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Minutes today'),
                const SizedBox(height: 6),
                Text(
                  due.isEmpty
                      ? 'Nothing due'
                      : '$settled of ${due.length} done',
                  maxLines: 2,
                  style: Typo.sans(12.5, color: l.muted, height: 1.35),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: WeekStrip(days: app.week),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Hairline(),
        const SizedBox(height: 20),
        Text(
          'Pick something you want to get better at and give it a few minutes a day. '
          'Small enough that skipping feels silly.',
          style: Typo.sans(15, color: l.muted, height: 1.55),
        ),
        const SizedBox(height: 24),
        LedgerButton(
          label: 'Add your first task',
          icon: Ic.plus,
          filled: true,
          onPressed: () => pushPage(context, const TaskEditorScreen()),
        ),
      ],
    );
  }
}
