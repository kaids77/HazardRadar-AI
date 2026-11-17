import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/incident.dart';
import '../../services/incident_repository.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
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
                    initialCenter: centerSnapshot.data!,
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.hazardradarai',
                    ),
                    MarkerLayer(
                      markers: [for (final incident in incidents) _markerFor(incident)],
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
      width: 24,
      height: 24,
      child: Semantics(
        label: '${incident.riskLevel} risk: ${incident.category}',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: riskColor(incident.riskLevel),
            shape: BoxShape.circle,
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
      decoration: const BoxDecoration(color: AppColors.cream),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
