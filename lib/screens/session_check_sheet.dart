import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/session_check.dart';
import '../models/models.dart';
import '../services/scroll_guard.dart';
import '../state/timer_controller.dart';
import '../theme.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../util/dates.dart';
import 'scroll_section.dart';

/// Asks about apps used during the session that could go either way, then
/// applies the answers. Returns false if the sheet was closed without
/// answering, in which case the session keeps running.
Future<bool> askCountThisTime(
  BuildContext context,
  TimerController timer,
  Task task,
) async {
  final s = timer.session;
  if (s == null || s.unsure.isEmpty) return true;
  final answer = await showLedgerSheet<_Answer>(
    context,
    title: 'Count this time?',
    child: _CountSheet(timer: timer, task: task),
  );
  if (answer == null) return false;
  timer.decide(counted: answer.counted, remember: answer.remember);
  return true;
}

class _Answer {
  const _Answer(this.counted, this.remember);

  final Set<String> counted;
  final Set<String> remember;
}

class _CountSheet extends StatefulWidget {
  const _CountSheet({required this.timer, required this.task});

  final TimerController timer;
  final Task task;

  @override
  State<_CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends State<_CountSheet> {
  late final ActiveSession _s = widget.timer.session!;
  late final List<AwayApp> _unsure = _s.unsure.values.toList();
  final _choice = <String, bool>{};
  late final _remember = <String>{
    for (final a in _unsure)
      if (rememberByDefault(a.kind)) a.package,
  };
  bool _missing = false;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    final now = DateTime.now().millisecondsSinceEpoch;
    final dropped = [
      for (final a in _unsure)
        if (_choice[a.package] != true) a.ms,
    ].fold(0, (sum, ms) => sum + ms);
    final logMinutes = ((_s.focusMs(now) - dropped) / 60000).floor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.task.name} · ${formatMinutes(_s.rawMs(now) ~/ 60000)} session',
          style: Typo.mono(12, color: l.muted),
        ),
        const SizedBox(height: 12),
        for (final a in _unsure) _row(l, a),
        for (final a in _s.notCounted.values)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: l.line)),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${a.label} '),
                  TextSpan(
                    text: awayDuration(a.ms),
                    style: Typo.mono(12, color: l.muted),
                  ),
                  TextSpan(
                    text:
                        ' · not counted, ${neverReason(a, widget.timer.limitedApps)}',
                  ),
                ],
              ),
              style: Typo.sans(13.5, color: l.muted),
            ),
          ),
        Hairline(),
        if (_missing) ...[
          const SizedBox(height: 10),
          Text(
            'Choose Count or Don’t for each app.',
            style: Typo.sans(13, color: l.accent),
          ),
        ],
        const SizedBox(height: 18),
        LedgerButton(
          label: 'Log ${formatMinutes(logMinutes < 0 ? 0 : logMinutes)}',
          filled: true,
          onPressed: () {
            if (_unsure.any((a) => !_choice.containsKey(a.package))) {
              setState(() => _missing = true);
              return;
            }
            Navigator.pop(
              context,
              _Answer({
                for (final e in _choice.entries)
                  if (e.value) e.key,
              }, _remember),
            );
          },
        ),
      ],
    );
  }

  Widget _row(Ledger l, AwayApp a) {
    final choice = _choice[a.package];
    Widget option(String label, bool value) {
      final on = choice == value;
      return InkWell(
        onTap: () => setState(() {
          _choice[a.package] = value;
          _missing = false;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: on ? l.ink : null,
          child: Text(label, style: Typo.sans(13, color: on ? l.bg : l.ink)),
        ),
      );
    }

    final remember = _remember.contains(a.package);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: l.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${a.label} '),
                      TextSpan(
                        text: awayDuration(a.ms),
                        style: Typo.mono(12, color: l.muted),
                      ),
                    ],
                  ),
                  style: Typo.sans(15, color: l.ink),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: l.ink),
                  borderRadius: BorderRadius.circular(6),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [option('Count', true), option('Don’t', false)],
                ),
              ),
            ],
          ),
          // Only a counted app can be remembered as always counting.
          if (choice == true)
            InkWell(
              onTap: () => setState(
                () => remember
                    ? _remember.remove(a.package)
                    : _remember.add(a.package),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: remember ? l.ink : null,
                        border: Border.all(color: remember ? l.ink : l.muted),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: remember
                          ? Icon(Ic.check, size: 11, color: l.bg)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Always count for this task',
                      style: Typo.sans(13, color: l.ink),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Task editor: how apps used during this task's sessions are treated, and
/// the apps it always counts. Rules live on the phone only.
class AppsDuringTask extends StatelessWidget {
  const AppsDuringTask({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    final timer = context.watch<TimerController>();
    final allowed = timer.allowedApps(taskId);
    Widget rule(String what, String how) => Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: l.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(what, style: Typo.sans(14.5, color: l.ink)),
          ),
          Text(how, style: Typo.mono(11.5, color: l.muted)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Eyebrow('Apps during this task'),
        const SizedBox(height: 4),
        rule('Social apps and games', 'never count'),
        rule('Your limited apps', 'never count'),
        rule('Video and browsers', 'ask after'),
        rule('Anything else', 'ask once'),
        const SizedBox(height: 22),
        const Eyebrow('Always count'),
        const SizedBox(height: 4),
        if (allowed.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Apps land here when you tick “Always count” after a session.',
              style: Typo.sans(13.5, color: l.muted, height: 1.5),
            ),
          ),
        for (final e in allowed.entries)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: l.line)),
            ),
            child: Row(
              children: [
                AppIcon(e.key),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.value, style: Typo.sans(15, color: l.ink)),
                ),
                IconButton(
                  tooltip: 'Stop always counting ${e.value}',
                  icon: Icon(Ic.close, size: 16, color: l.muted),
                  onPressed: () =>
                      timer.setAllowed(taskId, e.key, e.value, false),
                ),
              ],
            ),
          ),
        FutureBuilder<bool>(
          future: ScrollGuard.isEnabled(),
          builder: (context, snap) => snap.data == false
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Works while the scroll guard is on. Set it up in Me.',
                    style: Typo.sans(13, color: l.muted, height: 1.5),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
