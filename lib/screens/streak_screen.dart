import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repo.dart';
import '../logic/session_check.dart';
import '../logic/headline.dart';
import '../logic/streaks.dart';
import '../models/models.dart';
import '../theme.dart';
import '../util/dates.dart';

/// Full-screen moment after a day is completed: the streak number turns
/// over, the dial moves toward the next bonus, today's square fills. On a
/// bonus milestone the page is ink and the dial sweeps round.
Future<void> showStreakMoment(
  BuildContext context, {
  required Task task,
  required CompletionOutcome outcome,
  required String sessionId,
  required Repo repo,
  required List<DayLog> weekLogs,
  List<AwayApp> notCounted = const [],
}) {
  HapticFeedback.lightImpact();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => StreakScreen(
        task: task,
        outcome: outcome,
        sessionId: sessionId,
        repo: repo,
        weekLogs: weekLogs,
        notCounted: notCounted,
      ),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

const _ink = Color(0xFF1E1D1A);
const _paper = Color(0xFFF5F3EE);
const _inkMuted = Color(0xFFA39E93);

class StreakScreen extends StatefulWidget {
  const StreakScreen({
    super.key,
    required this.task,
    required this.outcome,
    required this.sessionId,
    required this.repo,
    required this.weekLogs,
    this.notCounted = const [],
  });

  final Task task;
  final CompletionOutcome outcome;
  final String sessionId;
  final Repo repo;

  /// This week's logs (any task); this task's are picked out.
  final List<DayLog> weekLogs;

  /// Apps whose time was left out of this session.
  final List<AwayApp> notCounted;

  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  final _note = TextEditingController();
  bool _noting = false;
  bool _tapped = false;
  Timer? _second;

  bool get _milestone => widget.outcome.bonus > 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      // Haptic as the digits turn over; two on a milestone.
      if (!_tapped && _c.value >= .2) {
        _tapped = true;
        HapticFeedback.mediumImpact();
        if (_milestone) {
          _second = Timer(
            const Duration(milliseconds: 420),
            HapticFeedback.heavyImpact,
          );
        }
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _second?.cancel();
    _c.dispose();
    _note.dispose();
    super.dispose();
  }

  void _done() {
    if (_note.text.trim().isNotEmpty) {
      widget.repo.setNote(widget.sessionId, _note.text);
    }
    Navigator.of(context).pop();
  }

  Animation<double> _phase(
    double a,
    double b, [
    Curve curve = Curves.easeOutCubic,
  ]) => CurvedAnimation(
    parent: _c,
    curve: Interval(a, b, curve: curve),
  );

  @override
  Widget build(BuildContext context) {
    final o = widget.outcome, t = widget.task;
    final to = o.streak.current, from = to - 1, clean = o.streak.clean;
    final fg = _milestone ? _paper : _ink;
    final muted = _milestone ? _inkMuted : const Color(0xFF8B867C);
    final line = fg.withValues(alpha: .12);
    final next = nextMilestone(clean), prev = previousMilestone(clean - 1);
    final pFrom = ((clean - 1 - prev) / (next - prev)).clamp(0.0, 1.0);
    final pTo = _milestone
        ? 1.0
        : ((clean - prev) / (next - prev)).clamp(0.0, 1.0);
    final roll = _phase(.2, .55, Curves.easeOutBack);
    final dial = _phase(.2, _milestone ? .62 : .48);
    final flash = _phase(.62, .9);
    final fill = _phase(.38, .62);
    final details = _phase(.58, .8);
    final word = to == 1
        ? 'Day one'
        : '${t.name} · ${_milestone ? 'a clean ${numberWords(clean)}' : 'done for today'}';

    final eyebrow = Typo.eyebrow(muted);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _done();
      },
      child: Scaffold(
        backgroundColor: _milestone ? _ink : _paper,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(word.toUpperCase(), style: eyebrow),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 250,
                            child: AnimatedBuilder(
                              animation: _c,
                              builder: (context, _) => CustomPaint(
                                painter: _DialPainter(
                                  progress: pFrom + (pTo - pFrom) * dial.value,
                                  flash: _milestone
                                      ? math.sin(flash.value * math.pi)
                                      : 0,
                                  ink: fg,
                                  faint: line,
                                ),
                                child: Center(
                                  child: _Odometer(
                                    from: from,
                                    to: to,
                                    t: roll,
                                    color: fg,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            to == 1
                                ? 'The streak starts here.'
                                : _milestone
                                ? 'days, not one missed.'
                                : 'days in a row.',
                            textAlign: TextAlign.center,
                            style: Typo.serif(30, color: muted, italic: true),
                          ),
                          const SizedBox(height: 24),
                          AnimatedBuilder(
                            animation: fill,
                            builder: (context, _) => _Week(
                              task: t,
                              logs: widget.weekLogs,
                              fill: fill.value,
                              ink: fg,
                              muted: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: details,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Meta(
                        line: line,
                        eyebrow: eyebrow,
                        color: fg,
                        items: [
                          ('Points', '+${o.points}'),
                          if (_milestone)
                            ('Bonus', '+${o.bonus}')
                          else
                            (
                              'Next bonus',
                              'in ${next - clean} ${next - clean == 1 ? 'day' : 'days'}',
                            ),
                          if (_milestone)
                            ('Next', '$next days')
                          else
                            ('Best', '${o.streak.best}'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _milestone
                            ? '${capitalise(numberWords(clean))} clean days earns a bonus. The next one is at $next.'
                            : clean == to
                            ? 'Every day clean so far.'
                            : '$clean clean ${clean == 1 ? 'day' : 'days'} since the last freeze.',
                        textAlign: TextAlign.center,
                        style: Typo.sans(13, color: muted, height: 1.45),
                      ),
                      if (widget.notCounted.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Not counted: ${awaySummary(widget.notCounted)}',
                          textAlign: TextAlign.center,
                          style: Typo.mono(11.5, color: muted),
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (_noting)
                        TextField(
                          controller: _note,
                          autofocus: true,
                          minLines: 1,
                          maxLines: 3,
                          maxLength: 280,
                          textCapitalization: TextCapitalization.sentences,
                          cursorColor: fg,
                          style: Typo.sans(15.5, color: fg, height: 1.4),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText:
                                'What did you do? Chapter 4, scales in G…',
                            hintStyle: Typo.sans(15, color: muted),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: line),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: fg),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 52,
                        child: Material(
                          color: fg,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _done,
                            child: Center(
                              child: Text(
                                'Continue',
                                style: Typo.sans(
                                  15,
                                  weight: 500,
                                  color: _milestone ? _ink : _paper,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!_noting)
                        Center(
                          child: TextButton(
                            onPressed: () => setState(() => _noting = true),
                            child: Text(
                              'Add a note',
                              style: Typo.sans(14, color: muted),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Digits that change roll up and out while the new ones roll in with a
/// little overshoot. A new leading digit opens its own column as it arrives.
class _Odometer extends StatelessWidget {
  const _Odometer({
    required this.from,
    required this.to,
    required this.t,
    required this.color,
  });

  final int from, to;
  final Animation<double> t;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Typo.serif(120, color: color).copyWith(height: 1);
    final b = '$to', a = '$from'.padLeft(b.length);
    double width(String ch) {
      if (ch.trim().isEmpty) return 0;
      final tp = TextPainter(
        text: TextSpan(text: ch, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }

    const h = 124.0;
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = t.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < b.length; i++)
              if (a[i] == b[i])
                SizedBox(
                  height: h,
                  child: Center(child: Text(b[i], style: style)),
                )
              else
                ClipRect(
                  child: SizedBox(
                    height: h,
                    width:
                        width(a[i]) +
                        (width(b[i]) - width(a[i])) * v.clamp(0.0, 1.0),
                    child: OverflowBox(
                      maxWidth: double.infinity,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.translate(
                            offset: Offset(0, -h * v.clamp(0.0, 1.2)),
                            child: Opacity(
                              opacity: (1 - v).clamp(0.0, 1.0),
                              child: Text(a[i], style: style),
                            ),
                          ),
                          Transform.translate(
                            offset: Offset(0, h * (1 - v)),
                            child: Text(b[i], style: style),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// 60 ticks; filled up to [progress] toward the next bonus, with a rust dot
/// at the edge. [flash] (0..1) washes the ticks rust on a milestone.
class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.progress,
    required this.flash,
    required this.ink,
    required this.faint,
  });

  final double progress, flash;
  final Color ink, faint;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 60;
    final c = size.center(Offset.zero), r = size.width / 2 - 6;
    final lit = Color.lerp(ink, Ledger.paper.accent, flash)!;
    final p = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2 - math.pi / 2, long = i % 5 == 0;
      p
        ..color = i < (progress * n).round() ? lit : faint
        ..strokeWidth = long ? 2 : 1.2;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - (long ? 16 : 9)), c + dir * r, p);
    }
    final a = progress * math.pi * 2 - math.pi / 2;
    canvas.drawCircle(
      c + Offset(math.cos(a), math.sin(a)) * r,
      4.5,
      Paint()..color = Ledger.paper.accent,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress || old.flash != flash;
}

/// This task's Monday-to-Sunday: done (filled), frozen (dashed), missed
/// (outline), not due (faint). Today fills in rust.
class _Week extends StatelessWidget {
  const _Week({
    required this.task,
    required this.logs,
    required this.fill,
    required this.ink,
    required this.muted,
  });

  final Task task;
  final List<DayLog> logs;
  final double fill;
  final Color ink, muted;

  @override
  Widget build(BuildContext context) {
    final today = todayKey(), start = weekStart(today);
    final mine = {
      for (final l in logs.where((l) => l.taskId == task.id)) l.date: l,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 7; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
            child: Column(
              children: [
                CustomPaint(
                  size: const Size.square(14),
                  painter: _Square(
                    date: addDays(start, i),
                    today: today,
                    task: task,
                    log: mine[addDays(start, i)],
                    fill: fill,
                    ink: ink,
                    muted: muted,
                  ),
                ),
                const SizedBox(height: 6),
                Text('MTWTFSS'[i], style: Typo.mono(9, color: muted)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Square extends CustomPainter {
  _Square({
    required this.date,
    required this.today,
    required this.task,
    required this.log,
    required this.fill,
    required this.ink,
    required this.muted,
  });

  final String date, today;
  final Task task;
  final DayLog? log;
  final double fill;
  final Color ink, muted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(
      rect.deflate(.5),
      const Radius.circular(4),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (date == today) {
      final rust = Ledger.paper.accent;
      canvas.save();
      canvas.clipRRect(rr);
      canvas.drawRect(
        Rect.fromLTRB(0, size.height * (1 - fill), size.width, size.height),
        Paint()..color = rust,
      );
      canvas.restore();
      canvas.drawRRect(
        rr,
        stroke
          ..color = rust
          ..strokeWidth = 1.5,
      );
    } else if (date.compareTo(today) > 0 || !task.isDueOn(date)) {
      canvas.drawRRect(rr, stroke..color = muted.withValues(alpha: .35));
    } else if (log?.completed ?? false) {
      canvas.drawRRect(rr, Paint()..color = ink);
    } else if (log?.frozen ?? false) {
      // Dashed outline: kept by a freeze.
      final path = Path()..addRRect(rr);
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 4) {
          canvas.drawPath(m.extractPath(d, d + 2), stroke..color = muted);
        }
      }
    } else {
      canvas.drawRRect(rr, stroke..color = ink.withValues(alpha: .55));
    }
  }

  @override
  bool shouldRepaint(_Square old) => old.fill != fill;
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.items,
    required this.line,
    required this.eyebrow,
    required this.color,
  });

  final List<(String, String)> items;
  final Color line, color;
  final TextStyle eyebrow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: line)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Container(
                  padding: EdgeInsets.fromLTRB(i == 0 ? 0 : 12, 12, 6, 12),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(left: BorderSide(color: line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(items[i].$1.toUpperCase(), style: eyebrow),
                      const SizedBox(height: 7),
                      Text(
                        items[i].$2,
                        maxLines: 1,
                        style: Typo.serif(24, color: color),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
