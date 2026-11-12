import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/analytics.dart';
import '../logic/insights.dart';
import '../models/models.dart';
import '../services/ai_recap.dart';
import '../services/export.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../ui/charts.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../util/dates.dart';
import 'monthly_recap_screen.dart';
import 'nav.dart';
import 'wrapped_screen.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late final AppController _app = context.read<AppController>();
  late final AiRecap _ai = AiRecap(_app.repo.recapDoc);
  late final Stream<Recap?> _recap = _ai.cached();
  Span _span = Span.year;
  String? _from;
  Stream<List<DayLog>>? _days;
  Stream<List<Session>>? _sessions;
  bool _generating = false;
  String? _aiError;

  /// History starts at the earliest task, or the start of the year if that
  /// is earlier, so the year chart is always complete.
  String _earliest(String today) {
    final created = _app.tasks
        .map((t) => t.createdDate)
        .fold<String>(today, (m, d) => d.compareTo(m) < 0 ? d : m);
    final y = yearStart(today);
    return created.compareTo(y) < 0 ? created : y;
  }

  void _watch(String from) {
    if (from == _from) return;
    _from = from;
    _days = _app.repo.daysSince(from);
    _sessions = _app.repo.watchSessionsSince(from);
  }

  Future<void> _generate(Insights insights, String week) async {
    setState(() {
      _generating = true;
      _aiError = null;
    });
    try {
      final sessions = await _app.repo.sessionsSince(week);
      final notes = <String, List<Session>>{};
      for (final x in sessions) {
        (notes[x.taskId] ??= []).add(x);
      }
      await _ai.generate(insights, week, notes);
    } catch (e) {
      _aiError = describeAiError(e);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String _focusTitle(Analytics a) {
    final h = peakStartHour(a);
    if (h < 11) return 'A morning person, mostly';
    if (h < 17) return 'Most of it in the daytime';
    return 'An evening person, mostly';
  }

  void _allMonths(BuildContext context, List<String> months) {
    showLedgerSheet<void>(
      context,
      title: 'Monthly recaps',
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .55,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in months)
              _LinkRow('${monthName(m)} ${m.substring(0, 4)}', '', () {
                Navigator.pop(context);
                pushPage(context, MonthlyRecapScreen(month: m));
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final l = Ledger.of(context);
    final today = app.today;
    final earliest = _earliest(today);
    _watch(earliest);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<DayLog>>(
          stream: _days,
          builder: (context, daySnap) => StreamBuilder<List<Session>>(
            stream: _sessions,
            builder: (context, sesSnap) {
              final days = daySnap.data ?? const <DayLog>[];
              final sessions = sesSnap.data ?? const <Session>[];
              final tasks = app.tasks;
              // Ranges and recaps start from the first task, not the start
              // of the year.
              final firstTask = tasks
                  .map((t) => t.createdDate)
                  .fold<String>(today, (m, d) => d.compareTo(m) < 0 ? d : m);
              final range = rangeFor(_span, today, firstTask);
              final a = analyze(
                tasks: tasks,
                days: days,
                sessions: sessions,
                range: range,
                today: today,
              );
              final yearDays = <String, int>{};
              for (final d in days) {
                if (d.date.startsWith(today.substring(0, 4))) {
                  yearDays[d.date] = (yearDays[d.date] ?? 0) + d.seconds;
                }
              }
              final names = [for (final t in tasks) t.name];
              final colors = [
                for (var i = 0; i < tasks.length; i++) Ledger.seriesFor(i),
              ];
              final insights = computeInsights(tasks, days, today);
              final week = weekStart(today);
              final months = finishedMonths(firstTask, today);
              final y = int.parse(today.substring(0, 4));
              final firstYear = int.parse(firstTask.substring(0, 4));
              final december = DateTime.now().month == 12;

              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
                children: [
                  const Eyebrow('Insights'),
                  const SizedBox(height: 14),
                  _SpanPicker(
                    value: _span,
                    onChanged: (v) => setState(() => _span = v),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    a.totalSec >= 7200
                        ? '${NumberFormat.decimalPattern().format(a.totalSec ~/ 3600)} hours'
                        : hm(a.totalSec),
                    style: Typo.serif(56, color: l.ink),
                  ),
                  Text(switch (_span) {
                    Span.week => 'this week.',
                    Span.month => 'in ${monthName(today.substring(0, 7))}.',
                    Span.year => 'in $y so far.',
                    Span.all =>
                      'since ${shortDate(range.from)} ${range.from.substring(0, 4)}.',
                  }, style: Typo.serif(26, color: l.muted, italic: true)),
                  const SizedBox(height: 18),
                  StatTiles(
                    items: [
                      ('Days showed up', '${a.daysShowed}', 'of ${range.days}'),
                      ('Sessions', '${a.sessions}', 'timer and manual'),
                      (
                        'Median session',
                        a.sessions == 0 ? '–' : '${a.medianSessionMin.round()}',
                        'minutes',
                      ),
                      (
                        'Best day',
                        a.bestDay == null ? '–' : shortDate(a.bestDay!),
                        a.bestDay == null ? '' : hm(a.bestDaySec),
                      ),
                    ],
                  ),
                  if (months.isNotEmpty || december || y > firstYear) ...[
                    const SizedBox(height: 28),
                    const Eyebrow('Recaps'),
                    const SizedBox(height: 4),
                    if (december)
                      _LinkRow(
                        'Wrapped $y',
                        'your year',
                        () => pushPage(context, WrappedScreen(year: y)),
                      ),
                    for (var py = y - 1; py >= firstYear; py--)
                      _LinkRow(
                        'Wrapped $py',
                        'the whole year',
                        () => pushPage(context, WrappedScreen(year: py)),
                      ),
                    for (final m in months.take(3))
                      _LinkRow(
                        '${monthName(m)} ${m.substring(0, 4)}',
                        'monthly recap',
                        () => pushPage(context, MonthlyRecapScreen(month: m)),
                      ),
                    if (months.length > 3)
                      _LinkRow(
                        'All months',
                        '${months.length} recaps',
                        () => _allMonths(context, months),
                      ),
                  ],
                  ChartSection(
                    eyebrow: 'Every day of $y',
                    title: 'The year in squares',
                    sub: 'Minutes per day, all tasks. Darker is more.',
                    child: Chart(
                      height: 78,
                      build: yearSquares(y, yearDays, today),
                    ),
                  ),
                  if (a.totalSec == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Text(
                        'Nothing logged in this range yet. The charts fill in as you go.',
                        style: Typo.sans(14, color: l.muted, height: 1.5),
                      ),
                    )
                  else ...[
                    ChartSection(
                      eyebrow: range.days <= 31
                          ? 'By day'
                          : range.days <= 26 * 7
                          ? 'By week'
                          : 'By month',
                      title: 'Where the time went',
                      sub: 'Hours, by task.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Chart(
                            height: 170,
                            build: stackedBars(a.buckets, names, colors),
                          ),
                          const SizedBox(height: 12),
                          ChartLegend(names: names, colors: colors),
                        ],
                      ),
                    ),
                    ChartSection(
                      eyebrow: 'When you focus',
                      title: _focusTitle(a),
                      sub: 'Minutes started, by weekday and hour. Darker is more.',
                      child: Chart(height: 190, build: focusGrid(a.focus)),
                    ),
                    ChartSection(
                      eyebrow: 'Session length',
                      title: 'How long you stay',
                      sub:
                          'Sessions in 5-minute bins. The line is your median.',
                      child: Chart(
                        height: 140,
                        build: lengthHistogram(
                          a.lengthBins,
                          a.medianSessionMin,
                        ),
                      ),
                    ),
                    ChartSection(
                      eyebrow: 'Target vs actual',
                      title: 'Who overdelivers',
                      sub: 'Average minutes on a due day against the target (dashed).',
                      child: Chart(
                        height: 30.0 * tasks.length + 18,
                        build: targetDots(names, a.targetRatio, a.avgDueMin, [
                          for (final t in tasks) t.targetMinutes,
                        ], a.dueDays),
                      ),
                    ),
                    ChartSection(
                      eyebrow: 'Streak history',
                      title: 'Runs, and the gaps',
                      sub: 'Each bar is an unbroken run; gaps are missed days.',
                      child: Chart(
                        height: 40.0 * tasks.length,
                        build: runsChart(range, names, colors, a.runs, [
                          for (var i = 0; i < tasks.length; i++)
                            a.dueDays[i] == 0
                                ? 'no finished due days yet'
                                : 'best ${a.bestRun[i]} d · ${(a.completion[i] * 100).round()}% of due days',
                        ]),
                      ),
                    ),
                    if (tasks.length >= 2)
                      ChartSection(
                        eyebrow: 'Habits together',
                        title: 'What travels with what',
                        sub: 'On days you finished the row, how often you also finished the column (%).',
                        child: Chart(
                          height: 66.0 + 38 * tasks.length,
                          build: heatGrid(
                            rows: names,
                            cols: names,
                            values: a.together,
                            numbers: true,
                            rotateCols: true,
                            leftWidth: 82,
                            topHeight: 64,
                            tip: (r, c, v) =>
                                'On ${names[r]} days, ${names[c]} done ${(v * 100).round()}%',
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 34),
                  StreamBuilder<Recap?>(
                    stream: _recap,
                    builder: (context, r) => _RecapBlock(
                      recap: r.data,
                      stale: r.data?.week != week,
                      busy: _generating,
                      error: _aiError,
                      canGenerate: insights.tasks.any((t) => t.weekSec > 0),
                      onGenerate: () => _generate(insights, week),
                    ),
                  ),
                  if (insights.tasks.isNotEmpty) ...[
                    const SizedBox(height: 34),
                    const Eyebrow('By task'),
                    const SizedBox(height: 6),
                    for (final s in insights.tasks) _TaskBlock(stats: s),
                  ],
                  const SizedBox(height: 30),
                  const Eyebrow('Your data'),
                  const SizedBox(height: 12),
                  LedgerButton(
                    label: 'Export as CSV',
                    icon: Ic.share,
                    onPressed: () => exportCsv(context, app.repo),
                  ),
                  if (!december) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextAction(
                        'Preview Wrapped (year so far)',
                        muted: true,
                        onPressed: () =>
                            pushPage(context, WrappedScreen(year: y)),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpanPicker extends StatelessWidget {
  const _SpanPicker({required this.value, required this.onChanged});

  final Span value;
  final ValueChanged<Span> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return Row(
      children: [
        for (final s in Span.values) ...[
          InkWell(
            onTap: () => onChanged(s),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: s == value ? l.ink : null,
                border: Border.all(color: s == value ? l.ink : l.line),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(switch (s) {
                Span.week => 'Week',
                Span.month => 'Month',
                Span.year => 'Year',
                Span.all => 'All',
              }, style: Typo.mono(12, color: s == value ? l.bg : l.ink)),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow(this.title, this.sub, this.onTap);

  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: l.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Typo.serif(24, color: l.ink)),
            ),
            if (sub.isNotEmpty) Text(sub, style: Typo.mono(11, color: l.muted)),
            const SizedBox(width: 8),
            Icon(Ic.chevron, size: 16, color: l.muted),
          ],
        ),
      ),
    );
  }
}

class _RecapBlock extends StatelessWidget {
  const _RecapBlock({
    required this.recap,
    required this.stale,
    required this.busy,
    required this.error,
    required this.canGenerate,
    required this.onGenerate,
  });

  final Recap? recap;
  final bool stale;
  final bool busy;
  final String? error;
  final bool canGenerate;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Eyebrow('This week, in plain words')),
            if (canGenerate)
              busy
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: l.muted,
                      ),
                    )
                  : InkResponse(
                      onTap: onGenerate,
                      radius: 20,
                      child: Icon(Ic.refresh, size: 18, color: l.muted),
                    ),
          ],
        ),
        const SizedBox(height: 14),
        if (recap == null)
          Text(
            canGenerate
                ? 'Tap the arrow for a short note on what your hours add up to.'
                : 'Log some time this week and this fills in.',
            style: Typo.sans(14.5, color: l.muted, height: 1.5),
          )
        else ...[
          Text(
            recap!.headline,
            style: Typo.serif(26, color: l.ink).copyWith(height: 1.2),
          ),
          for (final e in recap!.lines.entries) ...[
            const SizedBox(height: 14),
            Text(e.key.toUpperCase(), style: Typo.eyebrow(l.muted)),
            const SizedBox(height: 4),
            Text(e.value, style: Typo.sans(14.5, color: l.ink, height: 1.5)),
          ],
          if (stale) ...[
            const SizedBox(height: 12),
            Text('Written last week.', style: Typo.mono(11, color: l.muted)),
          ],
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: Typo.sans(13, color: l.accent, height: 1.4)),
        ],
      ],
    );
  }
}

class _TaskBlock extends StatelessWidget {
  const _TaskBlock({required this.stats});

  final TaskStats stats;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    final t = stats.task;
    final yearMin = stats.yearSec ~/ 60;
    final pct = stats.mastery * 100;
    final muted = Typo.mono(11.5, color: l.muted);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: l.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(taskIcon(t.icon), size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t.name,
                  style: Typo.sans(16, weight: 500, color: l.ink),
                ),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${t.currentStreak}',
                      style: Typo.serif(22, color: l.ink),
                    ),
                    TextSpan(
                      text: ' d',
                      style: Typo.mono(10, color: l.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            yearMin >= 600
                ? '${NumberFormat.decimalPattern().format(yearMin)} minutes this year'
                : '${formatMinutes(yearMin)} this year',
            style: Typo.serif(30, color: l.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'Week ${formatMinutes(stats.weekSec ~/ 60)} · Month ${formatMinutes(stats.monthSec ~/ 60)} · '
            'All ${formatMinutes(stats.allSec ~/ 60)}',
            style: muted,
          ),
          if (stats.dueDays30 > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Showed up ${stats.doneDays30} of ${stats.dueDays30} days lately',
              style: muted,
            ),
          ],
          if (stats.bestDay != null) ...[
            const SizedBox(height: 4),
            Text(
              'Best day ${formatMinutes(stats.bestDaySec ~/ 60)}, ${DateFormat('d MMM').format(parseKey(stats.bestDay!))}',
              style: muted,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkLine(
                  value: stats.mastery == 0
                      ? 0
                      : stats.mastery.clamp(.004, 1.0),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${pct < 1 ? pct.toStringAsFixed(2) : pct.toStringAsFixed(1)}% of 10,000 h',
                style: muted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
