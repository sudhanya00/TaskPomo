import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/week.dart';
import '../models/models.dart';
import '../theme.dart';
import '../util/dates.dart';
import 'icons.dart';

/// Small spaced capitals: section labels, captions.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Typo.eyebrow(color ?? Ledger.of(context).muted),
  );
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = false});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final c = Ledger.of(context).line;
    return vertical
        ? Container(width: 1, color: c)
        : Container(height: 1, color: c);
  }
}

/// The 1.5px ink progress stroke used under tasks and on the widget.
class InkLine extends StatelessWidget {
  const InkLine({super.key, required this.value, this.faded = false});

  final double value;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return SizedBox(
      height: 1.5,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Container(color: l.line),
            Container(
              width: c.maxWidth * value.clamp(0.0, 1.0),
              color: faded ? l.ink.withValues(alpha: .25) : l.ink,
            ),
          ],
        ),
      ),
    );
  }
}

/// Monday to Sunday as small squares. Filled = all done, rust outline =
/// today, faint = rest day.
/// Monday to Sunday as small squares, each filled from the bottom by how
/// much of that day's work got done. Rust outline = today, faint = rest day.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.days,
    this.labels = true,
    this.size = 10,
  });

  final List<DayCell> days;
  final bool labels;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    Widget square(DayCell d) {
      final (border, width) = switch (d.kind) {
        DayKind.past => (l.ink.withValues(alpha: .55), 1.0),
        DayKind.rest => (l.line, 1.0),
        DayKind.today => (l.accent, 1.5),
        DayKind.future => (l.ink.withValues(alpha: .3), 1.0),
      };
      final radius = BorderRadius.circular(size * .28);
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: border, width: width),
          borderRadius: radius,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: d.fill.clamp(0.0, 1.0),
              widthFactor: 1,
              child: ColoredBox(color: l.ink),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) SizedBox(width: size * .6),
          labels
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    square(days[i]),
                    const SizedBox(height: 6),
                    Text(
                      'MTWTFSS'[i],
                      style: Typo.mono(
                        9,
                        color: days[i].kind == DayKind.today ? l.ink : l.muted,
                      ),
                    ),
                  ],
                )
              : square(days[i]),
        ],
      ],
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 36, this.selected = false});

  final IconData icon;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? l.ink : null,
        border: Border.all(color: selected ? l.ink : l.line),
        borderRadius: BorderRadius.circular(size * .24),
      ),
      child: Icon(icon, size: size * .5, color: selected ? l.bg : l.ink),
    );
  }
}

/// Rectangular, flat, slightly rounded. Solid ink for the main action,
/// hairline outline otherwise.
class LedgerButton extends StatelessWidget {
  const LedgerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    final enabled = onPressed != null;
    final fg = filled ? l.bg : l.ink;
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: Material(
        color: filled ? l.ink : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: filled ? BorderSide.none : BorderSide(color: l.line),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: fg),
                  const SizedBox(width: 8),
                ],
                Text(label, style: Typo.sans(15, weight: 500, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain text action, for secondary choices.
class TextAction extends StatelessWidget {
  const TextAction(
    this.label, {
    super.key,
    required this.onPressed,
    this.muted = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          label,
          style: Typo.sans(14, weight: 500, color: muted ? l.muted : l.ink),
        ),
      ),
    );
  }
}

/// Labelled numbers in columns separated by hairlines.
class MetaRow extends StatelessWidget {
  const MetaRow(this.items, {super.key, this.valueSize = 26});

  final List<(String, String)> items;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: l.line)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Hairline(vertical: true),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(i == 0 ? 0 : 14, 14, 8, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(items[i].$1),
                      const SizedBox(height: 8),
                      Text(
                        items[i].$2,
                        style: Typo.serif(valueSize, color: l.ink),
                        maxLines: 1,
                      ),
                    ],
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

/// One habit as a ruled line: icon, name, minutes, streak, and an ink stroke
/// for today's progress along the bottom rule.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.log,
    required this.liveSeconds,
    required this.running,
    required this.onTap,
    this.dimmed = false,
  });

  final Task task;
  final DayLog? log;
  final int liveSeconds;
  final bool running;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    final done = log?.completed ?? false;
    final frozen = log?.frozen ?? false;
    final mins = ((log?.seconds ?? 0) + liveSeconds) ~/ 60;
    final meta = done
        ? '${formatMinutes(mins)} · done'
        : frozen
        ? 'frozen'
        : running
        ? '${formatMinutes(mins)} of ${formatMinutes(task.targetMinutes)} · running'
        : '${formatMinutes(mins)} of ${formatMinutes(task.targetMinutes)}';

    return Opacity(
      opacity: dimmed ? .45 : 1,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                children: [
                  IconTile(taskIcon(task.icon), size: 36),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Typo.sans(
                                16.5,
                                weight: 500,
                                color: done ? l.muted : l.ink,
                              ).copyWith(
                                decoration: done
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: l.muted,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          meta,
                          style: Typo.mono(
                            11.5,
                            color: running ? l.accent : l.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${task.currentStreak}',
                          style: Typo.serif(24, color: l.ink),
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
            ),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: InkLine(
                value: done
                    ? 1
                    : frozen
                    ? 0
                    : mins / task.targetMinutes,
                faded: done,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Watch-dial of 60 ticks. Elapsed ticks are ink, the live position is a
/// rust dot.
class TickDial extends StatelessWidget {
  const TickDial({
    super.key,
    required this.progress,
    this.size = 280,
    this.child,
    this.quiet = false,
  });

  final double progress;
  final double size;
  final Widget? child;

  /// Break mode: the ticks go muted.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DialPainter(
          progress.clamp(0.0, 1.0),
          quiet ? l.muted : l.ink,
          l.line,
          l.accent,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.progress, this.ink, this.track, this.accent);

  final double progress;
  final Color ink, track, accent;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 60;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final done = (progress * n).floor();
    final p = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2 - math.pi / 2;
      final long = i % 5 == 0;
      final inner = r - (long ? 16 : 9);
      p
        ..color = i < done ? ink : track.withValues(alpha: .9)
        ..strokeWidth = long ? 1.8 : 1.1;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * inner,
        c + Offset(math.cos(a), math.sin(a)) * r,
        p,
      );
    }
    if (progress > 0) {
      final a = progress * math.pi * 2 - math.pi / 2;
      canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * r,
        4,
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress ||
      old.ink != ink ||
      old.track != track ||
      old.accent != accent;
}

/// Bottom sheet with Ledger styling: a short title, then content.
Future<T?> showLedgerSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final l = Ledger.of(ctx);
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            22,
            24,
            20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: l.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(title, style: Typo.serif(30, color: l.ink)),
              const SizedBox(height: 14),
              // Scrolls when the content is taller than the screen.
              Flexible(child: SingleChildScrollView(child: child)),
            ],
          ),
        ),
      );
    },
  );
}

/// Yes/no question in Ledger style.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String yes,
}) async {
  final ok = await showLedgerSheet<bool>(
    context,
    title: title,
    child: Builder(
      builder: (ctx) {
        final l = Ledger.of(ctx);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(body, style: Typo.sans(14.5, color: l.muted, height: 1.5)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: LedgerButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LedgerButton(
                    label: yes,
                    filled: true,
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
  return ok ?? false;
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));
}

/// 2×2 grid of labelled numbers.
class StatTiles extends StatelessWidget {
  const StatTiles({super.key, required this.items});

  final List<(String, String, String)> items;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    Widget tile((String, String, String) it, {required bool left}) => Expanded(
      child: Container(
        padding: EdgeInsets.fromLTRB(left ? 0 : 14, 13, 8, 13),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: l.line),
            right: left ? BorderSide(color: l.line) : BorderSide.none,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(it.$1),
            const SizedBox(height: 8),
            Text(it.$2, style: Typo.serif(30, color: l.ink), maxLines: 1),
            const SizedBox(height: 2),
            Text(it.$3, style: Typo.mono(10.5, color: l.muted)),
          ],
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: l.line)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i += 2)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tile(items[i], left: true),
                  if (i + 1 < items.length) tile(items[i + 1], left: false),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ChartSection extends StatelessWidget {
  const ChartSection({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.sub,
    required this.child,
  });

  final String eyebrow, title, sub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 30),
      padding: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: l.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(eyebrow),
          const SizedBox(height: 6),
          Text(title, style: Typo.serif(30, color: l.ink)),
          const SizedBox(height: 4),
          Text(sub, style: Typo.sans(12.5, color: l.muted, height: 1.45)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.names, required this.colors});

  final List<String> names;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (var i = 0; i < names.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors[i],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(names[i], style: Typo.sans(12, color: l.ink)),
            ],
          ),
      ],
    );
  }
}
