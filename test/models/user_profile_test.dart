import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';

void main() {
  test('tier 1 is titled Commuter Observer', () {
    const profile = UserProfile(
      uid: 'u',
      role: 'CITIZEN',
      tier: 1,
      accountStatus: 'ACTIVE',
    );
    expect(profile.tierTitle, 'Commuter Observer');
  });

  test('tier titles cover all five levels and reject unknown tiers', () {
    String titleFor(int tier) => UserProfile(
          uid: 'u',
          role: 'CITIZEN',
          tier: tier,
          accountStatus: 'ACTIVE',
        ).tierTitle;

    expect(titleFor(2), 'Civic Scout');
    expect(titleFor(3), 'Neighborhood Sentinel');
    expect(titleFor(4), 'Municipal Dispatcher');
    expect(titleFor(5), 'System Administrator');
    expect(titleFor(9), 'Unknown tier');
  });

  test('new citizen fields match the keys and values firestore.rules requires', () {
    final fields = UserProfile.newCitizenFields();

    expect(fields.keys.toSet(), {'role', 'tier', 'accountStatus'});
    expect(fields['role'], 'CITIZEN');
    expect(fields['tier'], 1);
    expect(fields['accountStatus'], 'ACTIVE');
  });

  test('fromFirestore reads stored fields and falls back on bad data', () {
    final parsed = UserProfile.fromFirestore('u1', {
      'role': 'CITIZEN',
      'tier': 2,
      'accountStatus': 'ACTIVE',
    });
    expect(parsed.tier, 2);

    final fallback = UserProfile.fromFirestore('u2', {'tier': 'two'});
    expect(fallback.tier, 1);
    expect(fallback.role, 'CITIZEN');
    expect(fallback.accountStatus, 'ACTIVE');
  });
}
