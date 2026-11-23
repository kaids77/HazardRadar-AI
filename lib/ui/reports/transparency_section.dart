import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';

import '../../models/transparency_entry.dart';
import '../../theme/app_theme.dart';
import '../common/feedback.dart';
import '../common/pagination.dart';
import '../common/status_style.dart';
import '../map/incident_evidence.dart';
import '../map/risk_style.dart';

enum TransparencyFilter { all, resolved, quarantined }

extension on TransparencyFilter {
  String get label => switch (this) {
        TransparencyFilter.all => 'All',
        TransparencyFilter.resolved => 'Resolved',
        TransparencyFilter.quarantined => 'Quarantined',
      };

  bool matches(TransparencyEntry e) => switch (this) {
        TransparencyFilter.all => true,
        TransparencyFilter.resolved => e.isResolved,
        TransparencyFilter.quarantined => e.isModeration,
      };
}

/// "Report transparency" at the bottom of My Reports, for every user: city-wide reports
/// that were resolved (with the crew and the city's note) or moderated (quarantined,
/// restored, or removed as spam, with the reason).
class TransparencySection extends StatefulWidget {
  const TransparencySection({super.key, required this.entries, required this.counts});

  /// The newest entries. The parent re-creates it on pull-to-refresh.
  final Stream<List<TransparencyEntry>> entries;

  /// Totals beyond the newest entries. Null while loading or when it failed.
  final Future<({int resolved, int quarantined})> counts;

  @override
  State<TransparencySection> createState() => _TransparencySectionState();
}

class _TransparencySectionState extends State<TransparencySection> {
  TransparencyFilter _filter = TransparencyFilter.all;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Report transparency', style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22)),
        const SizedBox(height: 4),
        Text(
          'Reports the city resolved and reports moderators took off the map, for everyone to see.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        FutureBuilder<({int resolved, int quarantined})>(
          future: widget.counts,
          builder: (context, totals) {
            final data = totals.data;
            String count(TransparencyFilter f) => switch (f) {
                  TransparencyFilter.all => '',
                  TransparencyFilter.resolved => data == null ? '' : ' (${data.resolved})',
                  TransparencyFilter.quarantined => data == null ? '' : ' (${data.quarantined})',
                };
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in TransparencyFilter.values)
                  ChoiceChip(
                    label: Text('${f.label}${count(f)}'),
                    selected: _filter == f,
                    onSelected: (_) => setState(() {
                      _filter = f;
                      _page = 0;
                    }),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<TransparencyEntry>>(
          stream: widget.entries,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              if (kDebugMode) debugPrint('Transparency load error: ${snapshot.error}');
              return const FeedbackMessage.error('Could not load the transparency log. Pull down to try again.');
            }
            if (!snapshot.hasData) {
              return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
            }
            final shown = snapshot.data!.where(_filter.matches).toList();
            if (shown.isEmpty) {
              return Text(
                switch (_filter) {
                  TransparencyFilter.resolved => 'No resolved reports yet.',
                  TransparencyFilter.quarantined => 'No quarantined reports.',
                  TransparencyFilter.all => 'No resolved or quarantined reports yet.',
                },
                style: textTheme.bodyMedium,
              );
            }
            final page = paginate(shown, page: _page);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in page.items) ...[_EntryCard(entry: entry), const SizedBox(height: 8)],
                PaginationBar(page: page, onPageChanged: (next) => setState(() => _page = next)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final TransparencyEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final at = entry.at;
    final reason = entry.reasonLabel;
    final kindColors = entry.isResolved
        ? (background: palette.sage, foreground: palette.ink)
        : (background: palette.ink, foreground: palette.paper);
    return Container(
      decoration: BoxDecoration(
        color: palette.paper,
        border: Border(
          left: BorderSide(color: riskColor(entry.riskLevel), width: 4),
          top: BorderSide(color: palette.sage),
          right: BorderSide(color: palette.sage),
          bottom: BorderSide(color: palette.sage),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FlatBadge(label: entry.kindLabel, background: kindColors.background, foreground: kindColors.foreground),
              FlatBadge(
                label: '${entry.riskLevel} risk',
                background: riskColor(entry.riskLevel),
                foreground: entry.riskLevel == 'High' ? AppColors.onRedOrange : AppColors.cream,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${entry.category} · ${entry.reference}', style: textTheme.titleSmall),
          if (at != null) Text(formatPhilippineTime(at), style: textTheme.bodySmall),
          if (entry.isResolved) ...[
            const SizedBox(height: 4),
            if (entry.reporterName case final name?) Text('Reported by $name', style: textTheme.bodyMedium),
            Text('Crew: ${entry.crew.isEmpty ? 'not recorded' : entry.crew}', style: textTheme.bodyMedium),
            if (entry.resolutionNote.isNotEmpty) Text('City note: ${entry.resolutionNote}', style: textTheme.bodyMedium),
          ],
          if (reason != null) ...[
            const SizedBox(height: 4),
            Text(reason, style: textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
