import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/incident.dart';
import '../models/user_profile.dart';
import 'dispatch_repository.dart';

/// A role choice in the user manager. Role and tier always change together,
/// matching isAdminUserUpdate() in firestore.rules.
class RoleOption {
  const RoleOption(this.role, this.tier, this.title);

  final String role;
  final int tier;
  final String title;

  static const List<RoleOption> all = [
    RoleOption(UserProfile.roleCitizen, 1, 'Commuter Observer (L1)'),
    RoleOption(UserProfile.roleCitizen, 2, 'Civic Scout (L2)'),
    RoleOption(UserProfile.roleVerifier, 3, 'Neighborhood Sentinel (L3)'),
    RoleOption(UserProfile.roleDispatcher, 4, 'Municipal Dispatcher (L4)'),
    RoleOption(UserProfile.roleAdmin, 5, 'System Administrator (L5)'),
  ];

  static RoleOption of(UserProfile profile) =>
      all.firstWhere((o) => o.role == profile.role && o.tier == profile.tier, orElse: () => all.first);

  @override
  bool operator ==(Object other) => other is RoleOption && other.role == role && other.tier == tier;

  @override
  int get hashCode => Object.hash(role, tier);
}

/// Level 5 admin actions on other users.
abstract interface class UserAdminRepository {
  Stream<List<UserProfile>> watchUsers({int limit = 200});
  Future<void> setRole(String uid, RoleOption option);

  /// [until] is required for SUSPENDED and cleared for every other status.
  Future<void> setStatus(String uid, String status, {DateTime? until});
  Future<void> setRateLimitOverride(String uid, bool value);

  /// How many of the user's reports are quarantined right now, not counting any the
  /// city already resolved. Staff only.
  Future<int> quarantinedReports(String uid);
}

/// Case-insensitive search over display name and uid, then sorted by name.
List<UserProfile> searchUsers(List<UserProfile> users, String query) {
  final q = query.trim().toLowerCase();
  final matches = q.isEmpty
      ? users
      : users.where((u) => (u.displayName ?? '').toLowerCase().contains(q) || u.uid.toLowerCase().contains(q));
  return matches.toList()
    ..sort((a, b) => (a.displayName ?? '~${a.uid}').toLowerCase().compareTo((b.displayName ?? '~${b.uid}').toLowerCase()));
}

class FirestoreUserAdminRepository implements UserAdminRepository {
  FirestoreUserAdminRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _user(String uid) => _db.collection('users').doc(uid);

  @override
  Stream<List<UserProfile>> watchUsers({int limit = 200}) =>
      Stream<List<UserProfile>>.multi((controller) {
        final sub = _db
            .collection('users')
            .limit(limit)
            .snapshots()
            .map((s) => [for (final doc in s.docs) UserProfile.fromFirestore(doc.id, doc.data())])
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
        controller.onCancel = sub.cancel;
      });

  @override
  Future<void> setRole(String uid, RoleOption option) =>
      _guard(() => _user(uid).update({'role': option.role, 'tier': option.tier}));

  @override
  Future<void> setStatus(String uid, String status, {DateTime? until}) => _guard(() {
        if (status == UserProfile.accountSuspended && until == null) {
          throw const DispatchFailed('Pick when the suspension ends.');
        }
        return _user(uid).update({
          'accountStatus': status,
          'suspendedUntil': status == UserProfile.accountSuspended ? Timestamp.fromDate(until!) : null,
        });
      });

  @override
  Future<void> setRateLimitOverride(String uid, bool value) =>
      _guard(() => _user(uid).update({'rateLimitOverride': value}));

  // Equality filters only, so Firestore merges the single-field indexes (no composite index).
  @override
  Future<int> quarantinedReports(String uid) async {
    final quarantined = _db
        .collection('incidents')
        .where('reporterUid', isEqualTo: uid)
        .where('visibility', isEqualTo: Incident.visibilityQuarantined);
    final counts = await Future.wait([
      quarantined.count().get(),
      quarantined.where('status', isEqualTo: Incident.statusResolved).count().get(),
    ]);
    return ((counts[0].count ?? 0) - (counts[1].count ?? 0)).clamp(0, 1 << 30);
  }

  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const DispatchFailed('Not allowed. Admins cannot change their own account.');
      }
      rethrow;
    }
  }
}
