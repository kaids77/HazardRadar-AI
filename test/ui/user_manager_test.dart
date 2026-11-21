import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/user_admin_repository.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/dispatch/user_manager_screen.dart';

const _admin = UserProfile(uid: 'admin', role: 'ADMIN', tier: 5, accountStatus: 'ACTIVE', displayName: 'Ana Admin');
const _bob = UserProfile(
  uid: 'bob-uid',
  role: 'CITIZEN',
  tier: 2,
  accountStatus: 'ACTIVE',
  displayName: 'Bob Santos',
  ctp: 120,
  reportsTotal: 10,
  reportsResolved: 9,
);

class _Repo implements UserAdminRepository {
  final calls = <String>[];

  @override
  Stream<List<UserProfile>> watchUsers({int limit = 200}) => Stream.value(const [_admin, _bob]);

  @override
  Future<void> setRole(String uid, RoleOption option) async => calls.add('role $uid ${option.role} ${option.tier}');

  @override
  Future<void> setStatus(String uid, String status, {DateTime? until}) async =>
      calls.add('status $uid $status ${until?.toIso8601String()}');

  @override
  Future<void> setRateLimitOverride(String uid, bool value) async => calls.add('override $uid $value');
}

final _now = DateTime.utc(2026, 11, 18, 2);

Future<_Repo> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: UserManagerScreen(admin: _admin, users: repo, clock: () => _now)),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  test('search matches name or uid and sorts by name', () {
    expect(searchUsers(const [_bob, _admin], '').map((u) => u.uid), ['admin', 'bob-uid']);
    expect(searchUsers(const [_bob, _admin], 'santos').map((u) => u.uid), ['bob-uid']);
    expect(searchUsers(const [_bob, _admin], 'BOB-U').map((u) => u.uid), ['bob-uid']);
  });

  test('role options pair each role with its level', () {
    expect(RoleOption.of(_bob).title, 'Civic Scout (L2)');
    expect(RoleOption.all.map((o) => '${o.role}${o.tier}'), ['CITIZEN1', 'CITIZEN2', 'VERIFIER3', 'DISPATCHER4', 'ADMIN5']);
  });

  testWidgets('the list shows only names and roles; a row opens the details', (tester) async {
    await _pump(tester);
    expect(find.text('Bob Santos'), findsOneWidget);
    expect(find.text('Ana Admin (you)'), findsOneWidget);
    expect(find.text('Civic Scout'), findsOneWidget);
    expect(find.text('Civic Scout (L2)'), findsNothing);

    await _openBob(tester);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('Civic Scout (L2)'), findsOneWidget);
  });

  testWidgets('a user without a name is never shown as Unnamed user', (tester) async {
    expect(userLabel(const UserProfile(uid: 'x', role: 'CITIZEN', tier: 2, accountStatus: 'ACTIVE')), 'Name not set yet');
    expect(userLabel(const UserProfile(uid: 'x', role: 'CITIZEN', tier: 1, accountStatus: 'ACTIVE')), 'Guest');
  });

  testWidgets('the admin cannot change their own account', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Ana Admin (you)'));
    await tester.pumpAndSettle();
    expect(find.text('You cannot change your own account.'), findsOneWidget);
  });

  testWidgets('promotes Bob to dispatcher', (tester) async {
    final repo = await _pump(tester);
    await _openBob(tester);

    await tester.tap(find.text('Civic Scout (L2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Municipal Dispatcher (L4)').last);
    await tester.pumpAndSettle();

    expect(repo.calls, ['role bob-uid DISPATCHER 4']);
  });

  testWidgets('suspending asks for a duration', (tester) async {
    final repo = await _pump(tester);
    await _openBob(tester);

    await tester.tap(find.text('ACTIVE').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SUSPENDED').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['status bob-uid SUSPENDED ${_now.add(const Duration(days: 7)).toIso8601String()}']);
  });

  testWidgets('toggles the emergency rate-limit override', (tester) async {
    final repo = await _pump(tester);
    await _openBob(tester);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(repo.calls, ['override bob-uid true']);
  });
}

Future<void> _openBob(WidgetTester tester) async {
  await tester.tap(find.text('Bob Santos'));
  await tester.pumpAndSettle();
}
