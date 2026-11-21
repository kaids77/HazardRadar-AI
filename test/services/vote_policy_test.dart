import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/services/vote_policy.dart';

VoteEligibility _check({
  int tier = 2,
  String uid = 'me',
  String reporter = 'other',
  double? distance = 50,
}) =>
    VotePolicy.check(tier: tier, uid: uid, reporterUid: reporter, distanceMeters: distance);

void main() {
  test('vote weight follows the tier', () {
    expect(VotePolicy.weightForTier(1), 0);
    expect(VotePolicy.weightForTier(2), 1);
    expect(VotePolicy.weightForTier(3), 2);
    expect(VotePolicy.weightForTier(5), 2);
  });

  test('guests must upgrade before voting', () {
    expect(_check(tier: 1), VoteEligibility.needsUpgrade);
  });

  test('reporters cannot vote on their own report', () {
    expect(_check(reporter: 'me'), VoteEligibility.ownReport);
  });

  test('voting needs a known location within 200 m', () {
    expect(_check(distance: null), VoteEligibility.locationUnknown);
    expect(_check(distance: 200), VoteEligibility.allowed);
    expect(_check(distance: 200.5), VoteEligibility.tooFar);
  });

  test('every blocked state has a message and allowed has none', () {
    expect(VotePolicy.explain(VoteEligibility.allowed), isNull);
    for (final blocked in VoteEligibility.values.where((e) => e != VoteEligibility.allowed)) {
      expect(VotePolicy.explain(blocked), isNotEmpty);
    }
  });
}
