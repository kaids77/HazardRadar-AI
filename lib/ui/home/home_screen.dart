import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/report_limit_policy.dart';
import '../../theme/app_theme.dart';
import '../account/account_sheet.dart';
import '../map/map_screen.dart';
import '../report/report_screen.dart';
import '../reports/my_reports_screen.dart';
import '../settings/settings_screen.dart';
import 'home_services.dart';

/// Waits for sign-in and the profile, then shows the three tabs:
/// Radar (live map), My Reports, and Settings.
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

  HomeServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    unawaited(_s.settings.load());
    _profile = _start();
  }

  /// Starts the session, then re-checks offline-triaged reports in the background.
  Future<UserProfile> _start() async {
    final profile = await _s.session.start();
    final enricher = _s.enricher;
    if (enricher != null) unawaited(enricher.enrichPending(profile.uid));
    return profile;
  }

  void _retry() {
    setState(() {
      _latest = null;
      _profile = _start();
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Reloads the profile so counts and points are current. Keeps the old copy on failure.
  Future<UserProfile?> _refresh() async {
    try {
      final profile = await _s.session.start();
      if (mounted) setState(() => _latest = profile);
      return profile;
    } catch (_) {
      return null;
    }
  }

  Future<void> _openAccount(UserProfile profile) async {
    final upgraded = await showAccountSheet(context, profile: profile, session: _s.session);
    if (upgraded == null || !mounted) return;
    setState(() => _latest = upgraded);
    _toast('You are now a ${upgraded.tierTitle}.');
  }

  /// Checks the daily limit with a fresh profile before opening the camera.
  Future<void> _openReport() async {
    final profile = await _refresh();
    if (!mounted) return;
    if (profile == null) {
      _toast('Could not check your account. Try again.');
      return;
    }

    final allowance = ReportLimitPolicy.check(profile, DateTime.now());
    if (allowance.block == ReportBlock.guestLimit) {
      _toast(ReportLimitPolicy.explain(allowance)!);
      await _openAccount(profile);
      return;
    }
    final blocked = ReportLimitPolicy.explain(allowance);
    if (blocked != null) {
      _toast(blocked);
      return;
    }

    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReportScreen(reports: _s.reports, photos: _s.photos, location: _s.location),
      ),
    );
    if (sent == true && mounted) {
      _toast('Report sent. Thank you.');
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
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _ErrorState(
                  onRetry: _retry,
                  // Shows the real cause in debug builds only. Release builds show the generic message.
                  detail: kDebugMode ? '${snapshot.error}' : null,
                ),
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
            settings: _s.settings,
            onReport: _openReport,
          ),
        ),
      ],
    );
    return _Frame(
      tierLabel: profile.tierTitle,
      onAccount: () => _openAccount(profile),
      onReport: _tab == 0 ? _openReport : null,
      body: IndexedStack(
        index: _tab,
        children: [
          radar,
          MyReportsScreen(
            profile: profile,
            reports: _s.myReports,
            onSignIn: () => _openAccount(profile),
          ),
          SettingsScreen(profile: profile, settings: _s.settings, onAccount: () => _openAccount(profile)),
        ],
      ),
      bottom: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          setState(() => _tab = index);
          if (index == 1) unawaited(_refresh());
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.radar), label: 'Radar'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'My Reports'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.body, this.tierLabel, this.onReport, this.onAccount, this.bottom});

  final String? tierLabel;
  final Widget body;
  final VoidCallback? onReport;
  final VoidCallback? onAccount;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HazardRadar AI'),
        actions: [
          if (tierLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: onAccount,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(tierLabel!, style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
        ],
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
        Text(
          'Could not connect. Check your network and try again.',
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge,
        ),
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
