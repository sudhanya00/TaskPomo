import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/analytics.dart';
import '../theme.dart';
import '../util/dates.dart';

/// A drawable, tappable piece of a chart.
class Mark {
  const Mark(
    this.rect,
    this.color, {
    this.tip,
    this.radius = 2,
    this.circle = false,
    this.text,
    this.textColor,
    this.border,
  });

  final Rect rect;
  final Color color;

  /// Shown under the chart when tapped. Marks without one aren't tappable.
  final String? tip;
  final double radius;
  final bool circle;

  /// Optional value printed inside the mark.
  final String? text;
  final Color? textColor;
  final Color? border;
}

class ChartLabel {
  const ChartLabel(
    this.at,
    this.text, {
    this.align = TextAlign.left,
    this.size = 9,
    this.color,
    this.sans = false,
    this.rotate = 0,
  });

  /// Left/centre/right edge (per [align]) of the text's baseline box top.
  final Offset at;
  final String text;
  final TextAlign align;
  final double size;
  final Color? color;
  final bool sans;
  final double rotate;
}

class ChartLine {
  const ChartLine(
    this.a,
    this.b,
    this.color, {
    this.width = 1,
    this.dashed = false,
  });

  final Offset a, b;
  final Color color;
  final double width;
  final bool dashed;
}

class ChartLayout {
  ChartLayout({
    List<Mark>? marks,
    List<ChartLabel>? labels,
    List<ChartLine>? lines,
  }) : marks = marks ?? [],
       labels = labels ?? [],
       lines = lines ?? [];

  final List<Mark> marks;
  final List<ChartLabel> labels;
  final List<ChartLine> lines;
}

typedef ChartBuilder = ChartLayout Function(Size size, Ledger l);

/// Hosts a chart: lays it out for the available width, paints it, and shows
/// the tapped mark's numbers on a line underneath.
class Chart extends StatefulWidget {
  const Chart({
    super.key,
    required this.height,
    required this.build,
    this.hint = 'Tap a mark for its numbers',
  });

  final double height;
  final ChartBuilder build;
  final String? hint;

  @override
  State<Chart> createState() => _ChartState();
}

class _ChartState extends State<Chart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, widget.height);
        final layout = widget.build(size, l);
        final sel = _selected != null && _selected! < layout.marks.length
            ? layout.marks[_selected!]
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                int? hit;
                for (var i = 0; i < layout.marks.length; i++) {
                  final m = layout.marks[i];
                  final area = m.rect.inflate(m.rect.shortestSide < 10 ? 4 : 1);
                  if (m.tip != null && area.contains(d.localPosition)) {
                    hit = i;
                  }
                }
                setState(() => _selected = hit == _selected ? null : hit);
              },
              child: CustomPaint(
                size: size,
                painter: _ChartPainter(layout, _selected, l),
              ),
            ),
            if (widget.hint != null || sel != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  sel?.tip ?? widget.hint!,
                  style: Typo.mono(11, color: sel != null ? l.ink : l.muted),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.layout, this.selected, this.l);

  final ChartLayout layout;
  final int? selected;
  final Ledger l;

  @override
  void paint(Canvas canvas, Size size) {
    for (final ln in layout.lines) {
      final p = Paint()
        ..color = ln.color
        ..strokeWidth = ln.width;
      if (!ln.dashed) {
        canvas.drawLine(ln.a, ln.b, p);
      } else {
        final total = (ln.b - ln.a).distance;
        final dir = (ln.b - ln.a) / total;
        for (var t = 0.0; t < total; t += 5) {
          canvas.drawLine(
            ln.a + dir * t,
            ln.a + dir * math.min(t + 2.5, total),
            p,
          );
        }
      }
    }
    for (var i = 0; i < layout.marks.length; i++) {
      final m = layout.marks[i];
      final paint = Paint()..color = m.color;
      if (m.circle) {
        canvas.drawCircle(
          m.rect.center,
          m.rect.width / 2 + 2,
          Paint()..color = l.bg,
        );
        canvas.drawCircle(m.rect.center, m.rect.width / 2, paint);
      } else {
        final rr = RRect.fromRectAndRadius(m.rect, Radius.circular(m.radius));
        canvas.drawRRect(rr, paint);
        if (m.border != null) {
          canvas.drawRRect(
            rr.deflate(.5),
            Paint()
              ..color = m.border!
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
      }
      if (m.text != null) {
        _text(
          canvas,
          m.text!,
          m.rect.center - const Offset(0, 6),
          TextAlign.center,
          Typo.mono(9, color: m.textColor ?? l.ink),
          m.rect.width,
        );
      }
      if (i == selected) {
        final ring = Paint()
          ..color = l.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        if (m.circle) {
          canvas.drawCircle(m.rect.center, m.rect.width / 2 + 3, ring);
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              m.rect.inflate(1.5),
              Radius.circular(m.radius + 1),
            ),
            ring,
          );
        }
      }
    }
    for (final lb in layout.labels) {
      final style = lb.sans
          ? Typo.sans(lb.size, color: lb.color ?? l.ink)
          : Typo.mono(lb.size, color: lb.color ?? l.muted);
      if (lb.rotate != 0) {
        canvas.save();
        canvas.translate(lb.at.dx, lb.at.dy);
        canvas.rotate(lb.rotate);
        _text(canvas, lb.text, Offset.zero, lb.align, style, 200);
        canvas.restore();
      } else {
        _text(canvas, lb.text, lb.at, lb.align, style, 200);
      }
    }
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at,
    TextAlign align,
    TextStyle style,
    double maxW,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final dx = switch (align) {
      TextAlign.center => at.dx - tp.width / 2,
      TextAlign.right => at.dx - tp.width,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

// ---------------------------------------------------------------- helpers

String hm(int seconds) {
  final m = seconds ~/ 60;
  if (m < 60) return '$m min';
  return m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min';
}

/// Shade by quantile so a few huge days don't wash out the rest.
Color Function(int) quantileShade(Iterable<int> values) {
  final nz = values.where((v) => v > 0).toList()..sort();
  if (nz.isEmpty) return (_) => Ledger.ramp[0];
  final qs = [
    .2,
    .4,
    .6,
    .8,
  ].map((q) => nz[(q * (nz.length - 1)).floor()]).toList();
  return (v) =>
      v <= 0 ? Ledger.ramp[0] : Ledger.ramp[1 + qs.where((t) => v > t).length];
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

// ---------------------------------------------------------------- charts

/// Every day of [year], 53 columns of weeks.
ChartBuilder yearSquares(
  int year,
  Map<String, int> perDay,
  String today,
) => (size, l) {
  final out = ChartLayout();
  final first = DateTime(year, 1, 1), off = first.weekday - 1;
  const gap = 1.3;
  final cell = (size.width - gap * 52) / 53;
  final shade = quantileShade(perDay.values);
  for (var k = 0; k < 366; k++) {
    final d = DateTime(year, 1, 1 + k);
    if (d.year != year) break;
    final key = dateKey(d), idx = k + off;
    final r = Rect.fromLTWH(
      (idx ~/ 7) * (cell + gap),
      14 + (idx % 7) * (cell + gap),
      cell,
      cell,
    );
    if (key.compareTo(today) > 0) {
      out.marks.add(Mark(r, Colors.transparent, border: l.line, radius: 1.4));
    } else {
      final v = perDay[key] ?? 0;
      out.marks.add(
        Mark(
          r,
          shade(v),
          radius: 1.4,
          tip: '${shortDate(key)} · ${v == 0 ? 'nothing logged' : hm(v)}',
        ),
      );
    }
  }
  for (var m = 0; m < 12; m++) {
    final idx = DateTime(year, m + 1, 1).difference(first).inDays + off;
    out.labels.add(
      ChartLabel(
        Offset((idx ~/ 7) * (cell + gap), 0),
        'JFMAMJJASOND'[m],
        size: 8.5,
      ),
    );
  }
  final ly = 14 + 7 * (cell + gap) + 8;
  out.labels.add(ChartLabel(Offset(0, ly), 'less', size: 8.5));
  for (var i = 0; i < Ledger.ramp.length; i++) {
    out.marks.add(
      Mark(
        Rect.fromLTWH(26 + i * 10.0, ly + 1, 8, 8),
        Ledger.ramp[i],
        radius: 1.5,
      ),
    );
  }
  out.labels.add(ChartLabel(Offset(26 + 6 * 10.0 + 4, ly), 'more', size: 8.5));
  return out;
};

/// Hours per bucket, stacked by task (first task at the bottom).
ChartBuilder stackedBars(
  List<Bucket> buckets,
  List<String> names,
  List<Color> colors,
) => (size, l) {
  final out = ChartLayout();
  if (buckets.isEmpty) return out;
  const left = 26.0, bottom = 18.0;
  final h = size.height - bottom;
  final maxSec = buckets.fold<int>(0, (m, b) => math.max(m, b.total));
  final maxH = math.max(1, (maxSec / 3600).ceil());
  final step = maxH <= 4 ? 1 : (maxH / 4).ceil();
  final top = (maxH / step).ceil() * step;
  for (var v = 0; v <= top; v += step) {
    final y = h - v / top * (h - 6);
    out.lines.add(
      ChartLine(
        Offset(left, y),
        Offset(size.width, y),
        v == 0 ? l.ink.withValues(alpha: .25) : l.line,
      ),
    );
    out.labels.add(ChartLabel(Offset(0, y - 6), '$v h', size: 8.5));
  }
  final slot = (size.width - left) / buckets.length;
  final bw = math.max(2.0, math.min(22.0, slot - math.max(2.0, slot * .25)));
  final labelEvery = (buckets.length / 4).ceil();
  for (var k = 0; k < buckets.length; k++) {
    final b = buckets[k];
    final x = left + k * slot + (slot - bw) / 2;
    var y = h;
    for (var i = 0; i < b.perTask.length; i++) {
      final sec = b.perTask[i];
      if (sec <= 0) continue;
      final bh = sec / 3600 / top * (h - 6);
      // 2px of paper between stacked segments.
      final gap = y == h ? 0.0 : 1.0;
      out.marks.add(
        Mark(
          Rect.fromLTWH(x, y - bh + gap, bw, math.max(.5, bh - gap)),
          colors[i],
          radius: 0,
          tip: '${b.label} · ${names[i]} ${hm(sec)} · total ${hm(b.total)}',
        ),
      );
      y -= bh;
    }
    if (k % labelEvery == 0) {
      out.labels.add(ChartLabel(Offset(x, h + 5), b.label, size: 8.5));
    }
  }
  return out;
};

/// Rows × columns of shaded cells. NaN = no data (outlined).
ChartBuilder heatGrid({
  required List<String> rows,
  required List<String> cols,
  required List<List<double>> values,
  required String Function(int r, int c, double v) tip,
  double leftWidth = 22,
  double topHeight = 0,
  bool numbers = false,
  bool rotateCols = false,
  int colLabelEvery = 1,
}) => (size, l) {
  final out = ChartLayout();
  final bottom = cols.isEmpty || rotateCols ? 0.0 : 16.0;
  final cw = (size.width - leftWidth) / cols.length;
  final ch = (size.height - topHeight - bottom) / rows.length;
  final present = values.expand((r) => r).where((v) => !v.isNaN);
  final lo = present.isEmpty ? 0.0 : present.reduce(math.min);
  final hi = present.isEmpty ? 1.0 : present.reduce(math.max);
  for (var r = 0; r < rows.length; r++) {
    out.labels.add(
      ChartLabel(
        Offset(0, topHeight + r * ch + ch / 2 - 7),
        rows[r],
        size: numbers ? 10.5 : 9,
        sans: numbers,
        color: numbers ? l.ink : null,
      ),
    );
    for (var c = 0; c < cols.length; c++) {
      final v = values[r][c];
      final rect = Rect.fromLTWH(
        leftWidth + c * cw + 1,
        topHeight + r * ch + 1,
        cw - 2,
        ch - 2,
      );
      if (v.isNaN) {
        out.marks.add(
          Mark(rect, Colors.transparent, border: l.line, radius: 3),
        );
        continue;
      }
      final t = hi == lo ? (v > 0 ? 1.0 : 0.0) : (v - lo) / (hi - lo);
      final color = v <= 0 && !numbers
          ? Ledger.ramp[0]
          : Ledger.ramp[1 + math.min(4, (t * 4.999).floor())];
      out.marks.add(
        Mark(
          rect,
          color,
          radius: 3,
          tip: tip(r, c, v),
          text: numbers ? '${(v * 100).round()}' : null,
          textColor: t > .55 ? l.bg : l.ink,
        ),
      );
    }
  }
  for (var c = 0; c < cols.length; c += colLabelEvery) {
    if (rotateCols) {
      out.labels.add(
        ChartLabel(
          // Text ends just above its column and slants up-left, so long
          // names never run off the right edge.
          Offset(leftWidth + c * cw + cw / 2 + 4, topHeight - 14),
          cols[c],
          size: 9,
          rotate: 0.85,
          align: TextAlign.right,
        ),
      );
    } else {
      out.labels.add(
        ChartLabel(
          Offset(leftWidth + c * cw, topHeight + rows.length * ch + 4),
          cols[c],
          size: 8.5,
        ),
      );
    }
  }
  return out;
};

/// Weekday × hour of session starts, 5 am to midnight.
ChartBuilder focusGrid(List<List<int>> focus) => heatGrid(
  rows: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
  cols: [for (var h = 5; h < 24; h++) '$h'],
  colLabelEvery: 3,
  values: [
    for (final row in focus) [for (var h = 5; h < 24; h++) row[h].toDouble()],
  ],
  tip: (r, c, v) =>
      '${_weekdays[r]} ${c + 5}:00 · ${v == 0 ? 'no sessions started' : '${hm(v.round() * 60)} started here'}',
);

/// Session lengths in 5-minute bins with the median marked.
ChartBuilder lengthHistogram(List<int> bins, double median) => (size, l) {
  final out = ChartLayout();
  const bottom = 16.0;
  final h = size.height - bottom;
  final max = math.max(1, bins.reduce(math.max));
  final bw = size.width / bins.length;
  for (var i = 0; i < bins.length; i++) {
    final bh = bins[i] / max * (h - 12);
    out.marks.add(
      Mark(
        Rect.fromLTWH(i * bw + 1, h - bh, bw - 2, math.max(.5, bh)),
        l.ink,
        radius: 0,
        tip:
            '${i == bins.length - 1 ? '75+ min' : '${i * 5}–${i * 5 + 5} min'} · ${bins[i]} sessions',
      ),
    );
  }
  out.lines.add(
    ChartLine(
      Offset(0, h),
      Offset(size.width, h),
      l.ink.withValues(alpha: .25),
    ),
  );
  if (median > 0) {
    final mx = math.min(median, 80) / 80 * size.width;
    out.lines.add(
      ChartLine(Offset(mx, 0), Offset(mx, h), l.accent, width: 1.5),
    );
    out.labels.add(
      ChartLabel(
        Offset(mx + 4, 0),
        'median ${median.round()} min',
        size: 9,
        color: l.ink,
      ),
    );
  }
  for (final (i, t) in [
    (0, '0'),
    (4, '20'),
    (8, '40'),
    (12, '60'),
    (15, '75+'),
  ]) {
    out.labels.add(
      ChartLabel(Offset(i * bw + (i == 15 ? 0 : 1), h + 4), t, size: 8.5),
    );
  }
  return out;
};

/// Average minutes on due days against target, one row per task.
ChartBuilder targetDots(
  List<String> names,
  List<double> ratio,
  List<double> avgMin,
  List<int> targets,
  List<int> dueDays,
) => (size, l) {
  final out = ChartLayout();
  const left = 86.0, bottom = 16.0;
  final rowH = (size.height - bottom) / math.max(1, names.length);
  final maxR = math.max(1.5, ratio.fold<double>(0, math.max) * 1.1);
  double x(double r) => left + r / maxR * (size.width - left - 10);
  for (final r in [0.0, .5, 1.0, 1.5, 2.0, 3.0]) {
    if (r > maxR) continue;
    out.lines.add(
      ChartLine(
        Offset(x(r), 0),
        Offset(x(r), size.height - bottom),
        r == 1 ? l.ink.withValues(alpha: .35) : l.line,
        dashed: r == 1,
      ),
    );
    out.labels.add(
      ChartLabel(
        Offset(x(r), size.height - bottom + 4),
        '${(r * 100).round()}%',
        size: 8.5,
        align: TextAlign.center,
      ),
    );
  }
  for (var i = 0; i < names.length; i++) {
    final y = i * rowH + rowH / 2;
    out.labels.add(
      ChartLabel(
        Offset(0, y - 7),
        names[i],
        size: 10.5,
        sans: true,
        color: l.ink,
      ),
    );
    // No finished due days yet: say so rather than plot a misleading 0%.
    if (dueDays[i] == 0) {
      out.labels.add(
        ChartLabel(
          Offset(x(0) + 4, y - 6),
          'no finished due days yet',
          size: 9,
        ),
      );
      continue;
    }
    out.lines.add(
      ChartLine(
        Offset(x(math.min(1, ratio[i])), y),
        Offset(x(math.max(1, ratio[i])), y),
        l.ink.withValues(alpha: .25),
        width: 1.5,
      ),
    );
    out.marks.add(
      Mark(
        Rect.fromCircle(center: Offset(x(ratio[i]), y), radius: 4.5),
        l.ink,
        circle: true,
        tip:
            '${names[i]} · avg ${avgMin[i].round()} of ${targets[i]} min on due days (${(ratio[i] * 100).round()}%)',
      ),
    );
  }
  return out;
};

/// Each unbroken streak as a bar on a shared date axis, one row per task.
ChartBuilder runsChart(
  DateRange range,
  List<String> names,
  List<Color> colors,
  List<List<Run>> runs,
  List<String> captions,
) => (size, l) {
  final out = ChartLayout();
  const left = 86.0;
  final rowH = size.height / math.max(1, names.length);
  final span = math.max(1, range.days);
  double x(String d) =>
      left +
      parseKey(d).difference(parseKey(range.from)).inDays /
          span *
          (size.width - left);
  final dayW = (size.width - left) / span;
  for (var i = 0; i < names.length; i++) {
    final y = i * rowH + 4;
    out.labels.add(
      ChartLabel(
        Offset(0, y - 2),
        names[i],
        size: 10.5,
        sans: true,
        color: l.ink,
      ),
    );
    out.lines.add(
      ChartLine(Offset(left, y + 4), Offset(size.width, y + 4), l.line),
    );
    for (final r in runs[i]) {
      final x0 = x(r.start), x1 = x(r.end) + dayW;
      out.marks.add(
        Mark(
          Rect.fromLTWH(x0, y, math.max(1.5, x1 - x0 - .6), 8),
          colors[i],
          radius: 2,
          tip:
              '${names[i]} · ${r.length}-day run, ${shortDate(r.start)} to ${shortDate(r.end)}',
        ),
      );
    }
    out.labels.add(ChartLabel(Offset(left, y + 13), captions[i], size: 8.5));
  }
  return out;
};

/// A month as a calendar, shaded by minutes.
ChartBuilder monthCalendar(String ym, Map<String, int> perDay, String today) =>
    (size, l) {
      final out = ChartLayout();
      final r = DateRange.month(ym);
      final first = parseKey(r.from), off = first.weekday - 1;
      final cw = size.width / 7;
      final weeks = ((off + r.days) / 7).ceil();
      final ch = (size.height - 16) / weeks;
      final shade = quantileShade(
        perDay.entries.where((e) => r.contains(e.key)).map((e) => e.value),
      );
      for (var i = 0; i < 7; i++) {
        out.labels.add(
          ChartLabel(Offset(i * cw + 4, 0), 'MTWTFSS'[i], size: 8.5),
        );
      }
      final values =
          perDay.entries
              .where((e) => r.contains(e.key))
              .map((e) => e.value)
              .toList()
            ..sort();
      final dark = values.isEmpty
          ? 1 << 30
          : values[(values.length * .6).floor().clamp(0, values.length - 1)];
      var k = 0;
      for (final d in daysBetween(r.from, addDays(r.to, 1))) {
        final idx = k + off;
        final rect = Rect.fromLTWH(
          (idx % 7) * cw + 1,
          16 + (idx ~/ 7) * ch,
          cw - 3,
          ch - 3,
        );
        final v = perDay[d] ?? 0;
        final future = d.compareTo(today) > 0;
        out.marks.add(
          Mark(
            rect,
            future ? Colors.transparent : shade(v),
            border: future ? l.line : null,
            radius: 3,
            tip: future
                ? null
                : '${shortDate(d)} · ${v == 0 ? 'nothing logged' : hm(v)}',
          ),
        );
        out.labels.add(
          ChartLabel(
            rect.topLeft + const Offset(4, 3),
            '${parseKey(d).day}',
            size: 8.5,
            color: !future && v > dark ? l.bg : l.ink,
          ),
        );
        k++;
      }
      return out;
    };
