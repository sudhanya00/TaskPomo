import 'package:flutter_test/flutter_test.dart';
import 'package:taskpomo/logic/scroll.dart';
import 'package:taskpomo/logic/streaks.dart';
import 'package:taskpomo/models/models.dart';

Task t(int target) => Task(
  id: '$target',
  name: 'T$target',
  icon: 'book',
  targetMinutes: target,
  days: everyDay,
  createdDate: '2026-10-01',
);

void main() {
  test('default reserve covers two freezes of the biggest task', () {
    expect(defaultReserve([t(15), t(20)]), 60); // 2 × 29 → 58 → 60
    expect(defaultReserve([t(120)]), 240);
    expect(defaultReserve(const []), 0);
    expect(defaultReserve([t(20)]) >= 2 * freezeCostFor(20), isTrue);
  });

  test('one point buys one minute above the reserve', () {
    expect(allowanceSeconds(100, 60), 40 * 60);
    expect(allowanceSeconds(60, 60), 0);
    // Below the reserve (after grace) it goes negative: that's the debt.
    expect(allowanceSeconds(55, 60), -5 * 60);
  });

  test('spend summary lists apps biggest first and skips crumbs', () {
    expect(
      spendSummary({'YouTube': 240, 'Instagram': 480, 'LinkedIn': 20}),
      'Instagram 8, YouTube 4',
    );
    expect(spendSummary(const {}), '');
  });
}
