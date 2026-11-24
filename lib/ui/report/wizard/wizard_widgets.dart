import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'report_draft.dart';

const List<String> wizardStepTitles = ['Location', 'Photo', 'Notes', 'AI review'];

/// Four flat bars: ink for done, red-orange for the current step, sage for the rest.
class WizardStepper extends StatelessWidget {
  const WizardStepper({super.key, required this.step});

  final WizardStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final s in WizardStep.values) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: 6,
                    decoration: BoxDecoration(
                      color: s.index < step.index
                          ? context.palette.ink
                          : s == step
                              ? Theme.of(context).colorScheme.primary
                              : context.palette.sage,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (s != WizardStep.values.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Step ${step.index + 1} of 4: ${wizardStepTitles[step.index]}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

/// A small rounded label/value block for telemetry such as accuracy or geohash.
class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.sage,
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: context.palette.ink.withValues(alpha: 0.22)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: textTheme.labelSmall),
          Text(value, style: textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
