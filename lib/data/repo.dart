import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../logic/streaks.dart';
import '../models/models.dart';
import '../util/dates.dart';

/// Firestore layout, everything under users/{uid}:
///   (doc)        profile: points, autoFreeze, pomodoro settings
///   tasks/{id}   the habit plus its streak counters
///   days/{taskId}_{date}  seconds logged, completed, frozen
///   sessions/{id}         one focus session or manual entry
///   ledger/{id}           points earned and spent
///   meta/recap            cached AI recap
///
/// Writes are batched and not awaited: Firestore applies them locally at
/// once (listeners update immediately) and syncs when online, so the app
/// works the same on a plane.
class Repo {
  Repo(this.uid);

  final String uid;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get userDoc =>
      _db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _tasks =>
      userDoc.collection('tasks');
  CollectionReference<Map<String, dynamic>> get _days =>
      userDoc.collection('days');
  CollectionReference<Map<String, dynamic>> get _sessions =>
      userDoc.collection('sessions');
  CollectionReference<Map<String, dynamic>> get _ledger =>
      userDoc.collection('ledger');
  DocumentReference<Map<String, dynamic>> get recapDoc =>
      userDoc.collection('meta').doc('recap');

  /// Every collection kept under the user. Account deletion clears these.
  static const collections = [
    'tasks',
    'days',
    'sessions',
    'ledger',
    'meta',
    'scroll',
  ];

  /// Deletes everything stored for this user, then the user record. The
  /// client has no delete-collection call, so each is cleared in batches.
  /// Reads go to the server so nothing only the server knows is left behind.
  Future<void> deleteAllData() async {
    for (final name in collections) {
      final col = userDoc.collection(name);
      while (true) {
        final page = await col
            .limit(400)
            .get(const GetOptions(source: Source.server));
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in page.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    }
    await userDoc.delete();
  }

  void _commit(WriteBatch batch) {
    batch.commit().catchError((Object e) => debugPrint('Write failed: $e'));
  }

  void _ledgerEntry(WriteBatch batch, int amount, String reason) {
    batch.set(_ledger.doc(), {
      'amount': amount,
      'reason': reason,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ---- reads ----

  Stream<Profile> profile() =>
      userDoc.snapshots().map((s) => Profile.fromMap(s.data() ?? const {}));

  Stream<List<Task>> tasks() => _tasks
      .where('archived', isEqualTo: false)
      .snapshots()
      .map(
        (q) =>
            q.docs.map((d) => Task.fromMap(d.id, d.data())).toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  Stream<List<DayLog>> daysOn(String date) => _days
      .where('date', isEqualTo: date)
      .snapshots()
      .map((q) => q.docs.map((d) => DayLog.fromMap(d.data())).toList());

  Stream<List<DayLog>> daysSince(String from) => _days
      .where('date', isGreaterThanOrEqualTo: from)
      .snapshots()
      .map((q) => q.docs.map((d) => DayLog.fromMap(d.data())).toList());

  Stream<List<DayLog>> taskDays(String taskId) => _days
      .where('taskId', isEqualTo: taskId)
      .snapshots()
      .map((q) => q.docs.map((d) => DayLog.fromMap(d.data())).toList());

  Future<List<DayLog>> daysAfter(String date) async {
    final q = await _days.where('date', isGreaterThan: date).get();
    return q.docs.map((d) => DayLog.fromMap(d.data())).toList();
  }

  Future<DayLog?> day(String taskId, String date) async {
    final s = await _days.doc(DayLog.idFor(taskId, date)).get();
    return s.exists ? DayLog.fromMap(s.data()!) : null;
  }

  /// Recent sessions of one task that have a note, newest first.
  Stream<List<Session>> notes(String taskId) => _sessions
      .where('taskId', isEqualTo: taskId)
      .orderBy('startedAt', descending: true)
      .limit(40)
      .snapshots()
      .map(
        (q) => q.docs
            .map((d) => Session.fromMap(d.id, d.data()))
            .where((x) => x.note.isNotEmpty)
            .take(12)
            .toList(),
      );

  Stream<List<Session>> watchSessionsSince(String date) => _sessions
      .where('date', isGreaterThanOrEqualTo: date)
      .snapshots()
      .map((q) => q.docs.map((d) => Session.fromMap(d.id, d.data())).toList());

  // ---- full history, for "All time" and export ----

  /// Every task, including removed ones.
  Future<List<Task>> allTasks() async {
    final q = await _tasks.get();
    return q.docs.map((d) => Task.fromMap(d.id, d.data())).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<List<DayLog>> allDays() async {
    final q = await _days.get();
    return q.docs.map((d) => DayLog.fromMap(d.data())).toList();
  }

  Future<List<Session>> allSessions() async {
    final q = await _sessions.get();
    return q.docs.map((d) => Session.fromMap(d.id, d.data())).toList();
  }

  Future<List<LedgerEntry>> allLedger() async {
    final q = await _ledger.orderBy('at').get();
    return q.docs.map((d) => LedgerEntry.fromMap(d.data())).toList();
  }

  /// Cached AI notes: the weekly recap, monthly recaps, Wrapped.
  DocumentReference<Map<String, dynamic>> noteDoc(String key) =>
      userDoc.collection('meta').doc(key);

  Future<List<Session>> sessionsSince(String date) async {
    final q = await _sessions.where('date', isGreaterThanOrEqualTo: date).get();
    return q.docs.map((d) => Session.fromMap(d.id, d.data())).toList();
  }

  void setNote(String sessionId, String note) {
    _sessions.doc(sessionId).update({'note': note.trim()});
  }

  Stream<List<LedgerEntry>> ledger() => _ledger
      .orderBy('at', descending: true)
      .limit(30)
      .snapshots()
      .map((q) => q.docs.map((d) => LedgerEntry.fromMap(d.data())).toList());

  // ---- writes ----

  /// Creates the profile doc on first sign-in (a no-op afterwards). Works
  /// offline, unlike a read-then-write.
  void ensureProfile() {
    userDoc.set({'points': FieldValue.increment(0)}, SetOptions(merge: true));
  }

  void updateProfile(Map<String, dynamic> fields) {
    userDoc.set(fields, SetOptions(merge: true));
  }

  String createTask(Task t) {
    final ref = _tasks.doc();
    final today = todayKey();
    ref.set({
      ...t.editableFields(),
      'createdDate': today,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'lastChecked': addDays(today, -1),
      'currentStreak': 0,
      'cleanStreak': 0,
      'bestStreak': 0,
      'totalSeconds': 0,
      'archived': false,
    });
    return ref.id;
  }

  void updateTask(Task t) => _tasks.doc(t.id).update(t.editableFields());

  void archiveTask(String id) => _tasks.doc(id).update({'archived': true});

  Map<String, dynamic> _streakFields(StreakSnapshot s) => {
    'currentStreak': s.current,
    'cleanStreak': s.clean,
    'bestStreak': s.best,
    'lastChecked': s.lastChecked,
  };

  /// Records focused time and, if this pushes the day over its target,
  /// extends the streak and pays out points. Returns the completion, if any,
  /// and the new session's id so a note can be added to it.
  ({CompletionOutcome? outcome, String sessionId}) logTime({
    required Task task,
    required String date,
    required DayLog? existing,
    required int seconds,
    required int startedAt,
    bool manual = false,
    int notCountedSeconds = 0,
  }) {
    final batch = _db.batch();
    final taskRef = _tasks.doc(task.id);
    final sessionRef = _sessions.doc();
    batch.set(sessionRef, {
      'taskId': task.id,
      'date': date,
      'startedAt': startedAt,
      'seconds': seconds,
      'manual': manual,
      // Time in other apps that was left out. Only the total: which apps
      // stays on the phone.
      if (notCountedSeconds > 0) 'notCountedSeconds': notCountedSeconds,
    });
    batch.update(taskRef, {'totalSeconds': FieldValue.increment(seconds)});

    final day = <String, dynamic>{
      'taskId': task.id,
      'date': date,
      'seconds': FieldValue.increment(seconds),
    };
    CompletionOutcome? outcome;
    final total = (existing?.seconds ?? 0) + seconds;
    final alreadyDone = existing?.completed ?? false;
    if (!alreadyDone && total >= task.targetMinutes * 60) {
      day['completed'] = true;
      if (task.isDueOn(date)) {
        outcome = applyCompletion(task.streak, task.targetMinutes);
        batch.update(taskRef, _streakFields(outcome.streak));
        var earned = outcome.points + outcome.bonus;
        _ledgerEntry(batch, outcome.points, '${task.name} done');
        if (outcome.bonus > 0) {
          _ledgerEntry(
            batch,
            outcome.bonus,
            '${outcome.streak.clean}-day clean streak · ${task.name}',
          );
        }
        if (existing?.frozen ?? false) {
          // Froze the day but did it anyway: give back what was paid.
          final paid =
              existing!.freezePaid ?? freezeCostFor(task.targetMinutes);
          day['frozen'] = false;
          earned += paid;
          _ledgerEntry(batch, paid, 'Freeze refunded · ${task.name}');
        }
        batch.update(userDoc, {'points': FieldValue.increment(earned)});
      }
    }
    batch.set(
      _days.doc(DayLog.idFor(task.id, date)),
      day,
      SetOptions(merge: true),
    );
    _commit(batch);
    return (outcome: outcome, sessionId: sessionRef.id);
  }

  void applyEvaluation(Task task, EvalOutcome o) {
    final batch = _db.batch();
    final fields = _streakFields(o.streak);
    if (o.lostStreak > 0) {
      fields['lostStreak'] = o.lostStreak;
      fields['lostOn'] = o.missed.last;
    }
    batch.update(_tasks.doc(task.id), fields);
    for (final d in o.autoFrozen) {
      batch.set(_days.doc(DayLog.idFor(task.id, d)), {
        'taskId': task.id,
        'date': d,
        'frozen': true,
        'freezePaid': o.freezeCost,
      }, SetOptions(merge: true));
    }
    if (o.pointsSpent > 0) {
      batch.update(userDoc, {'points': FieldValue.increment(-o.pointsSpent)});
      _ledgerEntry(
        batch,
        -o.pointsSpent,
        'Auto-freeze ×${o.autoFrozen.length} · ${task.name}',
      );
    }
    _commit(batch);
  }

  /// Pays for time spent on limited apps: one point a minute. Points can go
  /// below the reserve or zero here when grace minutes were used; that debt
  /// comes out of future earnings.
  void spendScroll(int minutes, String detail, String date) {
    if (minutes <= 0) return;
    final batch = _db.batch();
    batch.update(userDoc, {'points': FieldValue.increment(-minutes)});
    _ledgerEntry(
      batch,
      -minutes,
      detail.isEmpty
          ? 'Scrolling · $minutes min'
          : 'Scrolling · $minutes min · $detail',
    );
    batch.set(userDoc.collection('scroll').doc(date), {
      'date': date,
      'seconds': FieldValue.increment(minutes * 60),
    }, SetOptions(merge: true));
    _commit(batch);
  }

  /// Minutes paid for on limited apps that day.
  Stream<int> scrollMinutesOn(String date) => userDoc
      .collection('scroll')
      .doc(date)
      .snapshots()
      .map((s) => ((s.data()?['seconds'] as num?)?.toInt() ?? 0) ~/ 60);

  /// Spend points to protect upcoming days, e.g. while travelling.
  /// [plan] maps each task to the dates to freeze.
  void freeze(Map<Task, List<String>> plan) {
    final batch = _db.batch();
    var count = 0, cost = 0;
    for (final MapEntry(key: task, value: dates) in plan.entries) {
      final each = freezeCostFor(task.targetMinutes);
      for (final d in dates) {
        batch.set(_days.doc(DayLog.idFor(task.id, d)), {
          'taskId': task.id,
          'date': d,
          'frozen': true,
          'freezePaid': each,
        }, SetOptions(merge: true));
        count++;
        cost += each;
      }
    }
    if (count == 0) return;
    batch.update(userDoc, {'points': FieldValue.increment(-cost)});
    _ledgerEntry(
      batch,
      -cost,
      plan.length == 1
          ? 'Froze ${plan.keys.first.name} ×$count'
          : 'Froze $count task-days',
    );
    _commit(batch);
  }
}
