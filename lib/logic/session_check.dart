/// Judging time spent in other apps during a focus session. The phone only
/// knows which app was in front, never what was done in it, so clear cases
/// are decided by the kind of app and the rest are asked about afterwards.
library;

/// The kind of app, from the category its developer declares (browsers are
/// found by what opens web links).
enum AppKind { social, game, video, browser, other }

AppKind appKindFrom(String? s) =>
    AppKind.values.firstWhere((k) => k.name == s, orElse: () => AppKind.other);

enum AppRule {
  /// Part of the task, e.g. a tuner while practising.
  count,

  /// Never part of a task: social apps, games and your limited apps.
  never,

  /// Could go either way (a tutorial or Shorts); asked after the session.
  ask,
}

/// Time in one app during a session.
class AwayApp {
  const AwayApp({
    required this.package,
    required this.label,
    required this.kind,
    required this.ms,
  });

  final String package;
  final String label;
  final AppKind kind;
  final int ms;

  AwayApp plus(int more) =>
      AwayApp(package: package, label: label, kind: kind, ms: ms + more);

  Map<String, Object?> toJson() => {
    'package': package,
    'label': label,
    'kind': kind.name,
    'ms': ms,
  };

  factory AwayApp.fromJson(Map<String, dynamic> j) => AwayApp(
    package: j['package'] as String,
    label: j['label'] as String? ?? j['package'] as String,
    kind: appKindFrom(j['kind'] as String?),
    ms: (j['ms'] as num?)?.toInt() ?? 0,
  );
}

/// What to do with time in [app] during a session of a task that always
/// counts [allowed], while [limited] are the apps points pay for.
AppRule ruleFor(
  AwayApp app, {
  required Set<String> allowed,
  required Set<String> limited,
}) {
  if (allowed.contains(app.package)) return AppRule.count;
  if (limited.contains(app.package)) return AppRule.never;
  return switch (app.kind) {
    AppKind.social || AppKind.game => AppRule.never,
    AppKind.video || AppKind.browser || AppKind.other => AppRule.ask,
  };
}

/// Whether "always count for this task" starts ticked when you count an
/// app. Video and browsers depend on what you watched, so they don't.
bool rememberByDefault(AppKind kind) =>
    kind != AppKind.video && kind != AppKind.browser;

/// Adds [more] into [into], by package.
void mergeAway(Map<String, AwayApp> into, AwayApp more) {
  final had = into[more.package];
  into[more.package] = had == null ? more : had.plus(more.ms);
}

int totalMs(Iterable<AwayApp> apps) => apps.fold(0, (sum, a) => sum + a.ms);

/// "3 min" or, under a minute, "40 s".
String awayDuration(int ms) {
  final s = ms ~/ 1000;
  return s < 60 ? '$s s' : '${s ~/ 60} min';
}

/// "WhatsApp 3 min, Instagram 40 s"
String awaySummary(Iterable<AwayApp> apps) =>
    [for (final a in apps) '${a.label} ${awayDuration(a.ms)}'].join(', ');

/// Why an app wasn't counted, for the after-session sheet.
String neverReason(AwayApp app, Set<String> limited) =>
    limited.contains(app.package)
    ? 'a limited app'
    : app.kind == AppKind.game
    ? 'a game'
    : 'a social app';
