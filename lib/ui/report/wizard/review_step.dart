import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../common/feedback.dart';
import '../../common/status_style.dart';
import '../../map/risk_style.dart';
import 'report_draft.dart';

/// Step 4: the AI triage result, shown before the report is published.
class ReviewStep extends StatelessWidget {
  const ReviewStep({super.key, required this.draft, required this.onRetry, this.error});

  final ReportDraft draft;
  final VoidCallback onRetry;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final result = draft.triage;
    if (result == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                const Text('Radar AI is reading your note...'),
              ] else ...[
                FeedbackMessage.error(error!),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Check the AI result', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FlatBadge(
              label: '${result.riskLevel} risk',
              background: riskColor(result.riskLevel),
              foreground: result.riskLevel == 'High' ? AppColors.onRedOrange : AppColors.cream,
            ),
            FlatBadge(
              label: result.aiProcessed ? 'Classified by Radar AI' : 'Classified offline',
              background: context.palette.sage,
              foreground: context.palette.ink,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          result.category,
          style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 28, color: context.palette.ink),
        ),
        const SizedBox(height: 8),
        Text(result.aiSummary, style: textTheme.bodyLarge),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.redOrange, width: 3))),
          child: Text('Recommended action: ${result.recommendedAction}', style: textTheme.bodyMedium),
        ),
        if (!result.aiProcessed) ...[
          const SizedBox(height: 12),
          Text(
            'Radar AI was not reachable, so the phone classified this from your words. '
            'The AI will check it again when you are back online.',
            style: textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        Text('Go back to change the note if this looks wrong.', style: textTheme.bodySmall),
      ],
    );
  }
}
