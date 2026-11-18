import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/level_policy.dart';

UserProfile _p({
  int tier = 1,
  String role = 'CITIZEN',
  int ctp = 0,
  int total = 0,
  int resolved = 0,
  String status = 'ACTIVE',
}) =>
    UserProfile(
      uid: 'u',
      role: role,
      tier: tier,
      accountStatus: status,
      ctp: ctp,
      reportsTotal: total,
      reportsResolved: resolved,
    );

void main() {
  test('Level 1 earns Civic Scout at 50 CTP', () {
    expect(LevelPolicy.dueUpgrade(_p(ctp: 49)), isNull);
    expect(LevelPolicy.dueUpgrade(_p(ctp: 50))?.tier, 2);
  });

  test('Level 2 earns Sentinel at 250 CTP with at least 85% resolved', () {
    expect(LevelPolicy.dueUpgrade(_p(tier: 2, ctp: 250, total: 20, resolved: 17)), (tier: 3, role: 'VERIFIER'));
    expect(LevelPolicy.dueUpgrade(_p(tier: 2, ctp: 250, total: 20, resolved: 16)), isNull);
    expect(LevelPolicy.dueUpgrade(_p(tier: 2, ctp: 249, total: 20, resolved: 20)), isNull);
    expect(LevelPolicy.dueUpgrade(_p(tier: 2, ctp: 300)), isNull);
  });

  test('blocked accounts, staff, and Sentinels do not level up here', () {
    expect(LevelPolicy.dueUpgrade(_p(ctp: 100, status: 'SUSPENDED')), isNull);
    expect(LevelPolicy.dueUpgrade(_p(tier: 4, role: 'DISPATCHER', ctp: 999, total: 1, resolved: 1)), isNull);
    expect(LevelPolicy.dueUpgrade(_p(tier: 3, role: 'VERIFIER', ctp: 999, total: 1, resolved: 1)), isNull);
    expect(LevelPolicy.dueUpgrade(_p(ctp: 50, status: 'WARNED'))?.tier, 2);
  });

  test('progress shows the next target', () {
    expect(LevelPolicy.progress(_p(ctp: 25)).fraction, 0.5);
    expect(LevelPolicy.progress(_p(tier: 2, ctp: 125)).target, 250);
    expect(LevelPolicy.progress(_p(tier: 3, role: 'VERIFIER')).target, isNull);
  });
}
