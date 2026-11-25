import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme/app_theme.dart';
import '../../map/map_tiles.dart';
import 'report_draft.dart';
import 'wizard_widgets.dart';

/// Step 1: confirm the hazard location. The pin sits under a fixed crosshair;
/// panning the map moves it, up to 100 m from the GPS fix.
class LocationStep extends StatefulWidget {
  const LocationStep({super.key, required this.draft});

  final ReportDraft draft;

  @override
  State<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<LocationStep> {
  final MapController _map = MapController();
  late final TileProvider _tiles = cachedTileProvider();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    // Snap the map back onto the clamped pin when a drag ends beyond 100 m.
    if (event is! MapEventMoveEnd && event is! MapEventFlingAnimationEnd) return;
    final pin = widget.draft.pin;
    if (pin == null) return;
    if (const Distance().as(LengthUnit.Meter, event.camera.center, pin) > 0.5) {
      _map.move(pin, event.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final fix = draft.fix;
    final pin = draft.pin;
    final textTheme = Theme.of(context).textTheme;
    if (fix == null || pin == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Finding your location...')));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Confirm the hazard location', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: AppTheme.radiusLg,
          child: SizedBox(
            height: 260,
            child: RepaintBoundary(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: pin,
                      initialZoom: 18,
                      minZoom: 15,
                      maxZoom: 19,
                      interactionOptions: radarInteractionOptions,
                      onPositionChanged: (camera, hasGesture) {
                        if (hasGesture) draft.movePin(camera.center);
                      },
                      onMapEvent: _onMapEvent,
                    ),
                    children: [
                      buildRadarTileLayer(tileProvider: _tiles),
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: fix.position,
                            radius: ReportDraft.maxPinShiftMeters,
                            useRadiusInMeter: true,
                            color: Colors.transparent,
                            borderColor: context.palette.ink,
                            borderStrokeWidth: 1.5,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: fix.position,
                            width: 12,
                            height: 12,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: context.palette.ink, shape: BoxShape.circle),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const IgnorePointer(child: Center(child: _Crosshair())),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: draft,
          builder: (context, _) {
            final currentPin = draft.pin ?? pin;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoChip(
                  label: 'GPS accuracy',
                  value: fix.accuracyMeters == null ? 'unknown' : '±${fix.accuracyMeters!.round()} m',
                ),
                InfoChip(label: 'Geohash', value: draft.geohash ?? '-'),
                InfoChip(
                  label: 'Position',
                  value: '${currentPin.latitude.toStringAsFixed(5)}, ${currentPin.longitude.toStringAsFixed(5)}',
                ),
                InfoChip(label: 'Moved', value: '${draft.pinShiftMeters.round()} m'),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Drag the map to move the pin, up to 100 m, if the hazard is across the street or just ahead.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// A rounded crosshair: red-orange with an ink outline.
class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: AppColors.redOrange,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.palette.ink, width: 2),
      ),
    );
  }
}
