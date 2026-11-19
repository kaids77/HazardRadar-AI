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
      decoration: const BoxDecoration(border: Border.fromBorderSide(BorderSide(color: AppColors.ink))),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Photo storage (Firestore free tier)', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          SizedBox(
            height: 10,
            child: LinearProgressIndicator(
              value: e?.fraction,
              backgroundColor: AppColors.sage,
              color: warn ? AppColors.redOrange : AppColors.ink,
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
