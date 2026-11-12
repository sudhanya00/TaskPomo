import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/streaks.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../data/repo.dart';
import '../services/account.dart';
import '../services/export.dart';
import 'scroll_section.dart';
import 'task_detail_screen.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final p = app.profile;
    final l = Ledger.of(context);
    final user = FirebaseAuth.instance.currentUser;
    void set(String k, Object v) => app.repo.updateProfile({k: v});

    Widget setting(String title, String? sub, Widget trailing) => Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: l.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Typo.sans(15.5, weight: 500, color: l.ink)),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub, style: Typo.sans(13, color: l.muted, height: 1.4)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );

    Widget stepper(int value, int min, int max, int step, String key) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Step(
          label: '−',
          onTap: value - step >= min ? () => set(key, value - step) : null,
        ),
        SizedBox(
          width: 56,
          child: Text(
            '$value min',
            textAlign: TextAlign.center,
            style: Typo.mono(12.5, color: l.ink),
          ),
        ),
        _Step(
          label: '+',
          onTap: value + step <= max ? () => set(key, value + step) : null,
        ),
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
          children: [
            Eyebrow(user?.email ?? 'Signed in'),
            const SizedBox(height: 14),
            Text(
              user?.displayName?.split(' ').first ?? 'You',
              style: Typo.serif(46, color: l.ink),
            ),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                border: Border.symmetric(horizontal: BorderSide(color: l.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${p.points}',
                    style: Typo.serif(64, color: l.ink).copyWith(height: .82),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Points'),
                        const SizedBox(height: 6),
                        Text(
                          'Earned by finishing tasks, spent on freezes.',
                          style: Typo.sans(12.5, color: l.muted, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'A task earns about a point for every three minutes of its daily target. '
              'Freezing a day costs three to five days of what that task earns: longer tasks '
              'nearer three, short ones nearer five. Clean runs of 10, 20, 50 and 100 days pay a bonus.',
              style: Typo.sans(13, color: l.muted, height: 1.5),
            ),
            if (app.tasks.isNotEmpty) ...[
              const SizedBox(height: 14),
              _PointsTable(tasks: app.tasks),
            ],
            const SizedBox(height: 16),
            LedgerButton(
              label: 'Going away? Freeze days',
              icon: Ic.travel,
              onPressed: app.tasks.isEmpty
                  ? null
                  : () => showFreezeSheet(context, app.tasks),
            ),
            const SizedBox(height: 34),
            const Eyebrow('Streaks'),
            setting(
              'Auto-freeze',
              'Spend points on a missed day instead of losing the streak.',
              Switch(
                value: p.autoFreeze,
                onChanged: (v) => set('autoFreeze', v),
              ),
            ),
            const SizedBox(height: 34),
            const Eyebrow('Rounds'),
            setting(
              'Focus',
              'Shorter tasks get a round as long as their target.',
              stepper(p.focusMinutes, 10, 90, 5, 'focusMinutes'),
            ),
            setting(
              'Short break',
              null,
              stepper(p.breakMinutes, 1, 20, 1, 'breakMinutes'),
            ),
            setting(
              'Long break',
              'After every fourth round.',
              stepper(p.longBreakMinutes, 5, 45, 5, 'longBreakMinutes'),
            ),
            const SizedBox(height: 34),
            const ScrollSection(),
            const SizedBox(height: 34),
            const Eyebrow('Reminder'),
            setting(
              'Evening nudge',
              'Only on days with something left. It never names a task.',
              PopupMenuButton<int>(
                initialValue: p.reminderHour,
                color: l.bg,
                onSelected: (v) => set('reminderHour', v),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: -1,
                    child: Text('Off', style: Typo.mono(13, color: l.ink)),
                  ),
                  for (final h in [17, 18, 19, 20, 21, 22])
                    PopupMenuItem(
                      value: h,
                      child: Text(
                        DateFormat.jm().format(DateTime(2000, 1, 1, h)),
                        style: Typo.mono(13, color: l.ink),
                      ),
                    ),
                ],
                child: Text(
                  p.reminderHour < 0
                      ? 'Off'
                      : DateFormat.jm().format(
                          DateTime(2000, 1, 1, p.reminderHour),
                        ),
                  style: Typo.mono(13, color: l.ink),
                ),
              ),
            ),
            const SizedBox(height: 34),
            const Eyebrow('Points history'),
            const SizedBox(height: 4),
            StreamBuilder<List<LedgerEntry>>(
              stream: app.repo.ledger(),
              builder: (context, snap) {
                final entries = snap.data ?? const [];
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Nothing yet.',
                      style: Typo.sans(14, color: l.muted),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final e in entries.take(12))
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: l.line)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.reason,
                                    style: Typo.sans(14, color: l.ink),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('d MMM, HH:mm').format(
                                      DateTime.fromMillisecondsSinceEpoch(e.at),
                                    ),
                                    style: Typo.mono(10.5, color: l.muted),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              e.amount > 0 ? '+${e.amount}' : '${e.amount}',
                              style: Typo.serif(22, color: l.ink),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 30),
            LedgerButton(
              label: 'Export data as CSV',
              icon: Ic.share,
              onPressed: () => exportCsv(context, app.repo),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextAction('Sign out', muted: true, onPressed: Account.signOut),
                const SizedBox(width: 24),
                TextAction(
                  'Delete account',
                  muted: true,
                  onPressed: () => _deleteAccount(context, app.repo),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _deleteAccount(BuildContext context, Repo repo) async {
  final sure = await confirm(
    context,
    title: 'Delete your account?',
    body:
        'This removes your tasks, sessions, notes, streaks, points and recaps '
        'from TaskPomo, clears the widget and the scroll guard on this phone, '
        'and signs you out. It can’t be undone. Export your data first if you '
        'want a copy.',
    yes: 'Delete everything',
  );
  if (!sure || !context.mounted) return;
  try {
    if (!await Account.confirmIdentity()) return;
  } on DeleteFailed catch (e) {
    if (context.mounted) toast(context, e.message);
    return;
  }
  if (!context.mounted) return;
  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  // Blocks the app while deleting; closed before the sign-in goes, since
  // the app swaps to the sign-in screen the moment it does.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final l = Ledger.of(ctx);
      return PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: l.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Deleting your account',
                  style: Typo.serif(26, color: l.ink),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  minHeight: 1,
                  color: l.ink,
                  backgroundColor: l.line,
                ),
                const SizedBox(height: 12),
                Text(
                  'Keep TaskPomo open until this finishes.',
                  style: Typo.sans(13.5, color: l.muted),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  try {
    await Account.deleteEverything(repo);
    nav.pop();
    messenger?.showSnackBar(
      const SnackBar(content: Text('Your account and data were deleted.')),
    );
  } on DeleteFailed catch (e) {
    nav.pop();
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: l.line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: Typo.mono(15, color: onTap == null ? l.line : l.ink),
        ),
      ),
    );
  }
}

/// What each task earns per day and what freezing one day of it costs.
class _PointsTable extends StatelessWidget {
  const _PointsTable({required this.tasks});

  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    Widget row(String a, String b, String c, {bool head = false}) {
      final style = head
          ? Typo.eyebrow(l.muted)
          : Typo.mono(12.5, color: l.ink);
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: l.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                a,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: head ? style : Typo.sans(14, color: l.ink),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(b, textAlign: TextAlign.end, style: style),
            ),
            SizedBox(
              width: 64,
              child: Text(c, textAlign: TextAlign.end, style: style),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        row('TASK', 'PER DAY', 'FREEZE', head: true),
        for (final t in tasks)
          row(
            t.name,
            '+${pointValue(t.targetMinutes)}',
            '${freezeCostFor(t.targetMinutes)}',
          ),
      ],
    );
  }
}
