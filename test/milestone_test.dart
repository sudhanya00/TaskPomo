import 'package:flutter_test/flutter_test.dart';
import 'package:taskpomo/logic/streaks.dart';

void main() {
  test('next and previous milestones', () {
    expect(nextMilestone(0), 10);
    expect(nextMilestone(9), 10);
    expect(nextMilestone(10), 20);
    expect(nextMilestone(364), 365);
    expect(nextMilestone(365), 400);
    expect(nextMilestone(420), 500);
    expect(previousMilestone(9), 0);
    expect(previousMilestone(10), 10);
    expect(previousMilestone(49), 20);
    expect(previousMilestone(380), 365);
    expect(previousMilestone(410), 400);
  });

  test('milestones line up with bonuses', () {
    for (final d in [10, 20, 50, 100, 150, 200, 300, 365, 400, 500]) {
      expect(isMilestone(d), isTrue, reason: '$d');
      expect(milestoneBonus(d, 15), greaterThan(0));
    }
    for (final d in [1, 9, 11, 99, 250, 310, 366]) {
      expect(isMilestone(d), isFalse, reason: '$d');
    }
  });
}
