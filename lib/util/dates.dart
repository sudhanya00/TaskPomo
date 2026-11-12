/// Days are stored as local-calendar keys like `2026-10-23` so a day means
/// the same thing on every device regardless of time zone.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

String _two(int n) => n.toString().padLeft(2, '0');

DateTime parseKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String todayKey([DateTime? now]) => dateKey(now ?? DateTime.now());

/// Calendar arithmetic through the DateTime constructor, which is safe across
/// DST changes (unlike adding Duration(days: n)).
String addDays(String key, int n) {
  final d = parseKey(key);
  return dateKey(DateTime(d.year, d.month, d.day + n));
}

/// 1 = Monday … 7 = Sunday, same as [DateTime.weekday].
int weekdayOf(String key) => parseKey(key).weekday;

/// Keys from [from] (inclusive) up to [to] (exclusive).
Iterable<String> daysBetween(String from, String to) sync* {
  for (var d = from; d.compareTo(to) < 0; d = addDays(d, 1)) {
    yield d;
  }
}

/// Monday of the week containing [key].
String weekStart(String key) => addDays(key, 1 - weekdayOf(key));

String monthStart(String key) => '${key.substring(0, 7)}-01';

String yearStart(String key) => '${key.substring(0, 4)}-01-01';

/// "1h 20m", "45m", "0m".
String formatMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// "12:05" or "1:02:09".
String formatClock(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}
