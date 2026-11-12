import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/streaks.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../util/dates.dart';
import 'nav.dart';
import 'task_editor_screen.dart';
import 'timer_screen.dart';

class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final task = app.taskById(taskId);
    final l = Ledger.of(context);
    if (task == null) return const Scaffold();

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<DayLog>>(
          stream: app.repo.taskDays(taskId),
          builder: (context, snap) {
            final logs = {
              for (final x in snap.data ?? const <DayLog>[]) x.date: x,
            };
            final today = app.today;
            int since(String from) =>
                logs.values
                    .where((x) => x.date.compareTo(from) >= 0)
                    .fold(0, (s, x) => s + x.seconds) ~/
                60;

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Ic.back, color: l.ink, size: 22),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () =>
                          pushPage(context, TaskEditorScreen(task: task)),
                      icon: Icon(Ic.edit, color: l.ink, size: 20),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      IconTile(taskIcon(task.icon), size: 44),
                      const SizedBox(height: 16),
                      Text(task.name, style: Typo.serif(46, color: l.ink)),
                      const SizedBox(height: 4),
                      Text(
                        '${describeDays(task.days)} · ${formatMinutes(task.targetMinutes)} a day',
                        style: Typo.mono(12, color: l.muted),
                      ),
                      const SizedBox(height: 26),
                      MetaRow([
                        ('Streak', '${task.currentStreak}'),
                        ('Clean', '${task.cleanStreak}'),
                        ('Best', '${task.bestStreak}'),
                      ], valueSize: 34),
                      if (task.lostStreak > 0 &&
                          task.lostOn != null &&
                          task.currentStreak < task.lostStreak) ...[
                        const SizedBox(height: 12),
                        Text(
                          'A ${task.lostStreak}-day streak ended on ${DateFormat('d MMMM').format(parseKey(task.lostOn!))}. '
                          'Auto-freeze, under Me, covers the odd missed day.',
                          style: Typo.sans(13, color: l.muted, height: 1.5),
                        ),
                      ],
                      const SizedBox(height: 30),
                      const Eyebrow('Last 17 weeks'),
                      const SizedBox(height: 14),
                      _History(task: task, logs: logs, today: today),
                      const SizedBox(height: 30),
                      MetaRow([
                        ('Week', formatMinutes(since(weekStart(today)))),
                        ('Month', formatMinutes(since(monthStart(today)))),
                        ('Year', formatMinutes(since(yearStart(today)))),
                      ], valueSize: 24),
                      const SizedBox(height: 14),
                      Text(
                        '${formatMinutes(task.totalSeconds ~/ 60)} in total since ${DateFormat('d MMMM y').format(parseKey(task.createdDate))}.',
                        style: Typo.mono(11.5, color: l.muted),
                      ),
                      _Notes(stream: app.repo.notes(taskId)),
                      const SizedBox(height: 30),
                      Row(
                        children: [
                          Expanded(
                            child: LedgerButton(
                              label: 'Log time',
                              onPressed: () => logManually(context, task),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LedgerButton(
                              label: 'Freeze days',
                              icon: Ic.freeze,
                              onPressed: () => showFreezeSheet(context, [task]),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The task's recent session notes, newest first. Hidden until there are any.
class _Notes extends StatelessWidget {
  const _Notes({required this.stream});

  final Stream<List<Session>> stream;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return StreamBuilder<List<Session>>(
      stream: stream,
      builder: (context, snap) {
        final notes = snap.data ?? const <Session>[];
        if (notes.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 30),
            const Eyebrow('Notes'),
            const SizedBox(height: 4),
            for (final n in notes)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: l.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${DateFormat('EEE d MMM').format(parseKey(n.date))} · ${formatMinutes(n.seconds ~/ 60)}',
                      style: Typo.mono(10.5, color: l.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      n.note,
                      style: Typo.sans(14.5, color: l.ink, height: 1.45),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 17 weeks by 7 days. Ink = done, faint ink = some time, outlined = due
/// and missed, rust outline = today.
class _History extends StatelessWidget {
  const _History({required this.task, required this.logs, required this.today});

  final Task task;
  final Map<String, DayLog> logs;
  final String today;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    const weeks = 17;
    final start = addDays(weekStart(today), -7 * (weeks - 1));
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 3.0;
        final cell = ((c.maxWidth - gap * (weeks - 1)) / weeks).clamp(
          6.0,
          16.0,
        );
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var w = 0; w < weeks; w++)
              Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    Builder(
                      builder: (_) {
                        final key = addDays(start, w * 7 + d);
                        final log = logs[key];
                        Color? fill;
                        Color? border;
                        if (key.compareTo(today) > 0 ||
                            key.compareTo(task.createdDate) < 0) {
                          // outside the task's life
                        } else if (log?.completed ?? false) {
                          fill = l.ink;
                        } else if (log?.frozen ?? false) {
                          border = l.muted;
                        } else if ((log?.seconds ?? 0) > 0) {
                          fill = l.ink.withValues(alpha: .25);
                        } else if (task.isDueOn(key)) {
                          border = l.line;
                        }
                        if (key == today) border = l.accent;
                        return Container(
                          width: cell,
                          height: cell,
                          margin: EdgeInsets.only(bottom: d == 6 ? 0 : gap),
                          decoration: BoxDecoration(
                            color: fill,
                            border: border != null
                                ? Border.all(
                                    color: border,
                                    width: key == today ? 1.4 : 1,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(cell * .25),
                          ),
                        );
                      },
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Pick upcoming due days to protect with points: one task from its page,
/// or every task at once from the Me tab.
Future<void> showFreezeSheet(BuildContext context, List<Task> tasks) {
  final app = context.read<AppController>();
  return showLedgerSheet<void>(
    context,
    title: tasks.length == 1 ? 'Freeze ${tasks.first.name}' : 'Going away',
    child: _FreezePicker(app: app, tasks: tasks),
  );
}

class _FreezePicker extends StatefulWidget {
  const _FreezePicker({required this.app, required this.tasks});

  final AppController app;
  final List<Task> tasks;

  @override
  State<_FreezePicker> createState() => _FreezePickerState();
}

class _FreezePickerState extends State<_FreezePicker> {
  final _picked = <String>{};

  /// Which tasks to freeze. With several, you choose: away from the piano
  /// for a week doesn't have to mean away from everything.
  late final Set<String> _tasks = {for (final t in widget.tasks) t.id};
  Map<String, DayLog>? _ahead;

  @override
  void initState() {
    super.initState();
    widget.app.repo.daysAfter(addDays(widget.app.today, -1)).then((logs) {
      if (mounted) {
        setState(
          () => _ahead = {
            for (final x in logs) DayLog.idFor(x.taskId, x.date): x,
          },
        );
      }
    });
  }

  List<Task> _freezable(String date) => widget.tasks.where((t) {
    if (!_tasks.contains(t.id) || !t.isDueOn(date)) return false;
    final log = date == widget.app.today
        ? widget.app.todayLogs[t.id]
        : _ahead?[DayLog.idFor(t.id, date)];
    return !(log?.completed ?? false) && !(log?.frozen ?? false);
  }).toList();

  int _costOn(String date) =>
      _freezable(date).fold(0, (s, t) => s + freezeCostFor(t.targetMinutes));

  Widget _box(bool on) {
    final l = Ledger.of(context);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: on ? l.ink : null,
        border: Border.all(color: on ? l.ink : l.muted),
        borderRadius: BorderRadius.circular(4),
      ),
      child: on ? Icon(Ic.check, size: 12, color: l.bg) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    final today = widget.app.today;
    final single = widget.tasks.length == 1;
    final days = [for (var i = 0; i < 21; i++) addDays(today, i)]
        .where((d) => _freezable(d).isNotEmpty)
        .toList();
    _picked.removeWhere((d) => !days.contains(d));
    final count = _picked.fold<int>(0, (s, d) => s + _freezable(d).length);
    final cost = _picked.fold<int>(0, (s, d) => s + _costOn(d));
    final points = widget.app.profile.points;

    String intro;
    if (single) {
      final t = widget.tasks.single;
      intro =
          'A frozen day keeps ${t.name}’s streak alive. Each costs ${freezeCostFor(t.targetMinutes)} points, '
          'about ${freezeDays(t.targetMinutes).toStringAsFixed(1)} days of what it earns. You have $points.';
    } else {
      intro =
          'Pick the tasks to pause, then the days. Each task costs a few days of its own points. You have $points.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(intro, style: Typo.sans(14, color: l.muted, height: 1.5)),
        if (!single) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in widget.tasks)
                InkWell(
                  onTap: () => setState(
                    () => _tasks.contains(t.id)
                        ? _tasks.remove(t.id)
                        : _tasks.add(t.id),
                  ),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _tasks.contains(t.id) ? l.ink : null,
                      border: Border.all(
                        color: _tasks.contains(t.id) ? l.ink : l.line,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${t.name} · ${freezeCostFor(t.targetMinutes)}',
                      style: Typo.mono(
                        12,
                        color: _tasks.contains(t.id) ? l.bg : l.ink,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .38,
          ),
          child: _ahead == null
              ? const SizedBox(height: 80)
              : days.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Nothing left to freeze in the next three weeks.',
                    style: Typo.sans(14, color: l.muted),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in days)
                      InkWell(
                        onTap: () => setState(
                          () => _picked.contains(d)
                              ? _picked.remove(d)
                              : _picked.add(d),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: l.line)),
                          ),
                          child: Row(
                            children: [
                              _box(_picked.contains(d)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  d == today
                                      ? 'Today'
                                      : DateFormat('EEEE d MMMM')
                                            .format(parseKey(d)),
                                  style: Typo.sans(
                                    15,
                                    weight: 500,
                                    color: l.ink,
                                  ),
                                ),
                              ),
                              Text(
                                single
                                    ? '${_costOn(d)}'
                                    : '${_freezable(d).length} · ${_costOn(d)}',
                                style: Typo.mono(11.5, color: l.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 18),
        LedgerButton(
          label: count == 0
              ? 'Pick days'
              : cost > points
              ? 'Needs $cost points'
              : 'Freeze ${single ? '$count ${count == 1 ? 'day' : 'days'}' : '$count task-days'} for $cost',
          filled: true,
          onPressed: count == 0 || cost > points
              ? null
              : () {
                  widget.app.repo.freeze(
                    {
                      for (final t in widget.tasks)
                        t: [
                          for (final d in _picked)
                            if (_freezable(d).contains(t)) d,
                        ],
                    }..removeWhere((_, v) => v.isEmpty),
                  );
                  Navigator.pop(context);
                },
        ),
      ],
    );
  }
}
