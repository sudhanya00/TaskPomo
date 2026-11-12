import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/analytics.dart';
import '../models/models.dart';
import '../services/ai_recap.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../ui/charts.dart';
import '../util/dates.dart';

/// The year in review, as story pages: tap right for the next page, left for
/// the previous one. Paper pages alternate with ink pages.
class WrappedScreen extends StatefulWidget {
  const WrappedScreen({super.key, required this.year});

  final int year;

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

const _ink = Color(0xFF1E1D1A);
const _paper = Color(0xFFF5F3EE);
const _inkMuted = Color(0xFFA39E93);

class _WrappedScreenState extends State<WrappedScreen> {
  late final AppController _app = context.read<AppController>();
  late final DateRange _range = DateRange.year(widget.year);
  late final Stream<List<DayLog>> _days = _app.repo.daysSince(_range.from);

  /// Before December the current year is a preview; its note is cached
  /// separately so the real Wrapped gets a fresh one.
  late final bool _preview =
      widget.year == DateTime.now().year && DateTime.now().month != 12;
  late final AiNote _note = AiNote(
    _app.repo.noteDoc(
      _preview ? 'wrapped_${widget.year}_preview' : 'wrapped_${widget.year}',
    ),
  );
  late final Stream<Map<String, dynamic>?> _cached = _note.cached();
  List<Session>? _sessions;
  int _page = 0;
  bool _writing = false;
  bool _tried = false;
  String? _error;
  static const _pages = 7;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _app.repo.sessionsSince(_range.from).then((s) {
      if (mounted) {
        setState(
          () => _sessions = s.where((x) => _range.contains(x.date)).toList(),
        );
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _write(Analytics a) async {
    if (_writing) return;
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      final tasks = a.tasks;
      await _note.write(
        wrappedPrompt(
          year: widget.year,
          totals: {
            'minutes': a.totalSec ~/ 60,
            'daysShowedUp': a.daysShowed,
            'sessions': a.sessions,
          },
          perTask: [
            for (var i = 0; i < tasks.length; i++)
              if (a.taskTotals[i] > 0)
                {
                  'task': tasks[i].name,
                  'minutes': a.taskTotals[i] ~/ 60,
                  'bestRunDays': a.bestRun[i],
                  'dueDaysDone': '${(a.completion[i] * 100).round()}%',
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

  void _tap(TapUpDetails d, double width) {
    final next = d.localPosition.dx > width / 3;
    setState(() => _page = (_page + (next ? 1 : -1)).clamp(0, _pages - 1));
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return StreamBuilder<List<DayLog>>(
      stream: _days,
      builder: (context, snap) {
        final days = (snap.data ?? const <DayLog>[])
            .where((d) => _range.contains(d.date))
            .toList();
        final a = analyze(
          tasks: app.tasks,
          days: days,
          sessions: _sessions ?? const [],
          range: _range,
          today: app.today,
        );
        final dark = _page.isEven;
        return Scaffold(
          backgroundColor: dark ? _ink : _paper,
          body: LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d, c.maxWidth),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(26, 14, 26, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < _pages; i++)
                            Expanded(
                              child: Container(
                                height: 2,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: i <= _page
                                      ? (dark ? _paper : _ink)
                                      : (dark ? _paper : _ink).withValues(
                                          alpha: .15,
                                        ),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          child: KeyedSubtree(
                            key: ValueKey(_page),
                            child: _pageFor(_page, a, app.today),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pageFor(int page, Analytics a, String today) {
    final ink = page.isEven ? _paper : _ink;
    final muted = page.isEven ? _inkMuted : const Color(0xFF8B867C);
    Text eyebrow(String s) => Text(s.toUpperCase(), style: Typo.eyebrow(muted));
    Text big(String s) =>
        Text(s, style: Typo.serif(104, color: ink).copyWith(height: .9));
    Text line(String s, {bool italic = false}) => Text(
      s,
      style: Typo.serif(32, color: italic ? muted : ink, italic: italic),
    );
    final preview = _preview;

    switch (page) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow(
              preview ? 'TaskPomo · Wrapped · so far' : 'TaskPomo · Wrapped',
            ),
            const Spacer(),
            big('${widget.year}'),
            line('in the ledger.', italic: true),
            const SizedBox(height: 22),
            Text('Tap to begin', style: Typo.sans(13, color: muted)),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow('You showed up'),
            const SizedBox(height: 30),
            big('${a.daysShowed}'),
            line(a.daysShowed == 1 ? 'day this year.' : 'days this year.'),
            const Spacer(),
            IgnorePointer(
              child: Chart(
                height: 78,
                hint: null,
                build: yearSquares(widget.year, a.perDay, today),
              ),
            ),
          ],
        );
      case 2:
        final hours = a.totalSec / 3600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow('In total'),
            const SizedBox(height: 30),
            big(
              hours >= 10
                  ? NumberFormat.decimalPattern().format(hours.round())
                  : hours.toStringAsFixed(1),
            ),
            line(hours.round() == 1 ? 'hour.' : 'hours.'),
            const Spacer(),
            Text(
              hours >= 24
                  ? 'That’s ${(hours / 24).toStringAsFixed(1)} full days, or about ${(hours / 2).round()} feature films back to back.'
                  : 'About ${(hours / 2).round() < 1 ? 'one' : (hours / 2).round()} feature film${(hours / 2).round() > 1 ? 's' : ''} back to back, a few minutes at a time.',
              style: Typo.sans(15, color: muted, height: 1.5),
            ),
          ],
        );
      case 3:
        final order = [for (var i = 0; i < a.tasks.length; i++) i]
          ..sort((x, y) => a.taskTotals[y].compareTo(a.taskTotals[x]));
        final top = order.isEmpty ? null : order.first;
        final most = top == null ? 1 : math.max(1, a.taskTotals[top]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow('Most of it went to'),
            const SizedBox(height: 26),
            Text(
              top == null ? '—' : a.tasks[top].name,
              style: Typo.serif(58, color: ink).copyWith(height: 1),
            ),
            if (top != null)
              Text(hm(a.taskTotals[top]), style: Typo.mono(13, color: muted)),
            const Spacer(),
            for (final i in order)
              if (a.taskTotals[i] > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          a.tasks[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Typo.sans(13, color: ink),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: math.max(.02, a.taskTotals[i] / most),
                            child: Container(
                              height: 9,
                              decoration: BoxDecoration(
                                color: Ledger.seriesFor(i),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          hm(a.taskTotals[i]),
                          textAlign: TextAlign.end,
                          style: Typo.mono(11, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        );
      case 4:
        final run = longestRun(a);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow('Your longest run'),
            const SizedBox(height: 30),
            big(run == null ? '0' : '${run.$2.length}'),
            if (run != null) ...[
              line('days of ${a.tasks[run.$1].name},'),
              line(
                '${_long(run.$2.start)} to ${_long(run.$2.end)}.',
                italic: true,
              ),
            ] else
              line('Next year, then.', italic: true),
            const Spacer(),
            Text(
              'Days a task wasn’t due never broke it; only a missed due day did.',
              style: Typo.sans(14, color: muted, height: 1.5),
            ),
          ],
        );
      case 5:
        final h = peakStartHour(a);
        final byHour = List.filled(24, 0);
        for (final row in a.focus) {
          for (var i = 0; i < 24; i++) {
            byHour[i] += row[i];
          }
        }
        final max = math.max(1, byHour.reduce(math.max));
        final label = h == 0
            ? '12 a.m.'
            : h < 12
            ? '$h a.m.'
            : h == 12
            ? '12 p.m.'
            : '${h - 12} p.m.';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow('When you work'),
            const SizedBox(height: 26),
            Text(
              'A $label\nperson.',
              style: Typo.serif(52, color: ink).copyWith(height: 1.02),
            ),
            const SizedBox(height: 8),
            Text(
              'Most sessions start between $h:00 and ${h + 2}:00.',
              style: Typo.sans(14, color: muted),
            ),
            const Spacer(),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 5; i < 24; i++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        height: math.max(1.5, 110 * byHour[i] / max),
                        color: i >= h && i <= h + 1 ? ink : Ledger.ramp[2],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final t in ['5', '12', '18', '23'])
                  Text(t, style: Typo.mono(10, color: muted)),
              ],
            ),
          ],
        );
      default:
        return StreamBuilder<Map<String, dynamic>?>(
          stream: _cached,
          builder: (context, n) {
            final note = n.data;
            if (n.connectionState == ConnectionState.active &&
                note == null &&
                !_tried &&
                _sessions != null &&
                a.totalSec > 0) {
              _tried = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => _write(a));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: eyebrow('In plain words')),
                    if (!_writing && a.totalSec > 0)
                      GestureDetector(
                        onTap: () => _write(a),
                        child: Text(
                          'Rewrite',
                          style: Typo.mono(11, color: muted),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 26),
                Text(
                  note?['line'] as String? ??
                      (_writing
                          ? 'Writing…'
                          : a.totalSec == 0
                          ? 'A quiet year in the ledger.'
                          : ''),
                  style: Typo.serif(30, color: ink).copyWith(height: 1.18),
                ),
                const SizedBox(height: 16),
                if (note?['sub'] != null)
                  Text(
                    '${note!['sub']}',
                    style: Typo.sans(15, color: muted, height: 1.5),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: Typo.sans(
                      13,
                      color: const Color(0xFFD07A55),
                      height: 1.4,
                    ),
                  ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: ink.withValues(alpha: .25)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      preview
                          ? 'Back to the ledger'
                          : 'See you in ${widget.year + 1}',
                      style: Typo.sans(15, weight: 500, color: ink),
                    ),
                  ),
                ),
              ],
            );
          },
        );
    }
  }

  String _long(String key) => DateFormat('d MMMM').format(parseKey(key));
}
