import 'package:cloud_firestore/cloud_firestore.dart';

/// A commuter's profile as stored in `users/{uid}`.
///
/// Field names and values must match `firestore.rules`. Fields added after launch
/// are missing on older profiles, so every one of them has a default.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.role,
    required this.tier,
    required this.accountStatus,
    this.reportDay,
    this.reportCount = 0,
    this.rateLimitOverride = false,
    this.suspendedUntil,
    this.ctp = 0,
    this.reportsTotal = 0,
    this.reportsResolved = 0,
    this.reportsRemoved = 0,
    this.creditName = false,
    this.displayName,
    this.focusBadge,
  });

  static const String roleCitizen = 'CITIZEN';
  static const String roleVerifier = 'VERIFIER';
  static const String roleDispatcher = 'DISPATCHER';
  static const String roleAdmin = 'ADMIN';

  static const String accountActive = 'ACTIVE';
  static const String accountWarned = 'WARNED';
  static const String accountSuspended = 'SUSPENDED';
  static const String accountBanned = 'BANNED';

  static const int tierCommuterObserver = 1;
  static const int tierCivicScout = 2;
  static const int tierSentinel = 3;

  final String uid;
  final String role;
  final int tier;
  final String accountStatus;

  /// Midnight (UTC) of the Philippine day of the last report, and that day's count.
  final DateTime? reportDay;
  final int reportCount;

  /// Set by an admin during emergencies: no daily report limit.
  final bool rateLimitOverride;
  final DateTime? suspendedUntil;

  /// Civic Trust Points and report totals.
  final int ctp;
  final int reportsTotal;
  final int reportsResolved;

  /// Reports an admin removed as spam. Raised only by isRemovalCount() in firestore.rules.
  final int reportsRemoved;

  /// The user chose to show their name on their resolved reports in the public
  /// transparency log. Off by default.
  final bool creditName;
  final String? displayName;
  final String? focusBadge;

  bool get isStaff => role == roleDispatcher || role == roleAdmin;
  bool get isAdmin => role == roleAdmin;

  /// Share of reports resolved by the city, from 0 to 1. Zero reports count as 0.
  double get accuracy => reportsTotal == 0 ? 0 : reportsResolved / reportsTotal;

  /// Mirrors isBlocked() in firestore.rules.
  bool isBlockedAt(DateTime now) {
    if (accountStatus == accountBanned) return true;
    if (accountStatus != accountSuspended) return false;
    final until = suspendedUntil;
    return until == null || now.isBefore(until);
  }

  String get tierTitle => switch (tier) {
        1 => 'Commuter Observer',
        2 => 'Civic Scout',
        3 => 'Neighborhood Sentinel',
        4 => 'Municipal Dispatcher',
        5 => 'System Administrator',
        _ => 'Unknown tier',
      };

  /// Fields for a new Level 1 profile, without the server timestamp.
  static Map<String, Object> newCitizenFields() => {
        'role': roleCitizen,
        'tier': tierCommuterObserver,
        'accountStatus': accountActive,
      };

  UserProfile copyWith({int? tier, String? role, int? reportCount, DateTime? reportDay, int? ctp, int? reportsTotal}) {
    return UserProfile(
      uid: uid,
      role: role ?? this.role,
      tier: tier ?? this.tier,
      accountStatus: accountStatus,
      reportDay: reportDay ?? this.reportDay,
      reportCount: reportCount ?? this.reportCount,
      rateLimitOverride: rateLimitOverride,
      suspendedUntil: suspendedUntil,
      ctp: ctp ?? this.ctp,
      reportsTotal: reportsTotal ?? this.reportsTotal,
      reportsResolved: reportsResolved,
      reportsRemoved: reportsRemoved,
      creditName: creditName,
      displayName: displayName,
      focusBadge: focusBadge,
    );
  }

  factory UserProfile.fromFirestore(String uid, Map<String, Object?> data) {
    return UserProfile(
      uid: uid,
      role: data['role'] as String? ?? roleCitizen,
      tier: _int(data['tier'], tierCommuterObserver),
      accountStatus: data['accountStatus'] as String? ?? accountActive,
      reportDay: _date(data['reportDay']),
      reportCount: _int(data['reportCount'], 0),
      rateLimitOverride: data['rateLimitOverride'] == true,
      suspendedUntil: _date(data['suspendedUntil']),
      ctp: _int(data['ctp'], 0),
      reportsTotal: _int(data['reportsTotal'], 0),
      reportsResolved: _int(data['reportsResolved'], 0),
      reportsRemoved: _int(data['reportsRemoved'], 0),
      creditName: data['creditName'] == true,
      displayName: data['displayName'] is String ? data['displayName'] as String : null,
      focusBadge: data['focusBadge'] is String ? data['focusBadge'] as String : null,
    );
  }

  static int _int(Object? value, int fallback) => value is int ? value : fallback;

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
