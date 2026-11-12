import '../models/models.dart';

/// The two-line sentence at the top of Today: a plain statement, then a
/// quieter italic line. "Two left today. / Seventeen minutes."
class Headline {
  const Headline(this.line, this.aside);

  final String line;
  final String aside;
}

const _ones = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const _tens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

/// 0..99 in words; larger numbers stay as digits.
String numberWords(int n) {
  if (n < 0 || n > 99) return '$n';
  if (n < 20) return _ones[n];
  final t = _tens[n ~/ 10], o = n % 10;
  return o == 0 ? t : '$t-${_ones[o]}';
}

String capitalise(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "seventeen minutes", "an hour", "two hours and ten minutes".
String durationWords(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final hours = h == 0
      ? ''
      : h == 1
      ? 'an hour'
      : '${numberWords(h)} hours';
  final mins = m == 1 ? 'one minute' : '${numberWords(m)} minutes';
  if (h == 0) return mins;
  if (m == 0) return hours;
  return '$hours and $mins';
}

Headline headlineFor({
  required List<Task> tasks,
  required Map<String, DayLog> todayLogs,
  required String today,
  required DateTime now,
}) {
  if (tasks.isEmpty) {
    return const Headline(
      'Start with one small thing.',
      'Ten minutes is plenty.',
    );
  }
  final due = tasks.where((t) => t.isDueOn(today)).toList();
  if (due.isEmpty) {
    return const Headline('Nothing due today.', 'Rest is part of it.');
  }
  final left = due.where((t) {
    final log = todayLogs[t.id];
    return !(log?.completed ?? false) && !(log?.frozen ?? false);
  }).toList();
  if (left.isEmpty) {
    return const Headline('All done today.', 'See you tomorrow.');
  }

  final minsLeft = left.fold<int>(0, (sum, t) {
    final done = (todayLogs[t.id]?.seconds ?? 0) ~/ 60;
    return sum + (t.targetMinutes - done).clamp(0, t.targetMinutes);
  });
  final line = left.length == 1
      ? 'One left today.'
      : '${capitalise(numberWords(left.length))} left today.';
  final time = capitalise(durationWords(minsLeft));
  if (now.hour >= 21) return Headline(line, '$time, before midnight.');
  return Headline(line, '$time.');
}
