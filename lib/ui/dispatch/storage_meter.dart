import 'package:flutter/material.dart';

import '../../services/moderation_repository.dart';
import '../../theme/app_theme.dart';

/// Flat bar showing estimated photo storage against the free 1 GiB.
class StorageMeter extends StatelessWidget {
  const StorageMeter({super.key, required this.estimate});

  /// Null while loading.
  final StorageEstimate? estimate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final e = estimate;
    final mb = e == null ? null : e.usedBytes / (1024 * 1024);
    final warn = e != null && e.fraction >= 0.8;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.paper,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: context.palette.ink.withValues(alpha: 0.25), width: 1.2),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Photo storage (Firestore free tier)', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: LinearProgressIndicator(
                value: e?.fraction,
                backgroundColor: context.palette.sage,
                color: warn ? AppColors.redOrange : context.palette.ink,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            e == null
                ? 'Estimating...'
                : '${mb!.toStringAsFixed(1)} MB of 1,024 MB (${(e.fraction * 100).toStringAsFixed(1)}%) · '
                    '${e.reports} reports · about ${e.uploadsRemaining} more uploads',
            style: textTheme.bodySmall,
          ),
          if (warn) Text('Storage is getting full. Purge spam to free space.', style: textTheme.bodySmall),
        ],
      ),
    );
  }
}
