import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../geo/philippines.dart';
import '../../models/chat.dart';
import '../../models/incident.dart';
import '../../models/user_profile.dart';
import '../../services/app_settings.dart';
import '../../services/chat_service.dart';
import '../../services/detour_service.dart';
import '../../services/incident_repository.dart';
import '../../services/location_service.dart';
import '../../services/vote_repository.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_sheet.dart';
import 'incident_sheet.dart';
import 'map_filter.dart';
import 'map_overlays.dart';
import 'map_style.dart';
import 'risk_style.dart';

/// Live map of public hazards (active and in progress), centered on the commuter.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.incidents,
    required this.location,
    required this.profile,
    required this.votes,
    this.settings,
    this.onUpgrade,
    this.chat,
    this.onReport,
    this.detour,
  });

  final IncidentRepository incidents;
  final LocationProvider location;
  final UserProfile profile;
  final VoteRepository votes;

  /// Data saver: when on, sheet photos load only after a tap. Null means photos auto-load.
  final AppSettings? settings;

  /// Opens the Google upgrade when a guest votes. Resolves to the new profile, or null.
  final Future<UserProfile?> Function()? onUpgrade;

  /// Null when the build has no proxy. The Radar AI button is hidden then.
  final ChatService? chat;
  final VoidCallback? onReport;

  /// Null when the build has no proxy. The Safe route button is hidden then.
  final DetourService? detour;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _map = MapController();
  StreamSubscription<List<Incident>>? _subscription;
  ChatController? _chat;

  LatLng? _center;
  LocationFix? _fix;

  /// Latest pins from the stream. Radar AI reads these when a question is sent.
  List<Incident> _latest = const [];
  bool _loadError = false;

  /// Ids seen so far. Null until the first snapshot, so the first load never raises the banner.
  Set<String>? _seen;
  Incident? _alert;

  MapFilter _filter = MapFilter.all;
  String _query = '';

  /// True while waiting for the user to tap a destination for a safe route.
  bool _pickingDestination = false;
  bool _routing = false;
  DetourRoute? _route;

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _startDetour() {
    if (_fix == null) {
      _toast('Turn on location to get a walking route from where you are.');
      return;
    }
    setState(() {
      _pickingDestination = true;
      _route = null;
    });
  }

  Future<void> _planDetour(LatLng destination) async {
    final detour = widget.detour;
    final from = _fix?.position;
    if (detour == null || from == null) return;
    setState(() {
      _pickingDestination = false;
      _routing = true;
    });
    try {
      final route = await detour.route(from: from, to: destination, hazards: _latest);
      if (!mounted) return;
      setState(() => _route = route);
      _map.fitCamera(CameraFit.coordinates(coordinates: route.path, padding: const EdgeInsets.all(60)));
    } on DetourUnavailable catch (failure) {
      if (mounted) _toast(failure.message);
    } catch (_) {
      if (mounted) _toast('Could not plan a route. Avoid the red pins and stay on main roads.');
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final chat = widget.chat;
    if (chat != null) _chat = ChatController(chat);
    _subscription = widget.incidents.watchActivePublic().listen(_onIncidents, onError: (_) {
      if (mounted) setState(() => _loadError = true);
    });
    _locate();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _chat?.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    final fix = await widget.location.currentFix();
    if (!mounted) return;
    final position = fix?.position;
    setState(() {
      _fix = fix;
      _center ??= position != null && philippinesBounds.contains(position)
          ? position
          : GeolocatorLocationService.fallbackCenter;
    });
  }

  void _onIncidents(List<Incident> incidents) {
    if (!mounted) return;
    setState(() {
      _loadError = false;
      final seen = _seen;
      if (seen != null) {
        final fresh = newHighRisk(seen, incidents);
        if (fresh.isNotEmpty) _alert = fresh.first;
      }
      _seen = {...?seen, for (final incident in incidents) incident.id};
      _latest = incidents;
    });
  }

  Future<void> _recenter() async {
    await _locate();
    final position = _fix?.position;
    if (!mounted) return;
    if (position == null || !philippinesBounds.contains(position)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location is off.')));
      return;
    }
    _map.move(position, 16);
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
      case PlanDetour():
        _startDetour();
      case ShowOnMap(:final incidentId):
        final incident = _latest.where((i) => i.id == incidentId).firstOrNull;
        if (incident != null) _focus(incident);
    }
  }

  void _focus(Incident incident) {
    _map.move(LatLng(incident.latitude, incident.longitude), 17);
    _openIncident(incident);
  }

  void _openIncident(Incident incident) {
    showIncidentSheet(
      context,
      incident: incident,
      profile: widget.profile,
      incidents: widget.incidents,
      votes: widget.votes,
      location: widget.location,
      autoLoadPhoto: !(widget.settings?.dataSaver ?? false),
      onUpgrade: widget.onUpgrade,
    );
  }

  String get _gpsLabel {
    final fix = _fix;
    if (fix == null) return 'GPS off · showing Mandaue City';
    final accuracy = fix.accuracyMeters;
    return accuracy == null ? 'GPS on' : 'GPS ±${accuracy.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    final center = _center;
    if (center == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.redOrange));
    }
    final shown = applyMapFilter(
      [for (final i in _latest) if (philippinesBounds.contains(LatLng(i.latitude, i.longitude))) i],
      _filter,
      _query,
    );
    final alert = _alert;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15,
            minZoom: 5,
            cameraConstraint: CameraConstraint.contain(bounds: philippinesBounds),
            onTap: (_, point) {
              if (_pickingDestination) _planDetour(point);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.hazardradarai',
              tileBuilder: tintedTileBuilder,
            ),
            if (_route case final route?)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: route.path,
                    strokeWidth: 6,
                    color: AppColors.sage,
                    borderColor: AppColors.ink,
                    borderStrokeWidth: 1.5,
                  ),
                ],
              ),
            if (_fix != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _fix!.position,
                    width: 14,
                    height: 14,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.cream, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            MarkerLayer(markers: [for (final incident in shown) _markerFor(incident)]),
            RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: MapSearchField(onChanged: (value) => setState(() => _query = value))),
                  if (_chat != null) ...[
                    const SizedBox(width: 8),
                    _RadarButton(onPressed: _openChat),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              MapFilterChips(
                incidents: _latest,
                selected: _filter,
                onSelected: (filter) => setState(() => _filter = filter),
              ),
              if (alert != null) ...[
                const SizedBox(height: 8),
                NewHighRiskBanner(
                  incident: alert,
                  onOpen: () {
                    setState(() => _alert = null);
                    _focus(alert);
                  },
                  onDismiss: () => setState(() => _alert = null),
                ),
              ],
              if (_loadError) ...[
                const SizedBox(height: 8),
                const MapLabel(text: 'Could not load hazards. Pins may be out of date.'),
              ],
            ],
          ),
        ),
        Positioned(
          left: 12,
          bottom: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MapLegend(),
              const SizedBox(height: 8),
              MapLabel(text: _gpsLabel),
              const SizedBox(height: 8),
              MapSquareButton(icon: Icons.my_location, tooltip: 'Recenter on me', onPressed: _recenter),
              if (widget.detour != null) ...[
                const SizedBox(height: 8),
                MapSquareButton(icon: Icons.alt_route, tooltip: 'Safe walking route', onPressed: _startDetour),
              ],
            ],
          ),
        ),
        if (_pickingDestination || _routing || _route != null)
          Positioned(
            left: 76,
            right: 12,
            bottom: 96,
            child: _RoutePanel(
              text: _routing
                  ? 'Finding a safe walking route...'
                  : _pickingDestination
                      ? 'Tap your destination on the map.'
                      : _route!.summary,
              actionLabel: _routing ? null : (_pickingDestination ? 'Cancel' : 'Clear route'),
              onAction: () => setState(() {
                _pickingDestination = false;
                _route = null;
              }),
            ),
          ),
      ],
    );
  }

  Marker _markerFor(Incident incident) {
    return Marker(
      point: LatLng(incident.latitude, incident.longitude),
      // 44 px tap target around a 28 px pin.
      width: 44,
      height: 44,
      child: Semantics(
        button: true,
        label: '${incident.riskLevel} risk: ${incident.category}, ${incident.status == Incident.statusInProgress ? 'in progress' : 'active'}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openIncident(incident),
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: pinColor(incident),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cream, width: 2),
              ),
              child: Icon(categoryIcon(incident.category), size: 16, color: pinIconColor(incident)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat route status block with one action (Cancel or Clear route).
class _RoutePanel extends StatelessWidget {
  const _RoutePanel({required this.text, required this.actionLabel, required this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.cream,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Container(width: 12, height: 12, color: AppColors.sage, margin: const EdgeInsets.only(right: 8)),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: AppColors.ink, shape: const RoundedRectangleBorder()),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Flat sage block next to the search field.
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Text('Ask Radar AI', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.ink)),
        ),
      ),
    );
  }
}
