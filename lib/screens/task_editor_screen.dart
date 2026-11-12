import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/scroll_guard.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../util/dates.dart';
import 'session_check_sheet.dart';

const _targets = [5, 10, 15, 20, 30, 45, 60, 90, 120];

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({super.key, this.task});

  final Task? task;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final _name = TextEditingController(text: widget.task?.name ?? '');
  late String _icon = widget.task?.icon ?? 'book';
  late int _target = widget.task?.targetMinutes ?? 15;
  late Set<int> _days = {...(widget.task?.days ?? everyDay)};

  bool get _editing => widget.task != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _days.isEmpty) return;
    final repo = context.read<AppController>().repo;
    final t = Task(
      id: widget.task?.id ?? '',
      name: name,
      icon: _icon,
      targetMinutes: _target,
      days: _days,
      createdDate: widget.task?.createdDate ?? todayKey(),
    );
    _editing ? repo.updateTask(t) : repo.createTask(t);
    Navigator.pop(context);
  }

  Future<void> _archive() async {
    final ok = await confirm(
      context,
      title: 'Remove ${widget.task!.name}?',
      body: 'It leaves your lists. The time you logged stays in your history.',
      yes: 'Remove',
    );
    if (!ok || !mounted) return;
    context.read<AppController>().repo.archiveTask(widget.task!.id);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _customTarget() async {
    final c = TextEditingController(text: '$_target');
    final v = await showLedgerSheet<int>(
      context,
      title: 'Daily target',
      child: Builder(
        builder: (ctx) {
          final l = Ledger.of(ctx);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: c,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: Typo.serif(40, color: l.ink),
                decoration: InputDecoration(
                  suffixText: 'minutes',
                  suffixStyle: Typo.mono(12, color: l.muted),
                ),
              ),
              const SizedBox(height: 22),
              LedgerButton(
                label: 'Set',
                filled: true,
                onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)),
              ),
            ],
          );
        },
      ),
    );
    if (v != null && v > 0 && v <= 24 * 60) setState(() => _target = v);
  }

  Widget _toggle(
    String label,
    bool on,
    VoidCallback onTap, {
    double minWidth = 0,
  }) {
    final l = Ledger.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: BoxConstraints(minWidth: minWidth),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on ? l.ink : null,
          border: Border.all(color: on ? l.ink : l.line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Typo.mono(12.5, color: on ? l.bg : l.ink),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    const presets = {
      'Every day': everyDay,
      'Weekdays': weekdays,
      'Weekends': weekends,
    };

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Ic.close, color: l.ink, size: 22),
                  ),
                  const Spacer(),
                  if (_editing)
                    IconButton(
                      onPressed: _archive,
                      icon: Icon(Ic.trash, color: l.muted, size: 20),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
                children: [
                  Text(
                    _editing ? 'Edit task' : 'New task',
                    style: Typo.serif(44, color: l.ink),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _name,
                    autofocus: !_editing,
                    textCapitalization: TextCapitalization.sentences,
                    style: Typo.sans(20, weight: 500, color: l.ink),
                    decoration: const InputDecoration(
                      hintText: 'Read, practise scales, write…',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 30),
                  const Eyebrow('Icon'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final key in taskIcons.keys.where(
                        (k) => k != 'circle',
                      ))
                        GestureDetector(
                          onTap: () => setState(() => _icon = key),
                          child: IconTile(
                            taskIcons[key]!,
                            size: 42,
                            selected: key == _icon,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  const Eyebrow('Daily target'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in _targets)
                        _toggle(
                          formatMinutes(m),
                          _target == m,
                          () => setState(() => _target = m),
                          minWidth: 52,
                        ),
                      _toggle(
                        _targets.contains(_target)
                            ? 'Other'
                            : formatMinutes(_target),
                        !_targets.contains(_target),
                        _customTarget,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Split it across as many sessions as you like.',
                    style: Typo.sans(13, color: l.muted),
                  ),
                  const SizedBox(height: 30),
                  const Eyebrow('Days'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in presets.entries)
                        _toggle(
                          e.key,
                          _days.length == e.value.length &&
                              _days.containsAll(e.value),
                          () => setState(() => _days = {...e.value}),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        _toggle('MTWTFSS'[d - 1], _days.contains(d), () {
                          final next = {..._days};
                          if (!next.remove(d)) next.add(d);
                          if (next.isNotEmpty) setState(() => _days = next);
                        }, minWidth: 38),
                    ],
                  ),
                  if (_editing && ScrollGuard.supported) ...[
                    const SizedBox(height: 30),
                    AppsDuringTask(taskId: widget.task!.id),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: LedgerButton(
                label: _editing ? 'Save' : 'Create task',
                filled: true,
                onPressed: _name.text.trim().isEmpty ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
