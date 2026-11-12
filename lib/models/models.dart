import '../util/dates.dart';

const everyDay = {1, 2, 3, 4, 5, 6, 7};
const weekdays = {1, 2, 3, 4, 5};
const weekends = {6, 7};

String describeDays(Set<int> days) {
  if (days.length == 7) return 'Every day';
  if (days.length == 5 && days.containsAll(weekdays)) return 'Weekdays';
  if (days.length == 2 && days.containsAll(weekends)) return 'Weekends';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return (days.toList()..sort()).map((d) => names[d - 1]).join(', ');
}

class StreakSnapshot {
  const StreakSnapshot({
    required this.current,
    required this.clean,
    required this.best,
    required this.lastChecked,
  });

  /// Consecutive due days kept (completed or frozen).
  final int current;

  /// Consecutive due days completed without using a freeze. Milestone bonuses
  /// are paid on this one.
  final int clean;
  final int best;

  /// Last day whose outcome has been settled (missed / frozen / done).
  final String lastChecked;
}

class Task {
  Task({
    required this.id,
    required this.name,
    required this.icon,
    required this.targetMinutes,
    required this.days,
    required this.createdDate,
    this.createdAt = 0,
    this.currentStreak = 0,
    this.cleanStreak = 0,
    this.bestStreak = 0,
    String? lastChecked,
    this.totalSeconds = 0,
    this.lostStreak = 0,
    this.lostOn,
    this.archived = false,
  }) : lastChecked = lastChecked ?? addDays(createdDate, -1);

  final String id;
  final String name;

  /// Key into the line-icon set (lib/ui/icons.dart).
  final String icon;
  final int targetMinutes;
  final Set<int> days;
  final String createdDate;
  final int createdAt;
  final int currentStreak;
  final int cleanStreak;
  final int bestStreak;
  final String lastChecked;
  final int totalSeconds;

  /// Length of the most recently broken streak and the day it broke.
  final int lostStreak;
  final String? lostOn;
  final bool archived;

  bool isDueOn(String date) =>
      days.contains(weekdayOf(date)) && date.compareTo(createdDate) >= 0;

  StreakSnapshot get streak => StreakSnapshot(
    current: currentStreak,
    clean: cleanStreak,
    best: bestStreak,
    lastChecked: lastChecked,
  );

  factory Task.fromMap(String id, Map<String, dynamic> m) {
    final created = m['createdDate'] as String? ?? todayKey();
    return Task(
      id: id,
      name: m['name'] as String? ?? 'Untitled',
      icon: m['icon'] as String? ?? _iconFromEmoji(m['emoji'] as String?),
      targetMinutes: (m['targetMinutes'] as num?)?.toInt() ?? 15,
      days: ((m['days'] as List?) ?? everyDay.toList())
          .map((e) => (e as num).toInt())
          .toSet(),
      createdDate: created,
      createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
      currentStreak: (m['currentStreak'] as num?)?.toInt() ?? 0,
      cleanStreak: (m['cleanStreak'] as num?)?.toInt() ?? 0,
      bestStreak: (m['bestStreak'] as num?)?.toInt() ?? 0,
      lastChecked: m['lastChecked'] as String? ?? addDays(created, -1),
      totalSeconds: (m['totalSeconds'] as num?)?.toInt() ?? 0,
      lostStreak: (m['lostStreak'] as num?)?.toInt() ?? 0,
      lostOn: m['lostOn'] as String?,
      archived: m['archived'] as bool? ?? false,
    );
  }

  /// Fields the editor owns. Streak and totals are only written by the
  /// streak engine.
  Map<String, dynamic> editableFields() => {
    'name': name,
    'icon': icon,
    'targetMinutes': targetMinutes,
    'days': days.toList()..sort(),
  };
}

/// Tasks made before line icons existed stored an emoji.
String _iconFromEmoji(String? e) => switch (e) {
  '📚' || '📖' => 'book',
  '🎸' => 'guitar',
  '🎹' => 'piano',
  '🎧' => 'headphones',
  '💻' => 'code',
  '🏃' => 'run',
  '🏋️' => 'barbell',
  '🧘' => 'lotus',
  '✍️' || '📝' => 'pen',
  '🎨' => 'brush',
  '🗣️' => 'translate',
  '🧠' => 'brain',
  '🌱' => 'leaf',
  '📷' => 'camera',
  '🍳' => 'chef',
  '🌍' => 'globe',
  _ => 'circle',
};

class DayLog {
  const DayLog({
    required this.taskId,
    required this.date,
    this.seconds = 0,
    this.completed = false,
    this.frozen = false,
    this.freezePaid,
  });

  final String taskId;
  final String date;
  final int seconds;
  final bool completed;
  final bool frozen;

  /// Points spent freezing this day, so a refund returns exactly that.
  final int? freezePaid;

  static String idFor(String taskId, String date) => '${taskId}_$date';

  factory DayLog.fromMap(Map<String, dynamic> m) => DayLog(
    taskId: m['taskId'] as String,
    date: m['date'] as String,
    seconds: (m['seconds'] as num?)?.toInt() ?? 0,
    completed: m['completed'] as bool? ?? false,
    frozen: m['frozen'] as bool? ?? false,
    freezePaid: (m['freezePaid'] as num?)?.toInt(),
  );
}

/// One logged stretch of time, from the timer or entered by hand.
class Session {
  const Session({
    required this.id,
    required this.taskId,
    required this.date,
    required this.startedAt,
    required this.seconds,
    this.manual = false,
    this.note = '',
  });

  final String id;
  final String taskId;
  final String date;
  final int startedAt;
  final int seconds;
  final bool manual;

  /// What was actually done, in the user's words. Optional.
  final String note;

  factory Session.fromMap(String id, Map<String, dynamic> m) => Session(
    id: id,
    taskId: m['taskId'] as String,
    date: m['date'] as String,
    startedAt: (m['startedAt'] as num?)?.toInt() ?? 0,
    seconds: (m['seconds'] as num?)?.toInt() ?? 0,
    manual: m['manual'] as bool? ?? false,
    note: m['note'] as String? ?? '',
  );
}

class Profile {
  const Profile({
    this.points = 0,
    this.autoFreeze = true,
    this.focusMinutes = 25,
    this.breakMinutes = 5,
    this.longBreakMinutes = 15,
    this.reminderHour = 20,
    this.scrollReserve,
    this.scrollApps = const [],
  });

  final int points;

  /// Spend points automatically when a due day is missed.
  final bool autoFreeze;
  final int focusMinutes;
  final int breakMinutes;
  final int longBreakMinutes;

  /// Hour of the evening nudge when tasks are left; -1 turns it off.
  final int reminderHour;

  /// Points scrolling can't spend. Null means the default (logic/scroll.dart).
  final int? scrollReserve;

  /// Apps whose time is paid for in points.
  final List<LimitedApp> scrollApps;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
    points: (m['points'] as num?)?.toInt() ?? 0,
    autoFreeze: m['autoFreeze'] as bool? ?? true,
    focusMinutes: (m['focusMinutes'] as num?)?.toInt() ?? 25,
    breakMinutes: (m['breakMinutes'] as num?)?.toInt() ?? 5,
    longBreakMinutes: (m['longBreakMinutes'] as num?)?.toInt() ?? 15,
    reminderHour: (m['reminderHour'] as num?)?.toInt() ?? 20,
    scrollReserve: (m['scrollReserve'] as num?)?.toInt(),
    scrollApps: [
      for (final a in (m['scrollApps'] as List?) ?? const [])
        LimitedApp.fromMap(Map<String, dynamic>.from(a as Map)),
    ],
  );
}

/// An app whose foreground time costs points.
class LimitedApp {
  const LimitedApp(this.package, this.label);

  final String package;
  final String label;

  factory LimitedApp.fromMap(Map<String, dynamic> m) =>
      LimitedApp(m['package'] as String, m['label'] as String? ?? '');

  Map<String, String> toMap() => {'package': package, 'label': label};
}

class LedgerEntry {
  const LedgerEntry({
    required this.amount,
    required this.reason,
    required this.at,
  });

  final int amount;
  final String reason;
  final int at;

  factory LedgerEntry.fromMap(Map<String, dynamic> m) => LedgerEntry(
    amount: (m['amount'] as num?)?.toInt() ?? 0,
    reason: m['reason'] as String? ?? '',
    at: (m['at'] as num?)?.toInt() ?? 0,
  );
}
