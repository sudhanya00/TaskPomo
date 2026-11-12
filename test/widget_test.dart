import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskpomo/logic/insights.dart';
import 'package:taskpomo/logic/analytics.dart';
import 'package:taskpomo/logic/headline.dart';
import 'package:taskpomo/logic/streaks.dart';
import 'package:taskpomo/logic/paper.dart';
import 'package:taskpomo/logic/week.dart';
import 'package:taskpomo/models/models.dart';
import 'package:taskpomo/services/ai_recap.dart';
import 'package:taskpomo/state/timer_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskpomo/util/dates.dart';

// 2026-10-19 is a Monday.
Task task({
  Set<int> days = everyDay,
  int current = 0,
  int clean = 0,
  int best = 0,
  String lastChecked = '2026-10-18',
  String created = '2026-10-01',
  int target = 15,
}) => Task(
  id: 't',
  name: 'Read',
  icon: 'book',
  targetMinutes: target,
  days: days,
  createdDate: created,
  currentStreak: current,
  cleanStreak: clean,
  bestStreak: best,
  lastChecked: lastChecked,
);

DayLog done(String d) =>
    DayLog(taskId: 't', date: d, seconds: 900, completed: true);
DayLog frozen(String d) => DayLog(taskId: 't', date: d, frozen: true);

void main() {
  group('dates', () {
    test('arithmetic crosses months and years', () {
      expect(addDays('2026-12-31', 1), '2027-01-01');
      expect(addDays('2026-03-01', -1), '2026-02-28');
      expect(weekdayOf('2026-10-19'), 1);
      expect(weekStart('2026-10-25'), '2026-10-19');
      expect(daysBetween('2026-10-19', '2026-10-22').toList(), [
        '2026-10-19',
        '2026-10-20',
        '2026-10-21',
      ]);
    });
  });

  group('evaluateMissedDays', () {
    test('a missed due day breaks the streak without auto-freeze', () {
      final o = evaluateMissedDays(
        task: task(current: 5, clean: 5, best: 5),
        logsByDate: {'2026-10-19': done('2026-10-19')},
        today: '2026-10-21',
        pointsAvailable: 100,
        autoFreeze: false,
      );
      expect(o.missed, ['2026-10-20']);
      expect(o.streak.current, 0);
      expect(o.lostStreak, 5);
      expect(o.streak.lastChecked, '2026-10-20');
    });

    test(
      'auto-freeze spends points and keeps the streak but not the clean run',
      () {
        final o = evaluateMissedDays(
          task: task(current: 5, clean: 5),
          logsByDate: const {},
          today: '2026-10-20',
          pointsAvailable: freezeCostFor(15),
          autoFreeze: true,
        );
        expect(o.autoFrozen, ['2026-10-19']);
        expect(o.pointsSpent, freezeCostFor(15));
        expect(o.streak.current, 5);
        expect(o.streak.clean, 0);
      },
    );

    test('auto-freeze stops when points run out', () {
      final o = evaluateMissedDays(
        task: task(current: 3),
        logsByDate: const {},
        today: '2026-10-21',
        pointsAvailable: freezeCostFor(15) + 5,
        autoFreeze: true,
      );
      expect(o.autoFrozen, ['2026-10-19']);
      expect(o.missed, ['2026-10-20']);
      expect(o.streak.current, 0);
    });

    test('days that are not due are skipped', () {
      // Weekdays only; Sat 24 and Sun 25 missed is fine.
      final o = evaluateMissedDays(
        task: task(days: weekdays, current: 5, lastChecked: '2026-10-23'),
        logsByDate: const {},
        today: '2026-10-26',
        pointsAvailable: 0,
        autoFreeze: false,
      );
      expect(o.missed, isEmpty);
      expect(o.streak.current, 5);
      expect(o.streak.lastChecked, '2026-10-25');
    });

    test('pre-frozen day keeps the streak', () {
      final o = evaluateMissedDays(
        task: task(current: 4, clean: 4),
        logsByDate: {'2026-10-19': frozen('2026-10-19')},
        today: '2026-10-20',
        pointsAvailable: 0,
        autoFreeze: false,
      );
      expect(o.missed, isEmpty);
      expect(o.streak.current, 4);
      expect(o.streak.clean, 0);
    });

    test('a running session holds its start day open', () {
      final o = evaluateMissedDays(
        task: task(current: 2),
        logsByDate: const {},
        today: '2026-10-20',
        pointsAvailable: 0,
        autoFreeze: false,
        holdFrom: '2026-10-19',
      );
      expect(o.missed, isEmpty);
      expect(o.streak.lastChecked, '2026-10-18');
    });

    test('days before the task existed never count', () {
      final o = evaluateMissedDays(
        task: task(created: '2026-10-20', lastChecked: '2026-10-15'),
        logsByDate: const {},
        today: '2026-10-20',
        pointsAvailable: 0,
        autoFreeze: false,
      );
      expect(o.missed, isEmpty);
    });
  });

  group('completion and points', () {
    test('completion extends both streaks and pays by target', () {
      final o = applyCompletion(
        const StreakSnapshot(current: 9, clean: 9, best: 9, lastChecked: 'x'),
        120,
      );
      expect(o.streak.current, 10);
      expect(o.streak.best, 10);
      expect(o.points, 40);
      expect(o.bonus, 1 * 40);
    });

    test('points scale with effort', () {
      expect(pointValue(2), 1);
      expect(pointValue(5), 2);
      expect(pointValue(15), 5);
      expect(pointValue(30), 10);
      expect(pointValue(120), 40);
    });

    test(
      'freezes cost five days of points for short tasks, three for long',
      () {
        expect(freezeDays(5), 5);
        expect(freezeDays(2), 5);
        expect(freezeDays(120), closeTo(3, 1e-9));
        expect(freezeDays(240), closeTo(3, 1e-9));
        expect(freezeCostFor(5), 10);
        expect(freezeCostFor(120), 120);
        expect(freezeCostFor(30), greaterThan(freezeCostFor(15)));
      },
    );

    test('milestones', () {
      expect(milestoneBonus(9, 15), 0);
      expect(milestoneBonus(50, 15), greaterThan(milestoneBonus(20, 15)));
      expect(milestoneBonus(100, 15), greaterThan(milestoneBonus(50, 15)));
      expect(milestoneBonus(10, 120), greaterThan(milestoneBonus(10, 5)));
      expect(milestoneBonus(300, 15), greaterThan(0));
      expect(milestoneBonus(400, 15), greaterThan(0));
      // A year of milestones is about a tenth of a year of daily points.
      final year = [
        10,
        20,
        50,
        100,
        150,
        200,
        300,
        365,
      ].fold<int>(0, (s, d) => s + milestoneBonus(d, 120));
      expect(year, 38 * pointValue(120));
      expect(milestoneBonus(365, 120) / freezeCostFor(120), lessThan(4));
      expect(milestoneBonus(301, 15), 0);
    });
  });

  group('headline', () {
    final t = task(target: 30);
    Headline at(
      int hour, {
      Map<String, DayLog> logs = const {},
      List<Task>? tasks,
    }) => headlineFor(
      tasks: tasks ?? [t],
      todayLogs: logs,
      today: '2026-10-21',
      now: DateTime(2026, 10, 21, hour),
    );

    test('counts what is left in words', () {
      expect(at(9).line, 'One left today.');
      expect(at(9).aside, 'Thirty minutes.');
      expect(at(22).aside, 'Thirty minutes, before midnight.');
      expect(at(9, logs: {'t': done('2026-10-21')}).line, 'All done today.');
      expect(at(9, tasks: const []).line, 'Start with one small thing.');
    });

    test('rest day', () {
      final h = headlineFor(
        tasks: [task(days: weekdays)],
        todayLogs: const {},
        today: '2026-10-24',
        now: DateTime(2026, 10, 24, 10),
      );
      expect(h.line, 'Nothing due today.');
    });

    test('number and duration words', () {
      expect(numberWords(17), 'seventeen');
      expect(numberWords(42), 'forty-two');
      expect(numberWords(120), '120');
      expect(durationWords(1), 'one minute');
      expect(durationWords(60), 'an hour');
      expect(durationWords(130), 'two hours and ten minutes');
    });
  });

  test('week cells fill by share of work done', () {
    // Week of Mon 19 Oct; today is Thu 22. A 30-min and a 10-min weekday task.
    final a = task(days: weekdays, target: 30);
    final b = Task(
      id: 'b',
      name: 'Short',
      icon: 'pen',
      targetMinutes: 10,
      days: weekdays,
      createdDate: '2026-10-01',
    );
    final cells = weekCells(
      tasks: [a, b],
      logs: [
        done('2026-10-19'),
        DayLog(taskId: 'b', date: '2026-10-19', seconds: 600, completed: true),
        DayLog(taskId: 'b', date: '2026-10-20', seconds: 600, completed: true),
        frozen('2026-10-21'),
        DayLog(taskId: 't', date: '2026-10-22', seconds: 900),
      ],
      today: '2026-10-22',
    );
    expect(cells[0], const DayCell(DayKind.past, 1)); // both done
    expect(cells[1], const DayCell(DayKind.past, .25)); // only the 10-min one
    expect(cells[2], const DayCell(DayKind.past, .75)); // 30-min frozen
    expect(cells[3], const DayCell(DayKind.today, 15 / 40));
    expect(cells[4].kind, DayKind.future);
  });

  group('paper age', () {
    final t = task(target: 30);
    double at(int hour, [Map<String, DayLog> logs = const {}]) => paperAge(
      tasks: [t],
      todayLogs: logs,
      today: '2026-10-21',
      now: DateTime(2026, 10, 21, hour),
    );

    test('fresh in the morning, old at night with work left', () {
      expect(at(8), 0);
      expect(at(18), closeTo(.6, 1e-9));
      expect(
        at(23, {'t': DayLog(taskId: 't', date: '2026-10-21', seconds: 900)}),
        closeTo(14 / 15 * .5, 1e-9),
      );
    });

    test('fresh again once done', () {
      expect(at(23, {'t': done('2026-10-21')}), 0);
    });
  });

  test('insights add up per period', () {
    final t = task();
    final logs = [
      DayLog(taskId: 't', date: '2026-10-21', seconds: 600, completed: true),
      DayLog(taskId: 't', date: '2026-10-02', seconds: 1200, completed: true),
      DayLog(taskId: 't', date: '2026-01-05', seconds: 3000),
    ];
    final i = computeInsights([t], logs, '2026-10-21');
    final s = i.tasks.single;
    expect(s.weekSec, 600);
    expect(s.monthSec, 1800);
    expect(s.yearSec, 4800);
    expect(s.bestDay, '2026-01-05');
    expect(i.last7.last.value, 600);
  });

  group('timer rounds', () {
    Future<TimerController> controller() async {
      SharedPreferences.setMockInitialValues({});
      return TimerController(await SharedPreferences.getInstance());
    }

    test('short tasks get a round as long as their target', () async {
      final timer = await controller();
      timer.start(task(target: 15));
      expect(timer.roundMinutes, 15);
      expect(timer.pomodoroLeft.inMinutes, inInclusiveRange(14, 15));
      timer.stop();
      timer.dispose();
    });

    test('time in other apps comes off once, and answers apply', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final timer = await controller();
      // The guard's channel, answering with what it noted.
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('taskpomo/guard'),
        (call) async => call.method == 'takeSessionLog'
            ? [
                {
                  'package': 'wa',
                  'label': 'WhatsApp',
                  'kind': 'social',
                  'ms': 3 * 60000,
                },
                {
                  'package': 'yt',
                  'label': 'YouTube',
                  'kind': 'video',
                  'ms': 6 * 60000,
                },
              ]
            : null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('taskpomo/guard'),
          null,
        ),
      );
      timer.start(task(target: 30));
      timer.pause();
      timer.session!.accumulatedMs = 31 * 60000;

      final dropped = await timer.collectAway();
      expect(dropped.map((a) => a.label), ['WhatsApp']);
      expect(timer.focus.inMinutes, 28);
      expect(timer.session!.unsure.keys, ['yt']);

      // Pausing and resuming folds the timer, not the counted time.
      timer.resume();
      timer.pause();
      expect(timer.focus.inMinutes, 28);

      timer.decide(counted: {'yt'}, remember: {'yt'});
      expect(timer.focus.inMinutes, 28);
      expect(timer.allowedApps('t'), {'yt': 'YouTube'});

      final done = timer.stop()!;
      expect(done.seconds ~/ 60, 28);
      expect(done.notCountedSeconds, 180);
      timer.dispose();
    });

    test('long tasks use the normal pomodoro length', () async {
      final timer = await controller();
      timer.start(task(target: 120));
      expect(timer.roundMinutes, 25);
      timer.stop();
      timer.dispose();
    });
  });

  test('recap only sees worked-on tasks and their notes', () {
    final workout = Task(
      id: 'w',
      name: 'Exercise or Run',
      icon: 'barbell',
      targetMinutes: 20,
      days: everyDay,
      createdDate: '2026-10-01',
    );
    final idle = Task(
      id: 'g',
      name: 'Learn German',
      icon: 'translate',
      targetMinutes: 15,
      days: everyDay,
      createdDate: '2026-10-01',
    );
    final insights = computeInsights(
      [workout, idle],
      [DayLog(taskId: 'w', date: '2026-10-21', seconds: 1320, completed: true)],
      '2026-10-21',
    );
    final notes = {
      'w': [
        const Session(
          id: 's',
          taskId: 'w',
          date: '2026-10-21',
          startedAt: 0,
          seconds: 1320,
          note: 'Home workout: squats and push-ups',
        ),
      ],
    };
    final input = recapInput(insights, notes);
    expect(input.map((e) => e['skill']), ['Exercise or Run']);
    expect('${input.single['notesThisWeek']}', contains('squats'));
    expect(
      recapPrompt(insights, notes),
      contains('Never guess what the user did'),
    );
  });

  group('analytics', () {
    // Weekdays-only task over Mon 5 – Sun 18 Oct 2026; today is Fri 16.
    final work = Task(
      id: 'w',
      name: 'Work',
      icon: 'briefcase',
      targetMinutes: 60,
      days: weekdays,
      createdDate: '2026-10-01',
    );
    final read = Task(
      id: 'r',
      name: 'Read',
      icon: 'book',
      targetMinutes: 10,
      days: everyDay,
      createdDate: '2026-10-01',
    );
    DayLog log(
      String id,
      String d,
      int min, {
      bool done = true,
      bool frozen = false,
    }) => DayLog(
      taskId: id,
      date: d,
      seconds: min * 60,
      completed: done,
      frozen: frozen,
    );
    final days = [
      log('w', '2026-10-05', 60),
      log('w', '2026-10-06', 70),
      log('w', '2026-10-07', 20, done: false),
      log('w', '2026-10-08', 60),
      log('w', '2026-10-09', 0, done: false, frozen: true),
      // weekend: work not due, run continues
      log('w', '2026-10-12', 60),
      log('w', '2026-10-13', 60),
      log('w', '2026-10-14', 60),
      log('w', '2026-10-15', 60),
      // Fri 16 (today): nothing yet
      for (final d in [
        '05',
        '06',
        '07',
        '08',
        '09',
        '10',
        '11',
        '12',
        '13',
        '14',
        '15',
      ])
        log('r', '2026-10-$d', 12),
    ];
    final sessions = [
      Session(
        id: '1',
        taskId: 'w',
        date: '2026-10-05',
        startedAt: DateTime(2026, 10, 5, 9, 5).millisecondsSinceEpoch,
        seconds: 1800,
      ),
      Session(
        id: '2',
        taskId: 'w',
        date: '2026-10-05',
        startedAt: DateTime(2026, 10, 5, 9, 40).millisecondsSinceEpoch,
        seconds: 1800,
      ),
      Session(
        id: '3',
        taskId: 'r',
        date: '2026-10-05',
        startedAt: DateTime(2026, 10, 5, 22).millisecondsSinceEpoch,
        seconds: 720,
      ),
    ];
    final a = analyze(
      tasks: [work, read],
      days: days,
      sessions: sessions,
      range: const DateRange('2026-10-05', '2026-10-16'),
      today: '2026-10-16',
    );

    test('runs skip rest days, freezes keep them, today is not a miss', () {
      expect(a.runs[0].map((r) => r.length), [2, 6]);
      expect(a.runs[0].last.start, '2026-10-08');
      expect(a.runs[0].last.end, '2026-10-15');
      expect(a.bestRun, [6, 11]);
      expect(a.completion[0], 8 / 9);
      expect(a.dueDays, [9, 11]);
    });

    test('totals, median, focus and buckets', () {
      expect(a.sessions, 3);
      expect(a.medianSessionMin, 30);
      expect(a.focus[0][9], 60);
      expect(a.focus[0][22], 12);
      expect(peakStartHour(a), 8);
      expect(a.buckets.length, 12); // daily buckets for a short range
      expect(a.buckets.first.perTask, [3600, 720]);
      expect(a.bestDay, '2026-10-06');
    });

    test('habits together only counts days both are due', () {
      // On days Work was done, Read was always done too.
      expect(a.together[0][1], 1);
      // On days Read was done and Work was due, Work was done 7 of 9 times.
      expect(a.together[1][0], closeTo(7 / 9, 1e-9));
      expect(a.together[0][0].isNaN, isTrue);
    });

    test('months', () {
      expect(DateRange.month('2026-02').to, '2026-02-28');
      expect(previousMonth('2026-01'), '2025-12');
      expect(finishedMonths('2026-08-14', '2026-10-24'), [
        '2026-09',
        '2026-08',
      ]);
      expect(monthName('2026-09'), 'September');
      // Ranges never start before the first task.
      expect(rangeFor(Span.year, '2026-10-24', '2026-10-24').days, 1);
      expect(
        rangeFor(Span.week, '2026-10-24', '2026-01-01').from,
        '2026-10-19',
      );
      expect(rangeFor(Span.all, '2026-10-24', '2026-08-02').from, '2026-08-02');
    });
  });
}
