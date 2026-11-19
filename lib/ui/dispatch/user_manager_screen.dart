import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/dispatch_repository.dart';
import '../../services/user_admin_repository.dart';
import '../../theme/app_theme.dart';
import '../common/pull_to_refresh.dart';
import '../common/status_style.dart';

/// Dispatch tab B (admins): search users, change role and level, account status,
/// suspension end, and the emergency rate-limit override.
class UserManagerScreen extends StatefulWidget {
  const UserManagerScreen({super.key, required this.admin, required this.users, this.clock = DateTime.now});

  final UserProfile admin;
  final UserAdminRepository users;
  final DateTime Function() clock;

  @override
  State<UserManagerScreen> createState() => _UserManagerScreenState();
}

class _UserManagerScreenState extends State<UserManagerScreen> {
  late Stream<List<UserProfile>> _users = widget.users.watchUsers();
  String _query = '';
  final Set<String> _busy = {};

  Future<void> _run(String uid, Future<void> Function() action, String done) async {
    setState(() => _busy.add(uid));
    try {
      await action();
      _toast(done);
    } on DispatchFailed catch (failure) {
      _toast(failure.message);
    } catch (_) {
      _toast('Could not save the change. Try again.');
    } finally {
      if (mounted) setState(() => _busy.remove(uid));
    }
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setStatus(UserProfile user, String status) async {
    DateTime? until;
    if (status == UserProfile.accountSuspended) {
      final days = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          shape: const RoundedRectangleBorder(),
          title: const Text('Suspend for how long?'),
          children: [
            for (final days in const [1, 3, 7, 30])
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(days),
                child: Text(days == 1 ? '1 day' : '$days days'),
              ),
          ],
        ),
      );
      if (days == null) return;
      until = widget.clock().add(Duration(days: days));
    }
    await _run(user.uid, () => widget.users.setStatus(user.uid, status, until: until), 'Status saved.');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserProfile>>(
      stream: _users,
      builder: (context, snapshot) {
        final shown = searchUsers(snapshot.data ?? const [], _query);
        return PullToRefresh(
          onRefresh: () async => setState(() => _users = widget.users.watchUsers()),
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search by name',
                prefixIcon: Icon(Icons.search, color: AppColors.ink),
                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
              ),
            ),
            const SizedBox(height: 12),
            if (snapshot.hasError)
              const Text('Could not load users. Pull down to try again.')
            else if (!snapshot.hasData)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (shown.isEmpty)
              const Text('No users match.')
            else
              for (final user in shown) ...[
                _UserCard(
                  user: user,
                  isSelf: user.uid == widget.admin.uid,
                  busy: _busy.contains(user.uid),
                  now: widget.clock(),
                  onRole: (option) => _run(user.uid, () => widget.users.setRole(user.uid, option), 'Role saved.'),
                  onStatus: (status) => _setStatus(user, status),
                  onOverride: (value) =>
                      _run(user.uid, () => widget.users.setRateLimitOverride(user.uid, value), 'Limit setting saved.'),
                ),
                const SizedBox(height: 10),
              ],
          ],
          ),
        );
      },
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.isSelf,
    required this.busy,
    required this.now,
    required this.onRole,
    required this.onStatus,
    required this.onOverride,
  });

  final UserProfile user;
  final bool isSelf;
  final bool busy;
  final DateTime now;
  final ValueChanged<RoleOption> onRole;
  final ValueChanged<String> onStatus;
  final ValueChanged<bool> onOverride;

  static const _statuses = [
    UserProfile.accountActive,
    UserProfile.accountWarned,
    UserProfile.accountSuspended,
    UserProfile.accountBanned,
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = !isSelf && !busy;
    final until = user.suspendedUntil;
    final blocked = user.isBlockedAt(now);
    return Container(
      decoration: const BoxDecoration(border: Border.fromBorderSide(BorderSide(color: AppColors.ink))),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${user.displayName ?? (user.tier == UserProfile.tierCommuterObserver ? 'Guest' : 'Unnamed user')}'
                  '${isSelf ? ' (you)' : ''}',
                  style: textTheme.titleMedium,
                ),
              ),
              FlatBadge(
                label: user.accountStatus,
                background: blocked ? AppColors.redOrange : (user.accountStatus == UserProfile.accountWarned ? AppColors.riskMedium : AppColors.sage),
                foreground: AppColors.ink,
              ),
            ],
          ),
          Text(user.tierTitle, style: textTheme.bodySmall),
          Text(
            'CTP ${user.ctp} · Reports ${user.reportsTotal} · Accuracy ${(user.accuracy * 100).round()}%'
            '${until != null && user.accountStatus == UserProfile.accountSuspended ? ' · Suspended until ${until.toLocal().toString().substring(0, 16)}' : ''}',
            style: textTheme.bodySmall,
          ),
          if (isSelf) Text('You cannot change your own account.', style: textTheme.bodySmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<RoleOption>(
            initialValue: RoleOption.of(user),
            decoration: const InputDecoration(labelText: 'Role', isDense: true),
            items: [for (final o in RoleOption.all) DropdownMenuItem(value: o, child: Text(o.title))],
            onChanged: enabled ? (o) => o == null || o == RoleOption.of(user) ? null : onRole(o) : null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _statuses.contains(user.accountStatus) ? user.accountStatus : UserProfile.accountActive,
            decoration: const InputDecoration(labelText: 'Account status', isDense: true),
            items: [for (final s in _statuses) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: enabled ? (s) => s == null || s == user.accountStatus ? null : onStatus(s) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('No daily report limit (emergencies)'),
            value: user.rateLimitOverride,
            onChanged: enabled ? onOverride : null,
          ),
        ],
      ),
    );
  }
}
