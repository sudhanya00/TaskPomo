import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/analytics.dart';
import '../models/models.dart';
import '../services/ai_recap.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../ui/charts.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

/// The page for a finished month: totals against the month before, the
/// month as a calendar, a written note, and a per-task table.
class MonthlyRecapScreen extends StatefulWidget {
  const MonthlyRecapScreen({super.key, required this.month});

  /// 'YYYY-MM'.
  final String month;

  @override
  State<MonthlyRecapScreen> createState() => _MonthlyRecapScreenState();
}

class _MonthlyRecapScreenState extends State<MonthlyRecapScreen> {
  late final AppController _app = context.read<AppController>();
  late final DateRange _range = DateRange.month(widget.month);
  late final DateRange _prev = DateRange.month(previousMonth(widget.month));
  late final AiNote _note = AiNote(_app.repo.noteDoc('month_${widget.month}'));
  late final Stream<Map<String, dynamic>?> _cached = _note.cached();
  late final Stream<List<DayLog>> _days = _app.repo.daysSince(_prev.from);
  List<Session>? _sessions;
  bool _writing = false;
  bool _tried = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _app.repo.sessionsSince(_range.from).then((s) {
      if (mounted) {
        setState(
          () => _sessions = s.where((x) => _range.contains(x.date)).toList(),
        );
      }
    });
  }

  Future<void> _write(Analytics a, Analytics before) async {
    if (_writing) return;
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      final tasks = a.tasks;
      await _note.write(
        monthPrompt(
          monthLabel:
              '${monthName(widget.month)} ${widget.month.substring(0, 4)}',
          totals: {
            'minutes': a.totalSec ~/ 60,
            'daysShowedUp': a.daysShowed,
            'daysInMonth': _range.days,
            'minutesPreviousMonth': before.totalSec ~/ 60,
          },
          perTask: [
            for (var i = 0; i < tasks.length; i++)
              if (a.taskTotals[i] > 0)
                {
                  'task': tasks[i].name,
                  'minutes': a.taskTotals[i] ~/ 60,
                  'dueDaysDone': '${(a.completion[i] * 100).round()}%',
                  'bestRunDays': a.bestRun[i],
                  'minutesChange':
                      (a.taskTotals[i] - before.taskTotals[i]) ~/ 60,
                },
          ],
          sessions: _sessions ?? const [],
          names: {for (final t in tasks) t.id: t.name},
        ),
      );
    } catch (e) {
      _error = describeAiError(e);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l = Ledger.of(context);
    final tasks = app.tasks;

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<DayLog>>(
          stream: _days,
          builder: (context, snap) {
            final days = snap.data ?? const <DayLog>[];
            final a = analyze(
              tasks: tasks,
              days: days,
              sessions: _sessions ?? const [],
              range: _range,
              today: app.today,
            );
            final before = analyze(
              tasks: tasks,
              days: days,
              sessions: const [],
              range: _prev,
              today: app.today,
            );
            final run = longestRun(a);
            String delta(num v, {String unit = ''}) =>
                '${v >= 0 ? '+' : ''}$v$unit vs ${monthName(previousMonth(widget.month))}';
            final hoursDelta = num.parse(
              ((a.totalSec - before.totalSec) / 3600).toStringAsFixed(1),
            );

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 40),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Ic.back, color: l.ink, size: 22),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(
                        'Monthly recap · ${widget.month.substring(0, 4)}',
                      ),
                      const SizedBox(height: 10),
                      Text(
                        monthName(widget.month),
                        style: Typo.serif(60, color: l.ink),
                      ),
                      Text(
                        'in the ledger.',
                        style: Typo.serif(30, color: l.muted, italic: true),
                      ),
                      const SizedBox(height: 20),
                      StatTiles(
                        items: [
                          (
                            'Hours',
                            (a.totalSec / 3600).toStringAsFixed(1),
                            delta(hoursDelta),
                          ),
                          (
                            'Days showed up',
                            '${a.daysShowed} / ${_range.days}',
                            delta(a.daysShowed - before.daysShowed),
                          ),
                          (
                            'Best day',
                            a.bestDay == null ? '–' : shortDate(a.bestDay!),
                            a.bestDay == null ? '' : hm(a.bestDaySec),
                          ),
                          (
                            'Longest run',
                            run == null ? '–' : '${run.$2.length} d',
                            run == null ? '' : tasks[run.$1].name,
                          ),
                        ],
                      ),
                      ChartSection(
                        eyebrow: 'The month',
                        title: 'Day by day',
                        sub: 'Minutes per day, all tasks. Darker is more.',
                        child: Chart(
                          height: 210,
                          build: monthCalendar(
                            widget.month,
                            a.perDay,
                            app.today,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 30),
                        padding: const EdgeInsets.only(top: 18),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: l.line)),
                        ),
                        child: StreamBuilder<Map<String, dynamic>?>(
                          stream: _cached,
                          builder: (context, n) {
                            final note = n.data;
                            // Write it the first time the month is opened.
                            if (n.connectionState == ConnectionState.active &&
                                note == null &&
                                !_tried &&
                                _sessions != null &&
                                a.totalSec > 0) {
                              _tried = true;
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => _write(a, before),
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Eyebrow('In plain words'),
                                    ),
                                    if (_writing)
                                      SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: l.muted,
                                        ),
                                      )
                                    else if (a.totalSec > 0 &&
                                        _sessions != null)
                                      InkResponse(
                                        onTap: () => _write(a, before),
                                        radius: 20,
                                        child: Icon(
                                          Ic.refresh,
                                          size: 18,
                                          color: l.muted,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (note != null) ...[
                                  Text(
                                    '${note['headline'] ?? ''}',
                                    style: Typo.serif(
                                      26,
                                      color: l.ink,
                                    ).copyWith(height: 1.2),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '${note['body'] ?? ''}',
                                    style: Typo.sans(
                                      14.5,
                                      color: l.ink,
                                      height: 1.55,
                                    ),
                                  ),
                                ] else
                                  Text(
                                    a.totalSec == 0
                                        ? 'Nothing was logged this month.'
                                        : 'Writing…',
                                    style: Typo.sans(
                                      14.5,
                                      color: l.muted,
                                      height: 1.5,
                                    ),
                                  ),
                                if (_error != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _error!,
                                    style: Typo.sans(
                                      13,
                                      color: l.accent,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Eyebrow('By task'),
                      const SizedBox(height: 8),
                      _Row(
                        cells: const ['Task', 'Hours', 'Done', 'vs before'],
                        head: true,
                      ),
                      for (var i = 0; i < tasks.length; i++)
                        _Row(
                          color: Ledger.seriesFor(i),
                          cells: [
                            tasks[i].name,
                            (a.taskTotals[i] / 3600).toStringAsFixed(1),
                            '${(a.completion[i] * 100).round()}%',
                            () {
                              final d =
                                  (a.taskTotals[i] - before.taskTotals[i]) /
                                  3600;
                              return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)}';
                            }(),
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

class _Row extends StatelessWidget {
  const _Row({required this.cells, this.head = false, this.color});

  final List<String> cells;
  final bool head;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    final num = head ? Typo.eyebrow(l.muted) : Typo.mono(12.5, color: l.ink);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: l.line)),
      ),
      child: Row(
        children: [
          if (color != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              cells[0],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: head ? num : Typo.sans(14, color: l.ink),
            ),
          ),
          for (final c in cells.skip(1))
            SizedBox(
              width: 66,
              child: Text(c, textAlign: TextAlign.end, style: num),
            ),
        ],
      ),
    );
  }
}
