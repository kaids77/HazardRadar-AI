import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

const int defaultPageSize = 5;

/// One page of a list, with a clamped 0-based [page] index so shrinking a list
/// (through a filter, search, or action) never leaves the screen on an empty page.
class PageSlice<T> {
  const PageSlice({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.total,
    required this.start,
    required this.end,
  });

  final List<T> items;
  final int page;
  final int totalPages;
  final int total;
  final int start;
  final int end;

  bool get hasPrevious => page > 0;
  bool get hasNext => page < totalPages - 1;
}

PageSlice<T> paginate<T>(List<T> all, {required int page, int pageSize = defaultPageSize}) {
  if (all.isEmpty) {
    return const PageSlice(items: [], page: 0, totalPages: 1, total: 0, start: 0, end: 0);
  }
  final totalPages = (all.length + pageSize - 1) ~/ pageSize;
  final clamped = page.clamp(0, totalPages - 1);
  final start = clamped * pageSize;
  final end = (start + pageSize).clamp(0, all.length);
  return PageSlice(
    items: all.sublist(start, end),
    page: clamped,
    totalPages: totalPages,
    total: all.length,
    start: start,
    end: end,
  );
}

/// Flat poster page controls shown under a paginated list.
class PaginationBar<T> extends StatelessWidget {
  const PaginationBar({super.key, required this.page, required this.onPageChanged});

  final PageSlice<T> page;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    if (page.total == 0) return const SizedBox.shrink();
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: palette.ink,
      side: BorderSide(color: palette.ink.withValues(alpha: 0.45), width: 1.2),
      shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusSm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      visualDensity: VisualDensity.compact,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: page.hasPrevious ? () => onPageChanged(page.page - 1) : null,
            style: buttonStyle,
            child: const Text('Previous'),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Page ${page.page + 1} of ${page.totalPages} (${page.start + 1}–${page.end} of ${page.total})',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: page.hasNext ? () => onPageChanged(page.page + 1) : null,
            style: buttonStyle,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}
