import 'package:flutter_test/flutter_test.dart';
import 'package:taskpomo/logic/csv_export.dart';
import 'package:taskpomo/models/models.dart';

void main() {
  test('cells are quoted only when needed', () {
    expect(csvCell('plain'), 'plain');
    expect(csvCell('a, b'), '"a, b"');
    expect(csvCell('say "hi"'), '"say ""hi"""');
    expect(csvCell('two\nlines'), '"two\nlines"');
    expect(csvCell(null), '');
    expect(
      csv([
        ['a', 1],
        ['b, c', true],
      ]),
      'a,1\r\n"b, c",true\r\n',
    );
  });

  test('timestamps carry the UTC offset', () {
    final t = DateTime(2026, 10, 23, 22, 4, 10);
    expect(
      isoWithOffset(t),
      matches(RegExp(r'^2026-10-23T22:04:10[+-]\d\d:\d\d$')),
    );
  });

  test('days.csv is the full ledger, including rest and missed days', () {
    final t = Task(
      id: 'r',
      name: 'Read',
      icon: 'book',
      targetMinutes: 15,
      days: weekdays,
      createdDate: '2026-10-23',
    );
    final out = buildExport(
      tasks: [t],
      days: [
        const DayLog(
          taskId: 'r',
          date: '2026-10-23',
          seconds: 1170,
          completed: true,
        ),
      ],
      sessions: [
        Session(
          id: 's1',
          taskId: 'r',
          date: '2026-10-23',
          startedAt: DateTime(2026, 10, 23, 22).millisecondsSinceEpoch,
          seconds: 1170,
          note: 'Chapter 4, "Piranesi"',
        ),
      ],
      ledger: const [LedgerEntry(amount: 5, reason: 'Read done', at: 0)],
      today: '2026-10-26',
    );
    expect(
      out.keys,
      containsAll([
        'README.txt',
        'tasks.csv',
        'days.csv',
        'sessions.csv',
        'points.csv',
      ]),
    );
    final dayLines = out['days.csv']!.trim().split('\r\n');
    expect(dayLines.length, 1 + 4); // header + Fri, Sat, Sun, Mon
    expect(dayLines[1], 'r,Read,2026-10-23,Fri,true,15,19.5,true,false,');
    expect(dayLines[2], startsWith('r,Read,2026-10-24,Sat,false,15,0.0,false'));
    expect(dayLines[4], startsWith('r,Read,2026-10-26,Mon,true,15,0.0,false'));
    expect(out['sessions.csv'], contains('"Chapter 4, ""Piranesi"""'));
    expect(out['sessions.csv'], contains(',timer,'));
    expect(out['points.csv'], contains(',5,5,Read done'));
    expect(out['tasks.csv'], contains('Mon;Tue;Wed;Thu;Fri'));
  });
}
