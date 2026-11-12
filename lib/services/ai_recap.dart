import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';

import '../logic/insights.dart';
import '../models/models.dart';

/// A short recap of your progress written by Gemini through
/// Firebase AI Logic. Cached per week so it costs one call a week unless you
/// ask for a fresh one.
class Recap {
  const Recap({
    required this.headline,
    required this.lines,
    required this.week,
  });

  final String headline;

  /// Skill name -> one fun line about it.
  final Map<String, String> lines;
  final String week;

  factory Recap.fromMap(Map<String, dynamic> m) => Recap(
    headline: m['headline'] as String? ?? '',
    lines: Map<String, String>.from(m['lines'] as Map? ?? const {}),
    week: m['week'] as String? ?? '',
  );
}

class AiRecap {
  AiRecap(this._doc);

  final DocumentReference<Map<String, dynamic>> _doc;

  /// Cheap and quick is plenty for a few lines of text.
  static const model = 'gemini-3.5-flash-lite';

  Stream<Recap?> cached() =>
      _doc.snapshots().map((s) => s.exists ? Recap.fromMap(s.data()!) : null);

  Future<Recap> generate(
    Insights insights,
    String week,
    Map<String, List<Session>> notesByTask,
  ) async {
    final prompt = recapPrompt(insights, notesByTask);
    final ai = FirebaseAI.googleAI().generativeModel(
      model: model,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.6,
      ),
    );
    final res = await ai.generateContent([Content.text(prompt)]);
    final text = res.text;
    if (text == null || text.isEmpty) throw StateError('Empty response');
    final json = jsonDecode(text) as Map<String, dynamic>;
    final recap = Recap(
      headline: json['headline'] as String? ?? '',
      lines: {
        for (final e in (json['lines'] as Map? ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
      week: week,
    );
    await _doc.set({
      'headline': recap.headline,
      'lines': recap.lines,
      'week': week,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    return recap;
  }
}

/// What the model sees: this week's numbers and the user's own notes for the
/// tasks they actually worked on.
List<Map<String, Object?>> recapInput(
  Insights insights,
  Map<String, List<Session>> notesByTask,
) => [
  for (final t in insights.tasks)
    if (t.weekSec > 0)
      {
        ...t.toJson(),
        'notesThisWeek': [
          for (final n in notesByTask[t.task.id] ?? const <Session>[])
            if (n.note.isNotEmpty)
              {'date': n.date, 'minutes': n.seconds ~/ 60, 'note': n.note},
        ],
      },
];

String recapPrompt(Insights insights, Map<String, List<Session>> notesByTask) {
  final input = recapInput(insights, notesByTask);
  return '''
You write the short weekly note in a quiet habit-tracking app. Plain, warm,
specific. No emoji, no exclamation marks, no hype, no clichés.

This week's practice, as JSON. Only skills with time this week are listed.
"notesThisWeek" are the user's own words about what they did in a session.
${jsonEncode(input)}

Rules:
- Base every claim on the numbers or the notes. Never guess what the user did
  from the skill's name: a skill called "Exercise or Run" does not mean they
  ran, and "Read" does not say what they read.
- If a skill has notes, use them: mention what they actually did.
- If a skill has no notes, talk only about the time and the streak or
  consistency, and say nothing about the activity's content.
- Rough conversions are fine only when the notes make them true (e.g. pages
  read if they mention pages). Otherwise don't convert.
- Skip skills not in the list. Don't mention what wasn't done.

Write:
- "headline": one sentence about the week as a whole.
- "lines": one sentence per listed skill, keyed by its exact "skill" value.
Each sentence under 25 words.
Return JSON only: {"headline": string, "lines": {skill: string}}''';
}

/// Plain-language reason for a failed AI call.
String describeAiError(Object e) {
  final msg = '$e';
  if (msg.contains('App Check')) {
    return 'Couldn’t write it: App Check is blocking requests. Unenforce App Check for Firebase AI Logic in the Firebase console.';
  }
  if (msg.toLowerCase().contains('template')) {
    return 'Couldn’t write it: template-only mode is on for Firebase AI Logic. Turn it off in the Firebase console.';
  }
  return 'Couldn’t write it. ${msg.length > 160 ? '${msg.substring(0, 160)}…' : msg}';
}

/// Sends [prompt] and returns the model's JSON object.
Future<Map<String, dynamic>> askJson(String prompt) async {
  final ai = FirebaseAI.googleAI().generativeModel(
    model: AiRecap.model,
    generationConfig: GenerationConfig(
      responseMimeType: 'application/json',
      temperature: 0.6,
    ),
  );
  final res = await ai.generateContent([Content.text(prompt)]);
  final text = res.text;
  if (text == null || text.isEmpty) throw StateError('Empty response');
  return jsonDecode(text) as Map<String, dynamic>;
}

/// A cached note (monthly recap, Wrapped), stored once generated.
class AiNote {
  AiNote(this._doc);

  final DocumentReference<Map<String, dynamic>> _doc;

  Stream<Map<String, dynamic>?> cached() =>
      _doc.snapshots().map((s) => s.exists ? s.data() : null);

  Future<Map<String, dynamic>> write(String prompt) async {
    final json = await askJson(prompt);
    await _doc.set({...json, 'at': DateTime.now().millisecondsSinceEpoch});
    return json;
  }
}

const _rules = '''
Rules:
- Base every claim on the numbers or the user's notes. Never guess what they
  did from a task's name: "Exercise or Run" does not mean they ran, and
  "Read" does not say what they read.
- Use the notes for specifics. With no notes for a task, talk only about time,
  consistency and streaks.
- Skip tasks with no time. Plain, warm, specific. No emoji, no exclamation
  marks, no hype, no clichés.''';

/// Notes worth sending: the most recent [max], oldest first.
List<Map<String, Object>> _notes(
  List<Session> sessions,
  Map<String, String> names, {
  int max = 80,
}) {
  final withNotes = sessions.where((s) => s.note.isNotEmpty).toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final keep = withNotes.length > max
      ? withNotes.sublist(withNotes.length - max)
      : withNotes;
  return [
    for (final s in keep)
      {
        'task': names[s.taskId] ?? '',
        'date': s.date,
        'minutes': s.seconds ~/ 60,
        'note': s.note,
      },
  ];
}

String monthPrompt({
  required String monthLabel,
  required List<Map<String, Object?>> perTask,
  required Map<String, Object?> totals,
  required List<Session> sessions,
  required Map<String, String> names,
}) =>
    '''
You write the end-of-month page in a quiet habit-tracking app.

Month: $monthLabel
Totals: ${jsonEncode(totals)}
Per task (minutes, due days done, change in minutes from the previous month):
${jsonEncode(perTask)}
The user's session notes this month:
${jsonEncode(_notes(sessions, names))}
$_rules

Write:
- "headline": one sentence on the month as a whole, under 22 words.
- "body": two to four sentences with specifics from the notes and numbers.
Return JSON only: {"headline": string, "body": string}''';

String wrappedPrompt({
  required int year,
  required List<Map<String, Object?>> perTask,
  required Map<String, Object?> totals,
  required List<Session> sessions,
  required Map<String, String> names,
}) =>
    '''
You write the last page of a year-in-review ("Wrapped") in a quiet
habit-tracking app.

Year: $year
Totals: ${jsonEncode(totals)}
Per task: ${jsonEncode(perTask)}
A sample of the user's session notes across the year:
${jsonEncode(_notes(sessions, names, max: 150))}
$_rules

Write:
- "line": one or two sentences, under 35 words, naming what the year added up
  to, using concrete things from the notes where there are any.
- "sub": one short sentence to close the year.
Return JSON only: {"line": string, "sub": string}''';
