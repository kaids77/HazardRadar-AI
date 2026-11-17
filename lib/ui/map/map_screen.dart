import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../geo/philippines.dart';
import '../../models/incident.dart';
import '../../services/incident_repository.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import 'map_style.dart';
import 'risk_style.dart';

/// Live map of active public hazards, centered on the commuter's location.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.incidents,
    required this.location,
  });

  final IncidentRepository incidents;
  final LocationProvider location;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final Future<LatLng> _center;
  late final Stream<List<Incident>> _incidentStream;

  @override
  void initState() {
    super.initState();
    _center = widget.location.currentOrFallback();
    _incidentStream = widget.incidents.watchActivePublic();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LatLng>(
      future: _center,
      builder: (context, centerSnapshot) {
        if (!centerSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.redOrange));
        }
        return StreamBuilder<List<Incident>>(
          stream: _incidentStream,
          builder: (context, incidentSnapshot) {
            final incidents = incidentSnapshot.data ?? const <Incident>[];
            return Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: philippinesBounds.contains(centerSnapshot.data!)
                        ? centerSnapshot.data!
                        : GeolocatorLocationService.fallbackCenter,
                    initialZoom: 15,
                    minZoom: 5,
                    cameraConstraint: CameraConstraint.contain(bounds: philippinesBounds),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.hazardradarai',
                      tileBuilder: tintedTileBuilder,
                    ),
                    MarkerLayer(
                      markers: [
                        for (final incident in incidents)
                          if (philippinesBounds.contains(LatLng(incident.latitude, incident.longitude)))
                            _markerFor(incident),
                      ],
                    ),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                if (incidentSnapshot.hasError)
                  const Positioned(
                    left: 16,
                    right: 16,
                    top: 16,
                    child: _Notice(text: 'Could not load hazards. Pins may be out of date.'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Marker _markerFor(Incident incident) {
    return Marker(
      point: LatLng(incident.latitude, incident.longitude),
      width: 26,
      height: 26,
      child: Semantics(
        label: '${incident.riskLevel} risk: ${incident.category}',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: riskColor(incident.riskLevel),
            shape: BoxShape.circle,
            border: Border.fromBorderSide(BorderSide(color: AppColors.cream, width: 3)),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.sage),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink),
        ),
      ),
    );
  }
}
