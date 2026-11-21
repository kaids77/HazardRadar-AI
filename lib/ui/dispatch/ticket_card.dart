import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../theme/app_theme.dart';
import '../common/status_style.dart';
import '../map/incident_evidence.dart';
import '../map/risk_style.dart';

/// One queue ticket. Shows only the next allowed status step.
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.incident,
    required this.busy,
    required this.onStart,
    required this.onResolve,
    required this.onCrew,
    required this.onOverride,
  });

  final Incident incident;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onResolve;
  final VoidCallback onCrew;
  final VoidCallback onOverride;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final status = statusStyle(context, incident);
    final created = incident.createdAt;
    final active = incident.status == Incident.statusActive;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.paper,
        border: Border(
          left: BorderSide(color: riskColor(incident.riskLevel), width: 5),
          top: BorderSide(color: context.palette.sage),
          right: BorderSide(color: context.palette.sage),
          bottom: BorderSide(color: context.palette.sage),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FlatBadge(
                label: '${incident.riskLevel} · ${incident.category}',
                background: riskColor(incident.riskLevel),
                foreground: incident.riskLevel == 'High' ? AppColors.onRedOrange : AppColors.cream,
              ),
              FlatBadge(label: status.label, background: status.background, foreground: status.foreground),
              FlatBadge(label: incident.reference, background: context.palette.sage, foreground: context.palette.ink),
              if (!incident.aiProcessed)
                FlatBadge(label: 'Offline triage', background: context.palette.sage, foreground: context.palette.ink),
            ],
          ),
          const SizedBox(height: 8),
          Text(incident.aiSummary, style: textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            '${incident.latitude.toStringAsFixed(5)}, ${incident.longitude.toStringAsFixed(5)}'
            '${created == null ? '' : ' · ${formatPhilippineTime(created)}'}'
            ' · ${incident.netVotes >= 0 ? '+' : ''}${incident.netVotes} votes',
            style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
          Text('Crew: ${incident.assignedCrew ?? 'not assigned'}', style: textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: busy ? null : (active ? onStart : onResolve),
                style: ElevatedButton.styleFrom(shape: const RoundedRectangleBorder()),
                child: Text(active ? 'Start work' : 'Resolve'),
              ),
              _Outline(label: 'Crew', onPressed: busy ? null : onCrew),
              _Outline(label: 'Override AI', onPressed: busy ? null : onOverride),
            ],
          ),
        ],
      ),
    );
  }
}

class _Outline extends StatelessWidget {
  const _Outline({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.palette.ink,
        side: BorderSide(color: context.palette.ink),
        shape: const RoundedRectangleBorder(),
      ),
      child: Text(label),
    );
  }
}
