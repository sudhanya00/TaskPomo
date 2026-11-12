import 'package:flutter_test/flutter_test.dart';
import 'package:taskpomo/logic/session_check.dart';

AwayApp app(String pkg, AppKind kind, [int ms = 60000]) =>
    AwayApp(package: pkg, label: pkg, kind: kind, ms: ms);

void main() {
  group('ruleFor', () {
    const none = <String>{};

    test('social apps and games never count', () {
      expect(
        ruleFor(app('wa', AppKind.social), allowed: none, limited: none),
        AppRule.never,
      );
      expect(
        ruleFor(app('g', AppKind.game), allowed: none, limited: none),
        AppRule.never,
      );
    });

    test('video, browsers and anything else are asked about', () {
      for (final k in [AppKind.video, AppKind.browser, AppKind.other]) {
        expect(ruleFor(app('x', k), allowed: none, limited: none), AppRule.ask);
      }
    });

    test('limited apps never count, even if their kind would be asked', () {
      expect(
        ruleFor(app('yt', AppKind.video), allowed: none, limited: {'yt'}),
        AppRule.never,
      );
    });

    test('an app the task always counts wins over everything', () {
      expect(
        ruleFor(app('yt', AppKind.video), allowed: {'yt'}, limited: {'yt'}),
        AppRule.count,
      );
      expect(
        ruleFor(app('wa', AppKind.social), allowed: {'wa'}, limited: none),
        AppRule.count,
      );
    });
  });

  test('remember starts ticked except for video and browsers', () {
    expect(rememberByDefault(AppKind.other), isTrue);
    expect(rememberByDefault(AppKind.video), isFalse);
    expect(rememberByDefault(AppKind.browser), isFalse);
  });

  test('merging adds time per app', () {
    final m = <String, AwayApp>{};
    mergeAway(m, app('wa', AppKind.social, 60000));
    mergeAway(m, app('wa', AppKind.social, 120000));
    mergeAway(m, app('ig', AppKind.social, 40000));
    expect(m['wa']!.ms, 180000);
    expect(totalMs(m.values), 220000);
    expect(awaySummary(m.values), 'wa 3 min, ig 40 s');
  });

  test('round-trips through json', () {
    final a = app('yt', AppKind.video, 6000);
    final b = AwayApp.fromJson(a.toJson());
    expect((b.package, b.kind, b.ms), ('yt', AppKind.video, 6000));
    expect(appKindFrom('nonsense'), AppKind.other);
  });
}
