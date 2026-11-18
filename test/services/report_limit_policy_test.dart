import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/geo/philippine_day.dart';
import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/report_limit_policy.dart';
import 'package:hazardradarai/services/report_repository.dart';

// 10:00 in Manila on 18 Nov 2026 is 02:00 UTC.
final _now = DateTime.utc(2026, 11, 18, 2);
final _today = DateTime.utc(2026, 11, 18);

UserProfile _profile({
  int tier = 1,
  int count = 0,
  DateTime? day,
  String status = 'ACTIVE',
  bool override = false,
  DateTime? until,
}) =>
    UserProfile(
      uid: 'u',
      role: 'CITIZEN',
      tier: tier,
      accountStatus: status,
      reportCount: count,
      reportDay: day ?? _today,
      rateLimitOverride: override,
      suspendedUntil: until,
    );

void main() {
  test('philippineDay uses UTC+8', () {
    expect(philippineDay(DateTime.utc(2026, 11, 18, 15, 59)), DateTime.utc(2026, 11, 18));
    expect(philippineDay(DateTime.utc(2026, 11, 18, 16)), DateTime.utc(2026, 11, 19));
  });

  test('limits are 3 for guests, 10 for scouts, none above', () {
    expect(ReportLimitPolicy.check(_profile(count: 2), _now).allowed, isTrue);
    expect(ReportLimitPolicy.check(_profile(count: 3), _now).block, ReportBlock.guestLimit);
    expect(ReportLimitPolicy.check(_profile(tier: 2, count: 9), _now).remaining, 1);
    expect(ReportLimitPolicy.check(_profile(tier: 2, count: 10), _now).block, ReportBlock.scoutLimit);
    expect(ReportLimitPolicy.check(_profile(tier: 3, count: 99), _now).allowed, isTrue);
  });

  test('yesterday\'s count does not apply, and the override lifts the limit', () {
    expect(ReportLimitPolicy.check(_profile(count: 3, day: DateTime.utc(2026, 11, 17)), _now).allowed, isTrue);
    expect(ReportLimitPolicy.check(_profile(count: 3, override: true), _now).allowed, isTrue);
  });

  test('banned and suspended accounts are blocked; an ended suspension is not', () {
    expect(ReportLimitPolicy.check(_profile(status: 'BANNED'), _now).block, ReportBlock.banned);
    expect(
      ReportLimitPolicy.check(_profile(status: 'SUSPENDED', until: _now.add(const Duration(hours: 1))), _now).block,
      ReportBlock.suspended,
    );
    expect(ReportLimitPolicy.check(_profile(status: 'SUSPENDED'), _now).block, ReportBlock.suspended);
    expect(
      ReportLimitPolicy.check(_profile(status: 'SUSPENDED', until: _now.subtract(const Duration(hours: 1))), _now)
          .allowed,
      isTrue,
    );
    expect(ReportLimitPolicy.check(_profile(status: 'WARNED'), _now).allowed, isTrue);
  });

  test('every block has a message', () {
    for (final block in ReportBlock.values.where((b) => b != ReportBlock.none)) {
      expect(ReportLimitPolicy.explain(ReportAllowance(block: block, usedToday: 0, limit: 3)), isNotEmpty);
    }
  });

  test('nextReportCounter continues today and resets on a new day', () {
    expect(nextReportCounter({'reportDay': Timestamp.fromDate(_today), 'reportCount': 2}, _today).count, 3);
    expect(
      nextReportCounter({'reportDay': Timestamp.fromDate(DateTime.utc(2026, 11, 17)), 'reportCount': 2}, _today).count,
      1,
    );
    expect(nextReportCounter(null, _today).count, 1);
  });
}
