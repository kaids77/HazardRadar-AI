import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../geo/philippines.dart';
import '../../models/chat.dart';
import '../../models/incident.dart';
import '../../models/user_profile.dart';
import '../../services/chat_service.dart';
import '../../services/incident_repository.dart';
import '../../services/location_service.dart';
import '../../services/vote_repository.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_sheet.dart';
import 'incident_sheet.dart';
import 'map_style.dart';
import 'risk_style.dart';

/// Live map of active public hazards, centered on the commuter's location.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.incidents,
    required this.location,
    required this.profile,
    required this.votes,
    this.chat,
    this.onReport,
  });

  final IncidentRepository incidents;
  final LocationProvider location;
  final UserProfile profile;
  final VoteRepository votes;

  /// Null when the build has no proxy. The Radar AI button is hidden then.
  final ChatService? chat;
  final VoidCallback? onReport;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final Future<LatLng> _center;
  late final Stream<List<Incident>> _incidentStream;
  final MapController _map = MapController();
  ChatController? _chat;

  /// Latest pins from the stream. Radar AI reads these when a question is sent.
  List<Incident> _latest = const [];

  @override
  void initState() {
    super.initState();
    _center = widget.location.currentOrFallback();
    _incidentStream = widget.incidents.watchActivePublic();
    final chat = widget.chat;
    if (chat != null) _chat = ChatController(chat);
  }

  @override
  void dispose() {
    _chat?.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _openChat() async {
    final chat = _chat;
    if (chat == null) return;
    final action = await showChatSheet(
      context,
      controller: chat,
      incidents: () => _latest,
      around: () => _map.camera.center,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case OpenReport():
        widget.onReport?.call();
      case ShowOnMap(:final incidentId):
        final incident = _latest.where((i) => i.id == incidentId).firstOrNull;
        if (incident == null) return;
        _map.move(LatLng(incident.latitude, incident.longitude), 17);
        _openIncident(incident);
    }
  }

  void _openIncident(Incident incident) {
    showIncidentSheet(
      context,
      incident: incident,
      profile: widget.profile,
      incidents: widget.incidents,
      votes: widget.votes,
      location: widget.location,
    );
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
            _latest = incidents;
            return Stack(
              children: [
                FlutterMap(
                  mapController: _map,
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
                if (_chat != null)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: _RadarButton(onPressed: _openChat),
                  ),
                if (incidentSnapshot.hasError)
                  Positioned(
                    left: 16,
                    right: _chat == null ? 16 : 160,
                    top: 16,
                    child: const _Notice(text: 'Could not load hazards. Pins may be out of date.'),
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
      // 44 px tap target around a 26 px dot.
      width: 44,
      height: 44,
      child: Semantics(
        button: true,
        label: '${incident.riskLevel} risk: ${incident.category}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openIncident(incident),

          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: riskColor(incident.riskLevel),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cream, width: 3),
              ),
            ),
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

/// Flat sage block in the top-right corner of the map.
class _RadarButton extends StatelessWidget {
  const _RadarButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.sage,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text('Ask Radar AI', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.ink)),
        ),
      ),
    );
  }
}
