import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/hazard_category.dart';
import '../../models/incident.dart';
import '../../services/analytics.dart';
import '../../services/moderation_repository.dart';
import '../../theme/app_theme.dart';
import '../common/feedback.dart';
import '../common/pagination.dart';
import '../common/pull_to_refresh.dart';
import 'storage_meter.dart';

/// Dispatch tab C (admins): city performance from the newest 500 reports.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, required this.analytics, this.moderation, this.clock = DateTime.now});

  final AnalyticsRepository analytics;
  final ModerationRepository? moderation;
  final DateTime Function() clock;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  StreamSubscription<List<Incident>>? _sub;
  CityAnalytics? _data;
  StorageEstimate? _storage;
  bool _error = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _sub?.cancel();
    setState(() => _error = false);
    _sub = widget.analytics.watchRecent().listen(
      (incidents) {
        if (!mounted) return;
        setState(() {
          _error = false;
          _data = CityAnalytics.compute(incidents, widget.clock());
        });
        unawaited(_loadStorage());
      },
      onError: (_) {
        if (mounted) setState(() => _error = true);
      },
    );
  }

  Future<void> _loadStorage() async {
    try {
      final storage = await widget.moderation?.storage();
      if (mounted && storage != null) setState(() => _storage = storage);
    } catch (_) {
      // Informational only.
    }
  }

  Future<void> _load() async {
    _subscribe();
    await _loadStorage();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final textTheme = Theme.of(context).textTheme;
    if (_error) {
      return PullToRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            const FeedbackMessage.error('Could not load analytics. Pull down to try again.'),
            const SizedBox(height: 8),
            Center(child: OutlinedButton(onPressed: _load, child: const Text('Try again'))),
          ],
        ),
      );
    }
    if (data == null) return const Center(child: CircularProgressIndicator());
    final mttr = data.meanTimeToResolve;
    final hotspots = paginate(data.hotspots, page: _page);
    return PullToRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _Block(label: 'Resolution rate', value: '${(data.resolutionRate * 100).toStringAsFixed(1)}%'),
              _Block(label: 'Mean time to resolve', value: mttr == null ? '-' : formatDuration(mttr)),
              _Block(label: 'Total reports', value: '${data.total}'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Block(label: 'Active high', value: '${data.activeHigh}', color: AppColors.redOrange, foreground: AppColors.onRedOrange),
              _Block(label: 'Active medium', value: '${data.activeMedium}', color: AppColors.riskMedium, foreground: AppColors.ink),
              _Block(label: 'Active low', value: '${data.activeLow}', color: AppColors.riskLow, foreground: AppColors.cream),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Block(label: 'In progress', value: '${data.inProgress}', color: AppColors.inProgress, foreground: AppColors.onInProgress),
              _Block(label: 'Resolved today', value: '${data.resolvedToday}'),
              _Block(label: 'Quarantined', value: '${data.quarantined}', color: context.palette.ink, foreground: context.palette.paper),
            ],
          ),
          const SizedBox(height: 16),
          Text('Hazard categories', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          _CategoryBar(counts: data.categoryCounts),
          const SizedBox(height: 16),
          Text('Hotspots (open reports per 1 km cell)', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          if (data.hotspots.isEmpty)
            Text('No open reports.', style: textTheme.bodySmall)
          else ...[
            for (final (index, spot) in hotspots.items.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${hotspots.start + index + 1}. ${spot.geohash} · ${spot.count} open',
                  style: textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            const SizedBox(height: 8),
            PaginationBar(page: hotspots, onPageChanged: (next) => setState(() => _page = next)),
          ],
          const SizedBox(height: 16),
          Text('AI health', style: textTheme.titleMedium),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: LinearProgressIndicator(value: data.aiProcessedShare, backgroundColor: context.palette.sage, color: context.palette.ink),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(data.aiProcessedShare * 100).round()}% of reports classified by Radar AI; the rest used the offline fallback.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (widget.moderation != null) StorageMeter(estimate: _storage),
          const SizedBox(height: 8),
          Text('Based on the newest ${data.total} reports. Pull down to refresh.', style: textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.label, required this.value, this.color, this.foreground});

  final String label;
  final String value;

  /// Null means the palette's panel color and text color.
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final foreground = this.foreground ?? context.palette.ink;
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: color ?? context.palette.sage,
          borderRadius: AppTheme.radiusMd,
          border: Border.all(color: foreground.withValues(alpha: 0.22)),
        ),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22, color: foreground)),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}

/// One rounded stacked bar plus a legend. Plain widgets, no chart library.
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.counts});

  final Map<String, int> counts;

  /// Fixed fills, so the legend reads the same in light and dark mode. "Other" uses the
  /// text color, so it stays visible on either background.
  static Map<String, Color> _colors(BuildContext context) => {
    HazardCategory.pothole: AppColors.riskMedium,
    HazardCategory.electrical: AppColors.redOrange,
    HazardCategory.flooding: AppColors.inProgress,
    HazardCategory.obstruction: AppColors.riskLow,
    HazardCategory.lighting: AppColors.sage,
    HazardCategory.other: context.palette.ink,
  };

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final textTheme = Theme.of(context).textTheme;
    if (total == 0) return Text('No reports yet.', style: textTheme.bodySmall);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 18,
            child: Row(
              children: [
                for (final entry in counts.entries)
                  if (entry.value > 0) Expanded(flex: entry.value, child: ColoredBox(color: _colors(context)[entry.key]!)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final entry in counts.entries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _colors(context)[entry.key],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('${entry.key} ${(entry.value * 100 / total).round()}%', style: textTheme.bodySmall),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
