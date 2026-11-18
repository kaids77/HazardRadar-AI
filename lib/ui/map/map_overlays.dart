import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../theme/app_theme.dart';
import 'map_filter.dart';

/// Flat cream search field: filters pins by HZD reference or category, on the device.
class MapSearchField extends StatelessWidget {
  const MapSearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream,
      child: TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Search HZD id or category',
          prefixIcon: Icon(Icons.search, color: AppColors.ink),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.ink)),
          enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.ink)),
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
      color: AppColors.cream,
      padding: const EdgeInsets.all(8),
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
                  Container(width: 12, height: 12, color: color),
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

/// A flat square map button, sage with an ink icon.
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
        color: AppColors.sage,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(width: 48, height: 48, child: Icon(icon, color: AppColors.ink)),
        ),
      ),
    );
  }
}

/// A flat label block, for the GPS chip and notices.
class MapLabel extends StatelessWidget {
  const MapLabel({super.key, required this.text, this.color = AppColors.sage});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.ink)),
    );
  }
}

/// Shown once when a new High-risk report appears after the map loaded.
class NewHighRiskBanner extends StatelessWidget {
  const NewHighRiskBanner({super.key, required this.incident, required this.onOpen, required this.onDismiss});

  final Incident incident;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.redOrange,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New high-risk report', style: textTheme.labelLarge?.copyWith(color: AppColors.onRedOrange)),
                    Text(
                      '${incident.category} · ${incident.reference}. Tap to open.',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.onRedOrange),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: AppColors.onRedOrange),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
