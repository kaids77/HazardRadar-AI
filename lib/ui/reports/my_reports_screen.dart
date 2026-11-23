import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../models/transparency_entry.dart';
import '../../models/user_profile.dart';
import '../../services/level_policy.dart';
import '../../services/my_reports_repository.dart';
import '../../services/transparency_repository.dart';
import '../../theme/app_theme.dart';
import '../common/feedback.dart';
import '../common/pagination.dart';
import '../common/pull_to_refresh.dart';
import '../common/status_style.dart';
import '../map/risk_style.dart';
import 'transparency_section.dart';

enum ReportFilter { all, active, inProgress, resolved }

extension on ReportFilter {
  String get label => switch (this) {
        ReportFilter.all => 'All',
        ReportFilter.active => 'Active',
        ReportFilter.inProgress => 'In progress',
        ReportFilter.resolved => 'Resolved',
      };

  bool matches(Incident incident) => switch (this) {
        ReportFilter.all => true,
        ReportFilter.active => incident.status == Incident.statusActive,
        ReportFilter.inProgress => incident.status == Incident.statusInProgress,
        ReportFilter.resolved => incident.status == Incident.statusResolved,
      };
}

/// Tab 2: the user's level, Civic Trust Points, and their own reports.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({
    super.key,
    required this.profile,
    required this.reports,
    this.onSignIn,
    this.onPickBadge,
    this.onRefresh,
    this.transparency,
  });

  final UserProfile profile;
  final MyReportsRepository reports;

  /// The public report transparency log shown at the bottom. Null hides the section.
  final TransparencyRepository? transparency;

  /// Opens the Google upgrade. Shown to guests only.
  final VoidCallback? onSignIn;

  /// Saves a focus badge. Offered to Neighborhood Sentinels without one.
  final ValueChanged<String>? onPickBadge;

  /// Reloads the profile (level, points) on pull-to-refresh.
  final Future<void> Function()? onRefresh;

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Stream<List<Incident>> _mine;
  ReportFilter _filter = ReportFilter.all;
  int _page = 0;

  /// The public transparency log, or null when the build has none.
  Stream<List<TransparencyEntry>>? _log;
  Future<({int resolved, int quarantined})>? _logCounts;

  @override
  void initState() {
    super.initState();
    _mine = widget.reports.watchMine(widget.profile.uid);
    _subscribeLog();
  }

  void _subscribeLog() {
    final repo = widget.transparency;
    if (repo == null) return;
    // Refresh the total counts every time the live stream emits a change, so web
    // and mobile chip counts update automatically without a manual refresh.
    _log = repo.watchRecent().map((entries) {
      final counts = repo.counts().catchError((Object _) => (resolved: 0, quarantined: 0));
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _logCounts = counts);
        });
      }
      return entries;
    });
    // A failed count only hides the numbers; the list still loads.
    _logCounts = repo.counts().catchError((Object _) => (resolved: 0, quarantined: 0));
  }

  @override
  void didUpdateWidget(MyReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The uid changes when a Google account that already had a profile is linked or signed out.
    if (oldWidget.profile.uid != widget.profile.uid) {
      _mine = widget.reports.watchMine(widget.profile.uid);
      _subscribeLog();
      _page = 0;
    }
  }

  /// Re-subscribes the lists (revives them after an error) and reloads the profile.
  Future<void> _reload() async {
    setState(() {
      _mine = widget.reports.watchMine(widget.profile.uid);
      _subscribeLog();
    });
    await widget.onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Incident>>(
      stream: _mine,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Incident>[];
        final shown = all.where(_filter.matches).toList();
        final page = paginate(shown, page: _page);
        return PullToRefresh(
          onRefresh: _reload,
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.profile.tier == UserProfile.tierCommuterObserver) ...[
              _GuestCard(onSignIn: widget.onSignIn),
              const SizedBox(height: 12),
            ],
            _ProfileCard(profile: widget.profile),
            if (widget.profile.tier >= UserProfile.tierSentinel &&
                widget.profile.focusBadge == null &&
                widget.onPickBadge != null) ...[
              const SizedBox(height: 12),
              _BadgePicker(onPick: widget.onPickBadge!),
            ],
            const SizedBox(height: 20),
            Text('My reports', style: _heading),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in ReportFilter.values)
                  ChoiceChip(
                    label: Text('${filter.label} (${all.where(filter.matches).length})'),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() {
                      _filter = filter;
                      _page = 0;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (snapshot.hasError)
              const FeedbackMessage.error('Could not load your reports. Pull down to try again.')
            else if (!snapshot.hasData)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (shown.isEmpty)
              Text(
                all.isEmpty ? 'You have not filed a report yet.' : 'No reports in this filter.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else ...[
              for (final incident in page.items) ...[
                _HistoryCard(incident: incident),
                const SizedBox(height: 8),
              ],
              PaginationBar(page: page, onPageChanged: (next) => setState(() => _page = next)),
            ],
            if (_log != null && _logCounts != null) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              TransparencySection(key: const ValueKey('transparency'), entries: _log!, counts: _logCounts!),
            ],
          ],
          ),
        );
      },
    );
  }

  static const _heading = TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22);
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({this.onSignIn});

  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.sage,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Guest profile', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Sign in with Google to become a Civic Scout: vote on hazards near you and file up to 10 reports a day. '
            'Your reports and points stay with you.',
          ),
          if (onSignIn != null) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onSignIn,
              style: ElevatedButton.styleFrom(shape: const RoundedRectangleBorder()),
              child: const Text('Sign in with Google'),
            ),
          ],
        ],
      ),
    );
  }
}

class _BadgePicker extends StatelessWidget {
  const _BadgePicker({required this.onPick});

  final ValueChanged<String> onPick;

  static const _descriptions = {
    'Roadway Watch': 'Potholes, sinkholes, and road obstructions',
    'Grid Guardian': 'Downed lines, exposed wiring, and streetlights',
    'Hydro Monitor': 'Flooding, clogged drains, and water main breaks',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.sage,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose your focus badge', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final badge in LevelPolicy.focusBadges)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton(
                onPressed: () => onPick(badge),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.palette.ink,
                  side: BorderSide(color: context.palette.ink),
                  shape: const RoundedRectangleBorder(),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(12),
                ),
                child: Text('$badge: ${_descriptions[badge]}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final progress = LevelPolicy.progress(profile);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(border: Border.fromBorderSide(BorderSide(color: context.palette.ink))),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Level ${profile.tier}', style: textTheme.labelLarge),
                    Text(
                      profile.tierTitle,
                      style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 24, color: context.palette.ink),
                    ),
                    if (profile.focusBadge != null) Text(profile.focusBadge!, style: textTheme.bodySmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${profile.ctp}',
                    style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 32, color: context.palette.ink),
                  ),
                  Text('Trust points', style: textTheme.bodySmall),
                ],
              ),
            ],
          ),
          if (progress.target != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 8,
              child: LinearProgressIndicator(
                value: progress.fraction,
                backgroundColor: context.palette.sage,
                color: AppColors.redOrange,
              ),
            ),
            const SizedBox(height: 6),
            Text('${profile.ctp} / ${progress.target} to ${progress.nextTitle}', style: textTheme.bodySmall),
            if (progress.hint != null) Text(progress.hint!, style: textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: 'Reports', value: '${profile.reportsTotal}'),
              _Stat(label: 'Resolved', value: '${profile.reportsResolved}'),
              _Stat(label: 'Accuracy', value: '${(profile.accuracy * 100).round()}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final status = statusStyle(context, incident);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: riskColor(incident.riskLevel), width: 4)),
        color: context.palette.paper,
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FlatBadge(label: status.label, background: status.background, foreground: status.foreground),
              FlatBadge(
                label: '${incident.riskLevel} risk',
                background: riskColor(incident.riskLevel),
                foreground: incident.riskLevel == 'High' ? AppColors.onRedOrange : AppColors.cream,
              ),
              if (incident.isVerified)
                const FlatBadge(label: 'Verified', background: AppColors.riskLow, foreground: AppColors.cream),
              if (!incident.aiProcessed)
                FlatBadge(label: 'Pending AI review', background: context.palette.sage, foreground: context.palette.ink),
            ],
          ),
          const SizedBox(height: 6),
          Text('${incident.category} · ${incident.reference}', style: textTheme.titleSmall),
          Text(incident.aiSummary, style: textTheme.bodyMedium),
          if (incident.isVerified) ...[
            const SizedBox(height: 4),
            Text(
              '+${incident.netVotes} votes · Verified by the community',
              style: textTheme.bodySmall?.copyWith(color: AppColors.riskLow, fontWeight: FontWeight.w700),
            ),
          ],
          if (incident.resolutionNote != null) ...[
            const SizedBox(height: 6),
            Text('City note: ${incident.resolutionNote}', style: textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
