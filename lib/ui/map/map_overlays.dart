import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../theme/app_theme.dart';
import 'map_filter.dart';

/// Rounded search field: filters pins by HZD reference or category, on the device.
class MapSearchField extends StatelessWidget {
  const MapSearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.paper,
      borderRadius: AppTheme.radiusMd,
      clipBehavior: Clip.antiAlias,
      child: TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search: high risk, pothole, HZD id',
          prefixIcon: Icon(Icons.search, color: context.palette.ink),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: AppTheme.radiusMd,
            borderSide: BorderSide(color: context.palette.ink.withValues(alpha: 0.45), width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusMd,
            borderSide: BorderSide(color: context.palette.ink.withValues(alpha: 0.45), width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppTheme.radiusMd,
            borderSide: BorderSide(color: context.palette.ink, width: 1.6),
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling filter chips with live counts.
class MapFilterChips extends StatelessWidget {
  const MapFilterChips({super.key, required this.incidents, required this.selected, required this.onSelected});

  final List<Incident> incidents;
  final MapFilter selected;
  final ValueChanged<MapFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final chip in MapFilter.chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${chip.label} ${incidents.where(chip.matches).length}'),
                selected: chip == selected,
                onSelected: (_) => onSelected(chip),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small flat legend for the pin colors.
class MapLegend extends StatelessWidget {
  const MapLegend({super.key});

  static const _entries = [
    ('Low', AppColors.riskLow),
    ('Medium', AppColors.riskMedium),
    ('High', AppColors.riskHigh),
    ('In progress', AppColors.inProgress),
  ];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.paper,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: context.palette.ink.withValues(alpha: 0.28), width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, color) in _entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(label, style: style),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A rounded map action button, sage with an ink icon and subtle border.
class MapSquareButton extends StatelessWidget {
  const MapSquareButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: context.palette.sage,
        shape: RoundedRectangleBorder(
          borderRadius: AppTheme.radiusMd,
          side: BorderSide(color: context.palette.ink.withValues(alpha: 0.3), width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppTheme.radiusMd,
          child: SizedBox(width: 48, height: 48, child: Icon(icon, color: context.palette.ink)),
        ),
      ),
    );
  }
}

/// A rounded label block, for the GPS chip and notices.
class MapLabel extends StatelessWidget {
  const MapLabel({super.key, required this.text, this.color, this.textColor});

  final String text;

  /// Null means the palette's panel color.
  final Color? color;

  /// Null means the palette's text color.
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? context.palette.sage,
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: (textColor ?? context.palette.ink).withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: textColor ?? context.palette.ink)),
    );
  }
}

/// Rounded red-orange alert for a High-risk hazard. Used for a new report after the map
/// loaded, and for a High hazard within 100 m of the commuter.
class NewHighRiskBanner extends StatelessWidget {
  const NewHighRiskBanner({
    super.key,
    required this.incident,
    required this.onOpen,
    required this.onDismiss,
    this.title = 'New high-risk report',
    this.detail,
    this.dismissTooltip = 'Dismiss',
  });

  final Incident incident;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final String title;

  /// Defaults to "category · reference. Tap to open."
  final String? detail;
  final String dismissTooltip;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.riskHigh,
      borderRadius: AppTheme.radiusMd,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        borderRadius: AppTheme.radiusMd,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.labelLarge?.copyWith(color: AppColors.onError)),
                    Text(
                      detail ?? '${incident.category} · ${incident.reference}. Tap to open.',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.onError),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: dismissTooltip,
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: AppColors.onError),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
