import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/scroll.dart';
import '../models/models.dart';
import '../services/scroll_guard.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

/// Me → Scroll minutes: points spent as time on the apps you choose to
/// limit, the reserve kept for freezes, and the one-time Android setup.
class ScrollSection extends StatefulWidget {
  const ScrollSection({super.key});

  @override
  State<ScrollSection> createState() => _ScrollSectionState();
}

class _ScrollSectionState extends State<ScrollSection>
    with WidgetsBindingObserver {
  GuardState _state = const GuardState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    // Read the app list now so the picker opens on it.
    if (ScrollGuard.supported) ScrollGuard.installedApps().ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android's settings is when the service gets switched on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await ScrollGuard.state();
    if (mounted) setState(() => _state = s);
  }

  @override
  Widget build(BuildContext context) {
    if (!ScrollGuard.supported) return const SizedBox.shrink();
    final app = context.watch<AppController>();
    final l = Ledger.of(context);
    final p = app.profile;
    final reserve = p.scrollReserve ?? defaultReserve(app.tasks);
    final left =
        (p.points - reserve) * minutesPerPoint - _state.unsyncedSeconds ~/ 60;
    void set(String k, Object? v) => app.repo.updateProfile({k: v});

    Widget row(String title, String? sub, Widget trailing) => Container(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Scroll minutes'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            border: Border.symmetric(horizontal: BorderSide(color: l.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${left < 0 ? 0 : left}',
                style: Typo.serif(64, color: l.ink).copyWith(height: .82),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(left < 0 ? '${-left} min owed' : 'Minutes left'),
                    const SizedBox(height: 6),
                    Text(
                      p.scrollApps.isEmpty
                          ? 'Pick the apps to limit below.'
                          : 'across ${p.scrollApps.map((a) => a.label).join(', ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Typo.sans(12.5, color: l.muted, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Every point is a minute on these apps, combined. $reserve points stay in reserve for '
          'freezes. At zero they pause; once a day you can take $graceMinutes grace minutes, '
          'repaid from your next points.',
          style: Typo.sans(13, color: l.muted, height: 1.5),
        ),
        const SizedBox(height: 8),
        row(
          'Guard',
          _state.enabled
              ? 'On. Counting and pausing.'
              : 'Off. Needs a one-time Android setup.',
          _state.enabled
              ? Icon(Ic.check, size: 18, color: l.ink)
              : TextAction('Set up', onPressed: () => _setup(context)),
        ),
        row(
          'Limited apps',
          p.scrollApps.isEmpty ? 'None yet' : '${p.scrollApps.length} chosen',
          TextAction('Choose', onPressed: () => _pick(context, p.scrollApps)),
        ),
        row(
          'Reserve for freezes',
          p.scrollReserve == null
              ? 'Default: two freezes of your biggest task.'
              : null,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Step(
                '−',
                reserve >= 10 ? () => set('scrollReserve', reserve - 10) : null,
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '$reserve',
                  textAlign: TextAlign.center,
                  style: Typo.mono(12.5, color: l.ink),
                ),
              ),
              _Step(
                '+',
                reserve <= 990
                    ? () => set('scrollReserve', reserve + 10)
                    : null,
              ),
            ],
          ),
        ),
        StreamBuilder<int>(
          stream: app.repo.scrollMinutesOn(app.today),
          builder: (context, snap) => row(
            'Used today',
            null,
            Builder(
              builder: (_) {
                // Seconds until the first full minute, so early use shows.
                final s = (snap.data ?? 0) * 60 + _state.unsyncedSeconds;
                return Text(
                  s < 60 ? '$s s' : '${s ~/ 60} min',
                  style: Typo.mono(12.5, color: l.ink),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _setup(BuildContext context) async {
    await showLedgerSheet<void>(
      context,
      title: 'Turn on the guard',
      child: const _GuardSetup(),
    );
    _refresh();
  }

  Future<void> _pick(BuildContext context, List<LimitedApp> current) async {
    final repo = context.read<AppController>().repo;
    final chosen = await showLedgerSheet<List<LimitedApp>>(
      context,
      title: 'Apps to limit',
      child: _Picker(initial: current),
    );
    if (chosen != null) {
      repo.updateProfile({
        'scrollApps': [for (final a in chosen) a.toMap()],
      });
    }
  }
}

/// Google Play requires apps that use accessibility for something other
/// than helping people with disabilities to say plainly what the service
/// sees and does, and to get agreement, before sending people to turn it on.
/// Agreement is remembered on the phone; the disclosure is shown again
/// until then.
class _GuardSetup extends StatefulWidget {
  const _GuardSetup();

  @override
  State<_GuardSetup> createState() => _GuardSetupState();
}

class _GuardSetupState extends State<_GuardSetup> {
  // Bumped when the disclosure changes, so it's agreed to again.
  static const _consentKey = 'guard_consent_v2_at';
  bool? _agreed;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _agreed = prefs.getString(_consentKey) != null);
      }
    });
  }

  Future<void> _agree() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_consentKey, DateTime.now().toIso8601String());
    if (mounted) setState(() => _agreed = true);
  }

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return switch (_agreed) {
      null => const SizedBox(height: 120),
      false => _disclosure(l),
      true => _steps(l),
    };
  }

  Widget _disclosure(Ledger l) {
    Widget point(String title, String body) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: l.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(title),
          const SizedBox(height: 6),
          Text(body, style: Typo.sans(14, color: l.ink, height: 1.5)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The guard uses Android’s accessibility service. Here is exactly what it does.',
          style: Typo.sans(14, color: l.muted, height: 1.5),
        ),
        const SizedBox(height: 10),
        point(
          'What it sees',
          'Only which app is open, while the guard is switched on. It never '
              'reads what is on screen: no text, messages, photos or videos.',
        ),
        point(
          'What it does',
          'Counts time in the apps you chose to limit, and covers them with a '
              'pause page when your points run out. During a focus session it '
              'also notes which apps you open, so time in them can be left out. '
              'It never taps or types for you.',
        ),
        point(
          'What is saved',
          'Minutes spent in your limited apps, with their names, are saved to '
              'your TaskPomo account so points can be taken for them. For focus '
              'sessions only the minutes left out are saved, not which apps. '
              'Nothing else about other apps leaves your phone, and nothing is '
              'shared.',
        ),
        point(
          'Turning it off',
          'Any time, in Android Settings, Accessibility. Deleting your '
              'account removes what was saved.',
        ),
        const SizedBox(height: 14),
        LedgerButton(
          label: 'Agree and continue',
          filled: true,
          onPressed: _agree,
        ),
        const SizedBox(height: 8),
        LedgerButton(label: 'Not now', onPressed: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _steps(Ledger l) {
    Widget step(
      String n,
      String title,
      String body,
      String button,
      VoidCallback onTap,
    ) => Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: l.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$n  $title', style: Typo.sans(15.5, weight: 500, color: l.ink)),
          const SizedBox(height: 4),
          Text(body, style: Typo.sans(13.5, color: l.muted, height: 1.5)),
          const SizedBox(height: 10),
          LedgerButton(label: button, height: 44, onPressed: onTap),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The guard only sees which app is open, never what is on screen.',
          style: Typo.sans(14, color: l.muted, height: 1.5),
        ),
        const SizedBox(height: 10),
        step(
          '01',
          'Switch on TaskPomo',
          'In Accessibility, open Installed apps (or Downloaded apps), choose '
              'TaskPomo scroll minutes and turn it on.',
          'Open Accessibility',
          ScrollGuard.openAccessibilitySettings,
        ),
        step(
          '02',
          'If Android says it’s restricted',
          'Apps installed outside the Play Store need one more switch. In App '
              'info, tap ⋮ at the top right, then Allow restricted settings, '
              'and try step 01 again.',
          'Open App info',
          ScrollGuard.openAppInfo,
        ),
      ],
    );
  }
}

class _Picker extends StatefulWidget {
  const _Picker({required this.initial});

  final List<LimitedApp> initial;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  late final Set<String> _on = {for (final a in widget.initial) a.package};
  // Opens on the list read earlier (Me prefetches it), then swaps in a
  // fresh read so newly installed apps appear.
  List<InstalledApp>? _all = ScrollGuard.lastApps;
  String _query = '';

  @override
  void initState() {
    super.initState();
    ScrollGuard.installedApps().then(
      (a) {
        if (mounted) setState(() => _all = a);
      },
      onError: (Object _) {
        if (mounted) setState(() => _all ??= const []);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    final all = _all;
    final q = _query.toLowerCase();
    // Apps chosen when the sheet opened go first; ticking one doesn't move it.
    final first = {for (final a in widget.initial) a.package};
    final shown =
        [
          for (final a in all ?? const <InstalledApp>[])
            if (q.isEmpty || a.label.toLowerCase().contains(q)) a,
        ]..sort((a, b) {
          final ca = first.contains(a.package) ? 0 : 1,
              cb = first.contains(b.package) ? 0 : 1;
          return ca != cb
              ? ca - cb
              : a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });

    final Widget list;
    if (all == null) {
      list = const _PickerLoading();
    } else if (shown.isEmpty) {
      list = Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Text(
          all.isEmpty ? 'Couldn\'t read your apps.' : 'No apps match.',
          style: Typo.sans(14, color: l.muted),
        ),
      );
    } else {
      list = ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: shown.length,
        itemExtent: 51,
        itemBuilder: (context, i) {
          final a = shown[i];
          final on = _on.contains(a.package);
          return InkWell(
            onTap: () =>
                setState(() => on ? _on.remove(a.package) : _on.add(a.package)),
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: l.line)),
              ),
              child: Row(
                children: [
                  AppIcon(a.package),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Typo.sans(15, color: l.ink),
                    ),
                  ),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: on ? l.ink : null,
                      border: Border.all(color: on ? l.ink : l.muted),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: on ? Icon(Ic.check, size: 12, color: l.bg) : null,
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          style: Typo.sans(15, color: l.ink),
          decoration: const InputDecoration(hintText: 'Search apps'),
        ),
        const SizedBox(height: 8),
        // Fixed height, so the sheet doesn't jump when the list arrives.
        SizedBox(height: MediaQuery.sizeOf(context).height * .45, child: list),
        const SizedBox(height: 16),
        LedgerButton(
          label: _on.isEmpty
              ? 'Limit nothing'
              : 'Limit ${_on.length} ${_on.length == 1 ? 'app' : 'apps'}',
          filled: true,
          onPressed: all == null
              ? null
              : () => Navigator.pop(context, [
                  for (final a in all)
                    if (_on.contains(a.package)) LimitedApp(a.package, a.label),
                ]),
        ),
      ],
    );
  }
}

/// Shown until the app list arrives: a moving hairline over blank rows, so
/// the sheet reads as working rather than empty.
class _PickerLoading extends StatelessWidget {
  const _PickerLoading();

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    const widths = [.46, .3, .55, .38, .5, .26, .42];
    // Cut off at the list's height rather than overflowing it.
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        LinearProgressIndicator(
          minHeight: 1,
          color: l.ink,
          backgroundColor: l.line,
        ),
        const SizedBox(height: 10),
        Text('Reading your apps', style: Typo.mono(11.5, color: l.muted)),
        for (final w in widths)
          Container(
            height: 51,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: l.line)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: l.line,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: w,
                      child: Container(
                        height: 9,
                        decoration: BoxDecoration(
                          color: l.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon(this.package, {super.key});

  final String package;

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: SizedBox.square(
        dimension: 30,
        child: FutureBuilder<Uint8List?>(
          future: ScrollGuard.appIcon(package),
          initialData: ScrollGuard.cachedIcon(package),
          builder: (context, snap) => snap.data == null
              ? ColoredBox(color: l.line)
              : Image.memory(snap.data!, gaplessPlayback: true),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.label, this.onTap);

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
