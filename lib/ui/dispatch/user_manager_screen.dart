import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/avatar_repository.dart';
import '../../services/dispatch_repository.dart';
import '../../services/moderation_policy.dart';
import '../../services/user_admin_repository.dart';
import '../../theme/app_theme.dart';
import '../common/feedback.dart';
import '../common/pagination.dart';
import '../common/pull_to_refresh.dart';
import '../common/status_style.dart';
import '../common/user_avatar.dart';

/// The name an admin sees for a user. Never the uid.
String userLabel(UserProfile user) {
  final name = user.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return user.tier == UserProfile.tierCommuterObserver ? 'Guest' : 'Name not set yet';
}

/// Dispatch tab B (admins): a list of users by name and role. Tapping a user opens
/// their details and the actions (role, account status, daily limit override).
class UserManagerScreen extends StatefulWidget {
  const UserManagerScreen({super.key, required this.admin, required this.users, this.avatars, this.clock = DateTime.now});

  final UserProfile admin;
  final UserAdminRepository users;

  /// Profile photos for the detail page. Null shows initials only.
  final AvatarRepository? avatars;
  final DateTime Function() clock;

  @override
  State<UserManagerScreen> createState() => _UserManagerScreenState();
}

class _UserManagerScreenState extends State<UserManagerScreen> {
  late Stream<List<UserProfile>> _users = widget.users.watchUsers();
  String _query = '';
  int _page = 0;

  void _open(UserProfile user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserDetailScreen(
          admin: widget.admin,
          uid: user.uid,
          users: widget.users,
          avatars: widget.avatars,
          clock: widget.clock,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return StreamBuilder<List<UserProfile>>(
      stream: _users,
      builder: (context, snapshot) {
        final shown = searchUsers(snapshot.data ?? const [], _query);
        final page = paginate(shown, page: _page);
        return PullToRefresh(
          onRefresh: () async => setState(() => _users = widget.users.watchUsers()),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                onChanged: (value) => setState(() {
                  _query = value;
                  _page = 0;
                }),
                decoration: InputDecoration(
                  hintText: 'Search by name',
                  prefixIcon: Icon(Icons.search, color: palette.ink),
                  border: const OutlineInputBorder(borderRadius: AppTheme.radiusMd),
                ),
              ),
              const SizedBox(height: 12),
              if (snapshot.hasError)
                const FeedbackMessage.error('Could not load users. Pull down to try again.')
              else if (!snapshot.hasData)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (shown.isEmpty)
                const Text('No users match.')
              else ...[
                for (final user in page.items)
                  _UserRow(user: user, isSelf: user.uid == widget.admin.uid, onTap: () => _open(user)),
                const SizedBox(height: 12),
                PaginationBar(page: page, onPageChanged: (next) => setState(() => _page = next)),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One list row: initials, name, and role. Nothing else, so the list scans quickly.
class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, required this.isSelf, required this.onTap});

  final UserProfile user;
  final bool isSelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final label = userLabel(user);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.sage))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: UserAvatar(name: user.displayName == null ? null : label, size: 40),
        title: Text('$label${isSelf ? ' (you)' : ''}', overflow: TextOverflow.ellipsis),
        subtitle: Text(user.tierTitle),
        trailing: Icon(Icons.chevron_right, color: palette.ink),
        onTap: onTap,
      ),
    );
  }
}

/// One user's details and the admin actions. Follows the live user list, so a change
/// shows up as soon as Firestore saves it.
class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({
    super.key,
    required this.admin,
    required this.uid,
    required this.users,
    this.avatars,
    this.clock = DateTime.now,
    this.canEdit = true,
  });

  /// The staff member viewing the page (an admin, or a dispatcher when [canEdit] is false).
  final UserProfile admin;
  final String uid;
  final UserAdminRepository users;
  final AvatarRepository? avatars;
  final DateTime Function() clock;

  /// False for dispatchers: the page is read-only, because only admins manage accounts.
  final bool canEdit;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  late final Stream<List<UserProfile>> _users = widget.users.watchUsers();
  late final Future<Uint8List?> _photo = _loadPhoto();
  late Future<int> _quarantined = widget.users.quarantinedReports(widget.uid);
  bool _busy = false;

  Future<Uint8List?> _loadPhoto() async {
    try {
      return await widget.avatars?.load(widget.uid);
    } catch (_) {
      return null;
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSuccess(context, done);
    } on DispatchFailed catch (failure) {
      if (mounted) showError(context, failure.message);
    } catch (_) {
      if (mounted) showError(context, 'Could not save the change. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(UserProfile user, String status) async {
    DateTime? until;
    if (status == UserProfile.accountSuspended) {
      final days = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
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
    await _run(() => widget.users.setStatus(user.uid, status, until: until), 'Status saved.');
  }

  static const _statuses = [
    UserProfile.accountActive,
    UserProfile.accountWarned,
    UserProfile.accountSuspended,
    UserProfile.accountBanned,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User')),
      body: StreamBuilder<List<UserProfile>>(
        stream: _users,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: FeedbackMessage.error('Could not load this user. Go back and try again.'),
            );
          }
          final user = snapshot.data?.where((u) => u.uid == widget.uid).firstOrNull;
          if (user == null) {
            return snapshot.hasData
                ? const Padding(padding: EdgeInsets.all(16), child: Text('This user no longer exists.'))
                : const Center(child: CircularProgressIndicator());
          }
          return _details(context, user);
        },
      ),
    );
  }

  Widget _details(BuildContext context, UserProfile user) {
    final textTheme = Theme.of(context).textTheme;
    final isSelf = user.uid == widget.admin.uid;
    final enabled = widget.canEdit && !isSelf && !_busy;
    final now = widget.clock();
    final until = user.suspendedUntil;
    final label = userLabel(user);
    final blocked = user.isBlockedAt(now);
    final warned = user.accountStatus == UserProfile.accountWarned;
    return PullToRefresh(
      onRefresh: () async {
        final next = widget.users.quarantinedReports(widget.uid);
        setState(() => _quarantined = next);
        await next.catchError((_) => 0);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              FutureBuilder<Uint8List?>(
                future: _photo,
                builder: (context, photo) =>
                    UserAvatar(name: user.displayName == null ? null : label, photo: photo.data, size: 72),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$label${isSelf ? ' (you)' : ''}', style: textTheme.titleLarge),
                    Text(user.tierTitle, style: textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    FlatBadge.outlined(
                      label: user.accountStatus,
                      color: blocked
                          ? AppColors.riskHigh
                          : warned
                              ? AppColors.riskMedium
                              : AppColors.riskLow,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Report history', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              _Stat(label: 'Trust points', value: '${user.ctp}'),
              _Stat(label: 'Reports', value: '${user.reportsTotal}'),
              _Stat(label: 'Resolved', value: '${user.reportsResolved}'),
              _Stat(label: 'Accuracy', value: '${(user.accuracy * 100).round()}%'),
            ],
          ),
          if (until != null && user.accountStatus == UserProfile.accountSuspended) ...[
            const SizedBox(height: 8),
            Text('Suspended until ${until.toLocal().toString().substring(0, 16)}', style: textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          _ModerationBlock(user: user, quarantined: _quarantined),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text('Actions', style: textTheme.titleMedium),
          if (!widget.canEdit) ...[
            const SizedBox(height: 8),
            const FeedbackMessage.error('Only admins can change accounts. Ask an admin to act on this user.'),
          ] else if (isSelf) ...[
            const SizedBox(height: 8),
            const FeedbackMessage.error('You cannot change your own account.'),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<RoleOption>(
            key: ValueKey('role-${user.role}-${user.tier}'),
            initialValue: RoleOption.of(user),
            decoration: const InputDecoration(labelText: 'Role', isDense: true),
            items: [for (final o in RoleOption.all) DropdownMenuItem(value: o, child: Text(o.title))],
            onChanged: enabled
                ? (o) => o == null || o == RoleOption.of(user)
                    ? null
                    : _run(() => widget.users.setRole(user.uid, o), 'Role saved.')
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('status-${user.accountStatus}'),
            initialValue: _statuses.contains(user.accountStatus) ? user.accountStatus : UserProfile.accountActive,
            decoration: const InputDecoration(labelText: 'Account status', isDense: true),
            items: [for (final s in _statuses) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: enabled ? (s) => s == null || s == user.accountStatus ? null : _setStatus(user, s) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('No daily report limit (emergencies)'),
            value: user.rateLimitOverride,
            onChanged: enabled
                ? (value) => _run(() => widget.users.setRateLimitOverride(user.uid, value), 'Limit setting saved.')
                : null,
          ),
        ],
      ),
    );
  }
}

/// Quarantined and removed counts, and the suggested action from the moderation guideline.
class _ModerationBlock extends StatelessWidget {
  const _ModerationBlock({required this.user, required this.quarantined});

  final UserProfile user;
  final Future<int> quarantined;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    return FutureBuilder<int>(
      future: quarantined,
      builder: (context, snapshot) {
        final counted = snapshot.hasData;
        final failed = snapshot.hasError;
        final suggestion = counted || failed
            ? suggestModeration(
                accountStatus: user.accountStatus,
                quarantined: snapshot.data ?? 0,
                removed: user.reportsRemoved,
              )
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Stat(label: 'Quarantined now', value: counted ? '${snapshot.data}' : (failed ? '?' : '...')),
                _Stat(label: 'Removed as spam', value: '${user.reportsRemoved}'),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: AppTheme.radiusMd,
                border: Border.all(
                  color: suggestion?.isAction == true ? AppColors.riskMedium : palette.sage,
                  width: 2,
                ),
              ),
              child: suggestion == null
                  ? const Text('Counting reports...')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Suggested: ${suggestion.title}', style: textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(suggestion.reason),
                        if (failed) const Text('Could not count quarantined reports. Pull down to try again.'),
                        const SizedBox(height: 4),
                        Text(
                          'A hint only. The app never warns, suspends, or bans anyone by itself.',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: textTheme.titleMedium),
          Text(label, textAlign: TextAlign.center, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}
