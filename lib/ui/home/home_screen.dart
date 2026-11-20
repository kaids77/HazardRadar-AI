import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/account_linker.dart';
import '../../services/photo_service.dart';
import '../../services/report_limit_policy.dart';
import '../../services/staff_auth.dart';
import '../../theme/app_theme.dart';
import '../account/account_sheet.dart';
import '../account/name_dialog.dart';
import '../account/photo_actions.dart';
import '../common/feedback.dart';
import '../common/pull_to_refresh.dart';
import '../common/user_avatar.dart';
import '../dispatch/analytics_screen.dart';
import '../dispatch/dispatch_screen.dart';
import '../dispatch/quarantine_screen.dart';
import '../dispatch/user_manager_screen.dart';
import '../map/map_screen.dart';
import '../report/wizard/report_wizard_screen.dart';
import '../reports/my_reports_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/staff_sign_in.dart';
import 'home_services.dart';

/// Waits for sign-in and the profile, then shows the tabs:
/// Radar (live map), My Reports, Dispatch (staff only), and Settings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});

  final HomeServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<UserProfile> _profile;
  int _tab = 0;

  /// The newest copy of the profile after an upgrade or a report. Replaces the
  /// loaded profile without rebuilding the map through a new future.
  UserProfile? _latest;

  /// The signed-in account's profile photo, and the uid it belongs to.
  Uint8List? _avatar;
  String? _avatarUid;

  /// True while the name dialog is open, so two triggers never stack two dialogs.
  bool _askingName = false;

  HomeServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    unawaited(_s.settings.load());
    _load();
  }

  void _load() {
    _profile = _start();
    _profile.then(_afterLoad, onError: (_) {});
  }

  /// Starts the session, then re-checks offline-triaged reports in the background.
  Future<UserProfile> _start() async {
    final profile = await _s.session.start();
    final enricher = _s.enricher;
    if (enricher != null) unawaited(enricher.enrichPending(profile.uid));
    return profile;
  }

  /// Loads the photo and, for an account without a name, asks for one.
  void _afterLoad(UserProfile profile) {
    if (!mounted) return;
    unawaited(_syncAvatar(profile));
    if (_needsName(profile)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_promptName(profile, required: true));
      });
    }
  }

  void _retry() {
    setState(() {
      _latest = null;
      _load();
    });
  }

  void _success(String message) {
    if (mounted) showSuccess(context, message);
  }

  void _error(String message) {
    if (mounted) showError(context, message);
  }

  /// Google and staff email accounts have a name. Guests stay anonymous.
  bool _needsName(UserProfile profile) =>
      _s.session.hasAccount && (profile.displayName == null || profile.displayName!.trim().isEmpty);

  /// The name shown in the top bar and Settings.
  String _nameOf(UserProfile profile) {
    final name = profile.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return _s.session.hasAccount ? profile.tierTitle : 'Guest';
  }

  /// Loads the photo once per account. Guests have none.
  Future<void> _syncAvatar(UserProfile profile) async {
    final repo = _s.avatars;
    if (repo == null || !_s.session.hasAccount) {
      if (_avatar != null || _avatarUid != null) {
        setState(() {
          _avatar = null;
          _avatarUid = null;
        });
      }
      return;
    }
    if (_avatarUid == profile.uid) return;
    _avatarUid = profile.uid;
    _avatar = null;
    try {
      final bytes = await repo.load(profile.uid);
      if (mounted && _avatarUid == profile.uid) setState(() => _avatar = bytes);
    } catch (_) {
      // No photo is fine; initials show instead.
    }
  }

  /// Reloads the profile so counts and points are current. Keeps the old copy on failure.
  /// Announces a level gained since the last copy.
  Future<UserProfile?> _refresh() async {
    final previousTier = _latest?.tier;
    try {
      final profile = await _s.session.start();
      if (!mounted) return profile;
      setState(() => _latest = profile);
      unawaited(_syncAvatar(profile));
      if (previousTier != null && profile.tier > previousTier) {
        _success('Level up: you are now a ${profile.tierTitle}.');
      }
      return profile;
    } catch (_) {
      return null;
    }
  }

  Future<void> _promptName(UserProfile profile, {required bool required}) async {
    if (_askingName) return;
    _askingName = true;
    try {
      final name = await askDisplayName(
        context,
        initial: profile.displayName ?? _s.session.googleName,
        required: required,
      );
      if (name == null || !mounted || name == profile.displayName) return;
      final updated = await _s.session.saveDisplayName(profile.uid, name);
      if (!mounted) return;
      setState(() => _latest = updated);
      _success('Name saved.');
    } catch (_) {
      _error('Could not save your name. Try again.');
    } finally {
      _askingName = false;
    }
  }

  Future<void> _changePhoto(UserProfile profile) async {
    final picker = _s.avatarPicker;
    final repo = _s.avatars;
    if (picker == null || repo == null) return;
    final action = await askPhotoAction(context, hasPhoto: _avatar != null);
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case RemovePhoto():
          await repo.remove(profile.uid);
          if (mounted) setState(() => _avatar = null);
          _success('Photo removed.');
        case PickPhoto(:final source):
          final bytes = await picker.pick(source);
          if (bytes == null) return;
          await repo.save(profile.uid, bytes);
          if (mounted) {
            setState(() {
              _avatar = bytes;
              _avatarUid = profile.uid;
            });
          }
          _success('Photo saved.');
      }
    } on PhotoTooLargeException {
      _error('That photo is too large. Try another one.');
    } catch (error) {
      const message = 'Could not save the photo. Try again.';
      _error(kDebugMode ? '$message\n$error' : message);
    }
  }

  Future<void> _pickBadge(UserProfile profile, String badge) async {
    try {
      await _s.session.profiles.setFocusBadge(profile.uid, badge);
      await _refresh();
      _success('Badge saved.');
    } catch (_) {
      _error('Could not save your badge. Try again.');
    }
  }

  /// Opens the account sheet. After a Google sign-in the user confirms their name.
  Future<UserProfile?> _openAccount(UserProfile profile, {UpgradeReason reason = UpgradeReason.manual}) async {
    final upgraded = await showAccountSheet(context, profile: profile, session: _s.session, reason: reason);
    if (upgraded == null || !mounted) return null;
    setState(() => _latest = upgraded);
    _success('Signed in with Google. You are now a ${upgraded.tierTitle}.');
    unawaited(_syncAvatar(upgraded));
    await _promptName(upgraded, required: true);
    return _latest ?? upgraded;
  }

  /// The Settings staff button for admins and dispatchers who use Google.
  Future<void> _signInWithGoogle() async {
    try {
      final profile = await _s.session.upgradeWithGoogle();
      if (profile == null || !mounted) return;
      setState(() {
        _latest = profile;
        _tab = 0;
      });
      if (profile.isStaff) {
        _success('Signed in as ${profile.tierTitle}.');
      } else {
        _error('Signed in with Google, but this account has no staff role yet. Ask an admin.');
      }
      unawaited(_syncAvatar(profile));
      if (_needsName(profile)) await _promptName(profile, required: true);
    } on LinkFailed catch (failure) {
      _error(failure.message);
    } catch (error) {
      const message = 'Google sign-in failed. Try again.';
      _error(kDebugMode ? '$message\n$error' : message);
    }
  }

  /// Checks the daily limit with a fresh profile before opening the camera.
  Future<void> _openReport() async {
    final profile = await _refresh();
    if (!mounted) return;
    if (profile == null) {
      _error('Could not check your account. Try again.');
      return;
    }

    final allowance = ReportLimitPolicy.check(profile, DateTime.now());
    if (allowance.block == ReportBlock.guestLimit) {
      await _openAccount(profile, reason: UpgradeReason.reportLimit);
      return;
    }
    final blocked = ReportLimitPolicy.explain(allowance);
    if (blocked != null) {
      _error(blocked);
      return;
    }

    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReportWizardScreen(reports: _s.reports, photos: _s.photos, location: _s.location),
      ),
    );
    if (sent == true && mounted) {
      _success('Report sent. Thank you.');
      unawaited(_refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _Frame(body: Center(child: CircularProgressIndicator(color: AppColors.redOrange)));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _Frame(
            body: PullToRefresh(
              onRefresh: () async {
                _retry();
                await _profile.then((_) {}, onError: (_) {});
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 96, 24, 24),
                children: [
                  _ErrorState(
                    onRetry: _retry,
                    // Shows the real cause in debug builds only. Release builds show the generic message.
                    detail: kDebugMode ? '${snapshot.error}' : null,
                  ),
                ],
              ),
            ),
          );
        }
        return _tabs(_latest ?? snapshot.data!);
      },
    );
  }

  Widget _tabs(UserProfile profile) {
    final radar = Column(
      children: [
        if (profile.accountStatus == UserProfile.accountWarned) const _WarnedBanner(),
        Expanded(
          child: MapScreen(
            incidents: _s.incidents,
            location: _s.location,
            profile: profile,
            votes: _s.votes,
            chat: _s.chat,
            detour: _s.detour,
            settings: _s.settings,
            onReport: _openReport,
            onUpgrade: () => _openAccount(profile, reason: UpgradeReason.vote),
          ),
        ),
      ],
    );
    final staffAuth = _s.session.staffAuth;
    final dispatch = _s.dispatch;
    final showDispatch = profile.isStaff && dispatch != null;
    final hasAccount = _s.session.hasAccount;
    final name = _nameOf(profile);
    final pages = <Widget>[
      radar,
      MyReportsScreen(
        profile: profile,
        reports: _s.myReports,
        onSignIn: () => _openAccount(profile),
        onPickBadge: (badge) => _pickBadge(profile, badge),
        onRefresh: _refresh,
      ),
      if (showDispatch)
        DispatchScreen(
          key: ValueKey(profile.uid),
          profile: profile,
          dispatch: dispatch,
          staffTabs: [
            if (_s.moderation case final moderation?)
              ('Quarantine', QuarantineScreen(profile: profile, moderation: moderation)),
          ],
          adminTabs: [
            if (_s.userAdmin case final users?)
              ('Users', UserManagerScreen(admin: profile, users: users, avatars: _s.avatars)),
            if (_s.analytics case final analytics?)
              ('Analytics', AnalyticsScreen(analytics: analytics, moderation: _s.moderation)),
          ],
        ),
      SettingsScreen(
        profile: profile,
        settings: _s.settings,
        name: name,
        photo: _avatar,
        hasAccount: hasAccount,
        onAccount: () => _openAccount(profile),
        onEditName: hasAccount ? () => _promptName(profile, required: false) : null,
        onChangePhoto: hasAccount && _s.avatarPicker != null && _s.avatars != null ? () => _changePhoto(profile) : null,
        onRefresh: _refresh,
        staffSection: staffAuth == null
            ? null
            : StaffSignInSection(
                profile: profile,
                isEmailSession: staffAuth.isEmailSession,
                googleEmail: staffAuth.googleEmail,
                hasPassword: staffAuth.hasPassword,
                onCheckAccess: _refresh,
                onSignIn: _signInStaff,
                onGoogleSignIn: _s.session.linker == null ? null : _signInWithGoogle,
                onSetPassword: (password) async {
                  await staffAuth.setPassword(password);
                  if (mounted) setState(() {});
                },
                onSignOut: _signOutStaff,
              ),
      ),
    ];
    final tab = _tab.clamp(0, pages.length - 1);
    return _Frame(
      account: _AccountButton(
        name: name,
        photo: _avatar,
        // Guests show a person icon instead of initials.
        initialsFrom: hasAccount ? name : null,
        onPressed: () => _openAccount(profile),
      ),
      onReport: tab == 0 ? _openReport : null,
      body: IndexedStack(index: tab, children: pages),
      bottom: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) {
          setState(() => _tab = index);
          // Reload the profile on every tab switch, so a role an admin changed in the
          // console (for example ADMIN) shows up without restarting the app.
          unawaited(_refresh());
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.radar), label: 'Radar'),
          const NavigationDestination(icon: Icon(Icons.list_alt), label: 'My Reports'),
          if (showDispatch) const NavigationDestination(icon: Icon(Icons.engineering_outlined), label: 'Dispatch'),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }

  Future<UserProfile> _signInStaff(String email, String password) async {
    final profile = await _s.session.signInStaff(email: email, password: password);
    if (mounted) {
      setState(() {
        _latest = profile;
        _tab = 0;
      });
      if (profile.isStaff) _success('Signed in as ${profile.tierTitle}.');
      unawaited(_syncAvatar(profile));
      if (_needsName(profile)) await _promptName(profile, required: true);
    }
    return profile;
  }

  Future<void> _signOutStaff() async {
    try {
      final profile = await _s.session.signOutStaff();
      if (!mounted) return;
      setState(() {
        _latest = profile;
        _tab = 0;
      });
      unawaited(_syncAvatar(profile));
      _success('Signed out. You are browsing as a guest.');
    } on StaffSignInFailed catch (failure) {
      _error(failure.message);
    } catch (_) {
      _error('Could not sign out. Try again.');
    }
  }
}

/// The top-bar account button: square photo (or initials) and the user's name.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.name, required this.photo, required this.initialsFrom, required this.onPressed});

  final String name;
  final Uint8List? photo;

  /// The name used for initials, or null for the guest icon.
  final String? initialsFrom;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        label: 'Account: $name',
        excludeSemantics: true,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: context.palette.ink,
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              UserAvatar(name: initialsFrom, photo: photo, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.body, this.account, this.onReport, this.bottom});

  final Widget? account;
  final Widget body;
  final VoidCallback? onReport;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HazardRadar AI'),
        actions: [?account],
      ),
      body: body,
      bottomNavigationBar: bottom,
      floatingActionButton: onReport == null
          ? null
          : FloatingActionButton.extended(
              onPressed: onReport,
              elevation: 0,
              focusElevation: 0,
              hoverElevation: 0,
              highlightElevation: 0,
              shape: const RoundedRectangleBorder(),
              backgroundColor: AppColors.redOrange,
              foregroundColor: AppColors.onRedOrange,
              label: const Text('Report hazard'),
            ),
    );
  }
}

class _WarnedBanner extends StatelessWidget {
  const _WarnedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.riskMedium,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        'Your account has a warning from a moderator. Further false reports can lead to a suspension.',
        // Fixed ink on the fixed amber fill, in light and dark mode.
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, this.detail});

  final VoidCallback onRetry;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const FeedbackMessage.error('Could not connect. Check your network and try again.'),
        if (detail != null) ...[
          const SizedBox(height: 12),
          SelectableText(
            detail!,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
