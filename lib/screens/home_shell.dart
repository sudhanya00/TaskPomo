import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/timer_controller.dart';
import '../theme.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../util/dates.dart';
import 'insights_screen.dart';
import 'me_screen.dart';
import 'nav.dart';
import 'timer_screen.dart';
import 'today_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [TodayScreen(), InsightsScreen(), MeScreen()],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SessionBar(),
            const Hairline(),
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  for (final (i, icon) in [
                    (0, Ic.today),
                    (1, Ic.insights),
                    (2, Ic.me),
                  ])
                    Expanded(
                      child: InkResponse(
                        onTap: () => setState(() => _tab = i),
                        radius: 28,
                        child: Center(
                          child: Icon(
                            icon,
                            size: 23,
                            color: _tab == i ? l.ink : l.muted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Running-session line above the tabs.
class _SessionBar extends StatelessWidget {
  const _SessionBar();

  @override
  Widget build(BuildContext context) {
    final timer = context.watch<TimerController>();
    final s = timer.session;
    if (s == null) return const SizedBox.shrink();
    final l = Ledger.of(context);
    final state = s.running
        ? 'Focusing'
        : s.onBreak
        ? 'On a break'
        : 'Paused';
    return Column(
      children: [
        const Hairline(),
        InkWell(
          onTap: () => pushPage(context, TimerScreen(taskId: s.taskId)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: s.running ? l.accent : l.muted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${s.taskName} · $state',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Typo.sans(14, weight: 500, color: l.ink),
                  ),
                ),
                Text(
                  formatClock(timer.focus),
                  style: Typo.mono(14, color: l.ink),
                ),
                const SizedBox(width: 6),
                Icon(Ic.chevron, size: 16, color: l.muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
