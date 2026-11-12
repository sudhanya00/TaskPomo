import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/session_check.dart';
import '../logic/streaks.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../state/timer_controller.dart';
import '../theme.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../util/dates.dart';
import 'nav.dart';
import 'session_check_sheet.dart';
import 'streak_screen.dart';
import 'task_detail_screen.dart';
import 'task_editor_screen.dart';

/// Starts a session for [task], asking first if another one is running.
Future<void> startFocus(BuildContext context, Task task) async {
  final timer = context.read<TimerController>();
  final current = timer.session;
  if (current != null && current.taskId != task.id) {
    final ok = await confirm(
      context,
      title: 'Switch task?',
      body:
          '${current.taskName} is running. The time so far will be logged first.',
      yes: 'Log and switch',
    );
    if (!ok || !context.mounted) return;
    await stopAndLog(context);
    if (!context.mounted) return;
  }
  if (!timer.isActiveFor(task.id)) timer.start(task);
}

/// Stops the running session and credits the time.
Future<void> stopAndLog(BuildContext context) async {
  final timer = context.read<TimerController>();
  final app = context.read<AppController>();
  final running = timer.session;
  if (running == null) return;
  // Settle time spent in other apps before the minutes are final.
  await timer.collectAway();
  if (!context.mounted) return;
  final runningTask = app.taskById(running.taskId);
  if (runningTask != null &&
      !await askCountThisTime(context, timer, runningTask)) {
    return;
  }
  if (!context.mounted) return;
  final done = timer.stop();
  if (done == null) return;
  var seconds = done.seconds;
  if (seconds < 30) {
    toast(context, 'Under 30 seconds, not logged');
    return;
  }
  if (seconds > 3 * 3600) {
    final edited = await askMinutes(
      context,
      title: 'That was ${formatMinutes(seconds ~/ 60)}',
      message: 'Forgot to stop the timer? Correct the minutes.',
      initial: seconds ~/ 60,
    );
    if (edited == null || edited <= 0 || !context.mounted) return;
    seconds = edited * 60;
  }
  final task = app.taskById(done.taskId);
  if (task == null) return;
  final result = await app.logTime(
    task,
    done.date,
    seconds,
    startedAt: done.startedAt,
    notCountedSeconds: done.notCountedSeconds,
  );
  if (!context.mounted) return;
  await afterLog(
    context,
    task,
    seconds,
    result.outcome,
    result.sessionId,
    notCounted: done.notCounted,
  );
}

Future<int?> askMinutes(
  BuildContext context, {
  required String title,
  String? message,
  int? initial,
}) {
  final controller = TextEditingController(text: initial?.toString() ?? '');
  return showLedgerSheet<int>(
    context,
    title: title,
    child: Builder(
      builder: (ctx) {
        final l = Ledger.of(ctx);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message != null) ...[
              Text(
                message,
                style: Typo.sans(14.5, color: l.muted, height: 1.5),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: Typo.serif(40, color: l.ink),
              decoration: InputDecoration(
                suffixText: 'minutes',
                suffixStyle: Typo.mono(12, color: l.muted),
              ),
            ),
            const SizedBox(height: 22),
            LedgerButton(
              label: 'Save',
              filled: true,
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(controller.text)),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> logManually(BuildContext context, Task task) async {
  final app = context.read<AppController>();
  final mins = await askMinutes(
    context,
    title: 'Log time',
    message: 'Minutes spent on ${task.name} today, without the timer.',
  );
  if (mins == null || mins <= 0 || !context.mounted) return;
  final result = await app.logTime(
    task,
    app.today,
    mins * 60,
    startedAt: DateTime.now().millisecondsSinceEpoch,
    manual: true,
  );
  if (!context.mounted) return;
  await afterLog(context, task, mins * 60, result.outcome, result.sessionId);
}

/// Shown once time is logged: the streak news if the day was completed, and
/// an optional note on what was actually done. The note gives the weekly
/// recap something real to go on instead of guessing from the task name.
Future<void> afterLog(
  BuildContext context,
  Task task,
  int seconds,
  CompletionOutcome? o,
  String sessionId, {
  List<AwayApp> notCounted = const [],
}) async {
  final app = context.read<AppController>();
  final repo = app.repo;
  // A completed day gets the full streak moment (with its own note field).
  if (o != null) {
    await showStreakMoment(
      context,
      task: task,
      outcome: o,
      sessionId: sessionId,
      repo: repo,
      weekLogs: app.weekLogs,
      notCounted: notCounted,
    );
    return;
  }
  final note = TextEditingController();
  await showLedgerSheet<void>(
    context,
    title: o != null
        ? '${task.name}, done for today.'
        : 'Logged ${formatMinutes(seconds ~/ 60)}.',
    child: Builder(
      builder: (ctx) {
        final l = Ledger.of(ctx);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (o != null) ...[
              Text(
                o.bonus > 0
                    ? '${o.streak.clean} days in a row without a freeze. That earns a bonus.'
                    : o.streak.current == 1
                    ? 'Day one. The streak starts here.'
                    : 'Day ${o.streak.current}. Keep it going tomorrow.',
                style: Typo.sans(14.5, color: l.muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              MetaRow([
                ('Streak', '${o.streak.current}'),
                ('Points', '+${o.points}'),
                if (o.bonus > 0) ('Bonus', '+${o.bonus}'),
              ]),
              const SizedBox(height: 24),
            ],
            if (notCounted.isNotEmpty) ...[
              Text(
                'Not counted: ${awaySummary(notCounted)}.',
                style: Typo.sans(14, color: l.muted, height: 1.5),
              ),
              const SizedBox(height: 18),
            ],
            const Eyebrow('Note, optional'),
            TextField(
              controller: note,
              minLines: 1,
              maxLines: 4,
              maxLength: 280,
              textCapitalization: TextCapitalization.sentences,
              style: Typo.sans(16, color: l.ink, height: 1.4),
              decoration: InputDecoration(
                hintText: 'What did you do? Chapter 4, scales in G, squats…',
                counterText: '',
              ),
            ),
            const SizedBox(height: 22),
            LedgerButton(
              label: 'Done',
              filled: true,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
    ),
  );
  // Closing the sheet any way keeps whatever was typed.
  if (note.text.trim().isNotEmpty) repo.setNote(sessionId, note.text);
  note.dispose();
}

class TimerScreen extends StatelessWidget {
  const TimerScreen({super.key, required this.taskId});

  final String taskId;

  void _menu(BuildContext context, Task task) {
    showLedgerSheet<void>(
      context,
      title: task.name,
      child: Builder(
        builder: (ctx) {
          final l = Ledger.of(ctx);
          Widget item(IconData icon, String label, VoidCallback onTap) =>
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  onTap();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: l.line)),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 19, color: l.ink),
                      const SizedBox(width: 14),
                      Text(
                        label,
                        style: Typo.sans(15.5, weight: 500, color: l.ink),
                      ),
                    ],
                  ),
                ),
              );
          return Column(
            children: [
              item(
                Ic.insights,
                'History and streaks',
                () => pushPage(context, TaskDetailScreen(taskId: task.id)),
              ),
              item(
                Ic.plus,
                'Log time manually',
                () => logManually(context, task),
              ),
              item(
                Ic.edit,
                'Edit task',
                () => pushPage(context, TaskEditorScreen(task: task)),
              ),
              item(
                Ic.freeze,
                'Freeze this task',
                () => showFreezeSheet(context, [task]),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final timer = context.watch<TimerController>();
    final task = app.taskById(taskId);
    final l = Ledger.of(context);
    if (task == null) return const Scaffold();

    final s = timer.isActiveFor(taskId) ? timer.session : null;
    final log = app.todayLogs[taskId];
    final live = s != null && s.date == app.today ? timer.focus.inSeconds : 0;
    final todayMin = ((log?.seconds ?? 0) + live) ~/ 60;
    final reached = todayMin >= task.targetMinutes;
    final round = task.targetMinutes < timer.focusMinutes
        ? task.targetMinutes
        : timer.focusMinutes;

    String big, caption;
    double progress;
    if (s == null) {
      big = formatClock(Duration(minutes: round));
      caption = 'Ready';
      progress = 0;
    } else if (s.onBreak) {
      big = formatClock(timer.breakLeft);
      caption = timer.breakLeft == Duration.zero ? 'Break over' : 'Break';
      progress = timer.breakProgress;
    } else {
      big = formatClock(timer.pomodoroLeft);
      caption = s.running ? 'Left in this round' : 'Paused';
      progress = timer.pomodoroProgress;
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Ic.back, color: l.ink, size: 22),
                  ),
                  Expanded(
                    child: Center(
                      child: Eyebrow(
                        s == null
                            ? task.name
                            : '${task.name} · Round ${timer.pomodorosDone + 1}',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _menu(context, task),
                    icon: Icon(Ic.more, color: l.ink, size: 22),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      TickDial(
                        progress: progress,
                        quiet: s?.onBreak ?? false,
                        size: 270,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              big,
                              style: Typo.serif(
                                76,
                                color: s?.onBreak ?? false ? l.muted : l.ink,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Eyebrow(caption),
                          ],
                        ),
                      ),
                      const Spacer(flex: 2),
                      MetaRow([
                        ('Today', '$todayMin / ${task.targetMinutes}'),
                        ('Streak', '${task.currentStreak}'),
                        (
                          'Session',
                          s == null ? '0:00' : formatClock(timer.focus),
                        ),
                      ]),
                      SizedBox(
                        height: 46,
                        child: Center(
                          child:
                              reached && !(log?.completed ?? false) && s != null
                              ? Text(
                                  'Goal reached. Finish whenever you like.',
                                  style: Typo.mono(11.5, color: l.accent),
                                )
                              : null,
                        ),
                      ),
                      if (timer.pomodoroDue && s != null)
                        _RoundPrompt(timer: timer),
                      const Spacer(),
                      if (s == null)
                        LedgerButton(
                          label: 'Start',
                          icon: Ic.play,
                          filled: true,
                          onPressed: () => startFocus(context, task),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: LedgerButton(
                                label: s.running
                                    ? 'Pause'
                                    : s.onBreak
                                    ? 'Back to focus'
                                    : 'Resume',
                                icon: s.running ? Ic.pause : Ic.play,
                                onPressed: s.running
                                    ? timer.pause
                                    : timer.resume,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: LedgerButton(
                                label: 'Finish and log',
                                icon: Ic.check,
                                filled: true,
                                // Finishing ends the session, so step back
                                // to Today to see it land.
                                onPressed: () async {
                                  await stopAndLog(context);
                                  if (context.mounted) Navigator.pop(context);
                                },
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundPrompt extends StatelessWidget {
  const _RoundPrompt({required this.timer});

  final TimerController timer;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    final n = timer.pomodorosDone;
    final long = n % 4 == 0;
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Round $n done.', style: Typo.serif(26, color: l.ink)),
          const SizedBox(height: 4),
          Text(
            long
                ? 'Four in a row. Take ${timer.longBreakMinutes} minutes?'
                : 'Stretch for ${timer.breakMinutes} minutes, or keep going.',
            style: Typo.sans(14, color: l.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LedgerButton(
                  label: 'Keep going',
                  height: 44,
                  onPressed: timer.keepGoing,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LedgerButton(
                  label: 'Take a break',
                  height: 44,
                  filled: true,
                  onPressed: timer.takeBreak,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
