import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repo.dart';
import '../logic/csv_export.dart';
import '../ui/kit.dart';
import '../util/dates.dart';

/// Writes the CSV export to a temporary folder and opens the share sheet,
/// so it can go to Drive, a computer, email or an agent.
Future<void> exportCsv(BuildContext context, Repo repo) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  toast(context, 'Preparing your export…');
  try {
    final today = todayKey();
    final (tasks, days, sessions, ledger) = await (
      repo.allTasks(),
      repo.allDays(),
      repo.allSessions(),
      repo.allLedger(),
    ).wait;
    final files = buildExport(
      tasks: tasks,
      days: days,
      sessions: sessions,
      ledger: ledger,
      today: today,
    );
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/taskpomo-export-$today');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final paths = <XFile>[];
    for (final e in files.entries) {
      final f = File('${dir.path}/${e.key}');
      await f.writeAsString(e.value);
      paths.add(
        XFile(
          f.path,
          mimeType: e.key.endsWith('.csv') ? 'text/csv' : 'text/plain',
        ),
      );
    }
    messenger?.hideCurrentSnackBar();
    await SharePlus.instance.share(
      ShareParams(files: paths, subject: 'TaskPomo export $today'),
    );
  } catch (e) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}
