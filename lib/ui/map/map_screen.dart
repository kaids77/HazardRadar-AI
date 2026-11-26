import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../geo/philippines.dart';
import '../../models/chat.dart';
import '../../models/incident.dart';
import '../../models/transparency_entry.dart';
import '../../models/user_profile.dart';
import '../../services/app_settings.dart';
import '../../services/chat_service.dart';
import '../../services/detour_service.dart';
import '../../services/incident_repository.dart';
import '../../services/location_service.dart';
import '../../services/transparency_repository.dart';
import '../../services/vote_repository.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_sheet.dart';
import '../common/feedback.dart';
import 'incident_sheet.dart';
import 'map_filter.dart';
import 'map_overlays.dart';
import 'map_tiles.dart';
import 'pin_clusters.dart';
import 'proximity_alert.dart';
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
    this.transparency,
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

  /// The public transparency log, so Radar AI can answer resolved and quarantined questions.
  final TransparencyRepository? transparency;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final MapController _map = MapController();
  late final TileProvider _tiles = cachedTileProvider();
  AnimationController? _cameraAnim;
  StreamSubscription<List<Incident>>? _subscription;
  StreamSubscription<List<TransparencyEntry>>? _transparencySub;
  StreamSubscription<LocationFix>? _moves;
  ChatController? _chat;

  /// Latest transparency entries kept warm from the live Firestore stream so Radar AI
  /// always sees newly resolved or quarantined reports immediately.
  List<TransparencyEntry> _recentTransparency = const [];

  LatLng? _center;
  LocationFix? _fix;

  /// Whole-number zoom used for clustering. Pins regroup only when it changes.
  /// Stored in a [ValueNotifier] so crossing a zoom threshold only rebuilds the
  /// cluster [MarkerLayer] instead of the entire [MapScreen] and overlays.
  final ValueNotifier<double> _clusterZoom = ValueNotifier<double>(_initialZoom);
  static const double _initialZoom = 15;

  /// High hazards already announced as nearby. The map stays alive in the home
  /// IndexedStack, so this lasts for the session and each hazard alerts once.
  final Set<String> _warned = {};
  NearbyHazard? _nearby;

  /// Latest pins from the stream. Radar AI reads these when a question is sent.
  List<Incident> _latest = const [];

  /// Pins from [_latest] that lie inside [philippinesBounds], computed once per snapshot.
  List<Incident> _boundedIncidents = const [];

  /// Memoized filtered pins and built markers so unrelated state updates (e.g. GPS accuracy,
  /// route picking) reuse the existing [MarkerLayer] and its cached Web Mercator projection.
  List<Incident>? _cachedBoundedSource;
  MapFilter? _cachedFilter;
  String? _cachedQuery;
  List<Incident> _cachedShown = const [];

  List<Incident>? _cachedMarkerShown;
  double? _cachedMarkerZoom;
  Color? _cachedMarkerPaper;
  List<Marker> _cachedMarkers = const [];
  bool _loadError = false;

  /// The real error text, shown only in debug builds.
  String? _loadErrorDetail;

  /// Ids seen so far. Null until the first snapshot, so the first load never raises the banner.
  Set<String>? _seen;
  Incident? _alert;

  MapFilter _filter = MapFilter.all;
  String _query = '';
  Timer? _searchDebounce;
  Timer? _retryTimer;

  /// True while waiting for the user to tap a destination for a safe route.
  bool _pickingDestination = false;
  bool _routing = false;
  DetourRoute? _route;

  /// Every map notice is a problem the user can fix (location off, no route, no match).
  void _toast(String message) => showError(context, message);

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
      final shown = [...route.path, ...?route.riskyDirect?.path];
      _map.fitCamera(CameraFit.coordinates(coordinates: shown, padding: const EdgeInsets.all(60)));
    } on DetourUnavailable catch (failure) {
      if (mounted) _toast(failure.message);
    } catch (_) {
      if (mounted) _toast('Could not plan a route. Avoid the red pins and stay on main roads.');
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  /// Active and in-progress counts from the loaded pins, plus resolved and quarantined
  /// totals and the newest entries from the public transparency log.
  Future<ReportStatusSummary> _statusSummary() async {
    final active = _latest.where((i) => i.status == Incident.statusActive).length;
    final inProgress = _latest.where((i) => i.status == Incident.statusInProgress).length;
    final log = widget.transparency;
    if (log == null) return ReportStatusSummary(active: active, inProgress: inProgress);
    var recent = _recentTransparency;
    try {
      if (recent.isEmpty) {
        recent = await log.watchRecent(limit: ReportStatusSummary.maxRecent).first;
        _recentTransparency = recent;
      }
      final counts = await log.counts();
      return ReportStatusSummary(
        active: active,
        inProgress: inProgress,
        resolved: counts.resolved,
        quarantined: counts.quarantined,
        recent: recent,
      );
    } on Object {
      return ReportStatusSummary(
        active: active,
        inProgress: inProgress,
        resolved: recent.isEmpty ? null : recent.where((e) => e.isResolved).length,
        quarantined: recent.isEmpty ? null : recent.where((e) => e.kind == TransparencyEntry.kindQuarantined).length,
        recent: recent,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final chat = widget.chat;
    if (chat != null) _chat = ChatController(chat, statusSummary: _statusSummary);
    _subscribe();
    // Start following the commuter only after the first fix request finishes, so the two
    // permission prompts never overlap. Always listen so a later GPS lock updates the map.
    _locate(followIfMoved: true).then((_) {
      if (mounted) _moves = widget.location.watchFix().listen(_onMove);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_locate(followIfMoved: true));
      _moves ??= widget.location.watchFix().listen(_onMove);
    }
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid || (_loadError && oldWidget.profile != widget.profile)) {
      _subscribe();
    }
    if (oldWidget.profile != widget.profile) {
      unawaited(_locate(followIfMoved: true));
    }
  }

  /// (Re)subscribes to the live pins. A Firestore stream stops after an error, so the
  /// load-error label calls this to start a fresh one. Seen ids are kept, so the
  /// re-sent snapshot never raises a false "new high-risk report" banner.
  void _subscribe() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    _transparencySub?.cancel();
    if (_loadError) setState(() => _loadError = false);
    final log = widget.transparency;
    if (log != null) {
      _transparencySub = log.watchRecent(limit: ReportStatusSummary.maxRecent).listen(
        (entries) {
          if (mounted) _recentTransparency = entries;
        },
        onError: (_) {},
      );
    }
    _subscription = widget.incidents.watchActivePublic().listen(_onIncidents, onError: (Object error) {
      if (!mounted) return;
      final text = '$error';
      // Signing out briefly sets auth to null before the new guest session starts, which
      // cancels the old stream with permission-denied. Retry once quietly after auth settles.
      if (text.contains('permission-denied') && _retryTimer == null) {
        _retryTimer = Timer(const Duration(milliseconds: 600), () {
          _retryTimer = null;
          if (mounted) _subscribe();
        });
        return;
      }
      if (kDebugMode) debugPrint('Radar map load error: $error');
      setState(() {
        _loadError = true;
        _loadErrorDetail = text;
      });
    });
  }

  /// Moves the camera to the pins that match the search text and filter chip. A single
  /// match is centered at street zoom. Nothing happens for "All" with an empty search.
  void _flyToMatches() {
    if (_filter == MapFilter.all && _query.trim().isEmpty) return;
    final matches = _shownIncidents();
    if (matches.isEmpty) {
      _toast('No matching hazards on the map.');
      return;
    }
    final points = [for (final i in matches) LatLng(i.latitude, i.longitude)];
    if (points.length == 1) {
      _animateMove(points.single, 17);
      return;
    }
    _cancelCameraAnimation();
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        // Extra room at the top for the search box and chips, and at the bottom for the legend.
        padding: const EdgeInsets.fromLTRB(40, 170, 40, 120),
        maxZoom: 17,
      ),
    );
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    // Wait until typing pauses, so the map does not jump on every letter.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _flyToMatches();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _searchDebounce?.cancel();
    _subscription?.cancel();
    _transparencySub?.cancel();
    _moves?.cancel();
    _chat?.dispose();
    _cameraAnim?.dispose();
    _clusterZoom.dispose();
    _map.dispose();
    super.dispose();
  }

  /// Distance in meters that triggers recentering the map when a fresher GPS fix arrives
  /// (for example moving from home to school, or replacing a cached fix with a live one).
  static const double _relocateMeters = 30;

  void _onMove(LocationFix fix) {
    if (!mounted) return;
    final previous = _fix?.position;
    final next = fix.position;
    final valid = philippinesBounds.contains(next);
    final moved = valid &&
        (previous == null || const Distance().as(LengthUnit.Meter, previous, next) >= _relocateMeters);
    setState(() {
      _fix = fix;
      if (valid) _center = next;
      _updateNearby();
    });
    if (moved) _moveCamera(next);
  }

  /// Call inside setState. Shows the closest unannounced High hazard within 100 m,
  /// and drops the alert when that hazard leaves the map (resolved or quarantined).
  void _updateNearby() {
    final current = _nearby;
    if (current != null && !_latest.any((i) => i.id == current.incident.id)) _nearby = null;
    final me = _fix?.position;
    if (me == null || _nearby != null) return;
    final hit = nearestUnwarnedHigh(me, _latest, _warned);
    if (hit == null) return;
    _warned.add(hit.incident.id);
    _nearby = hit;
  }

  void _onCamera(MapCamera camera, bool hasGesture) {
    if (hasGesture) _cancelCameraAnimation();
    final zoom = (camera.zoom >= clusterMaxZoom ? clusterMaxZoom : camera.zoom).floorToDouble();
    if (zoom == _clusterZoom.value) return;
    // The camera can settle during layout; never notify listeners in the middle of a build.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clusterZoom.value = zoom;
      });
    } else {
      _clusterZoom.value = zoom;
    }
  }

  Future<void> _locate({bool followIfMoved = false}) async {
    final fix = await widget.location.currentFix();
    if (!mounted) return;
    final previous = _fix?.position;
    final position = fix?.position;
    final valid = position != null && philippinesBounds.contains(position);
    final hadCenter = _center != null;
    final moved = valid &&
        (previous == null || const Distance().as(LengthUnit.Meter, previous, position) >= _relocateMeters);
    setState(() {
      _fix = fix;
      if (valid) {
        _center = position;
      } else {
        _center ??= GeolocatorLocationService.fallbackCenter;
      }
      _updateNearby();
    });
    if (valid && hadCenter && (moved || followIfMoved)) {
      _moveCamera(position);
    }
  }

  void _cancelCameraAnimation() {
    final anim = _cameraAnim;
    if (anim != null) {
      _cameraAnim = null;
      anim.stop();
      anim.dispose();
    }
  }

  /// Smoothly interpolates the camera center and zoom to [target] and [targetZoom] over
  /// 260 ms so cluster taps, recentering, and search jumps feel fluid instead of snapping.
  void _animateMove(LatLng target, double targetZoom) {
    _cancelCameraAnimation();
    final LatLng startCenter;
    final double startZoom;
    try {
      startCenter = _map.camera.center;
      startZoom = _map.camera.zoom;
    } catch (_) {
      return;
    }
    if ((startCenter.latitude - target.latitude).abs() < 1e-6 &&
        (startCenter.longitude - target.longitude).abs() < 1e-6 &&
        (startZoom - targetZoom).abs() < 1e-3) {
      _map.move(target, targetZoom);
      return;
    }
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _cameraAnim = controller;
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeOutCubic);
    final latTween = Tween<double>(begin: startCenter.latitude, end: target.latitude);
    final lonTween = Tween<double>(begin: startCenter.longitude, end: target.longitude);
    final zoomTween = Tween<double>(begin: startZoom, end: targetZoom);

    controller.addListener(() {
      if (!mounted) return;
      _map.move(
        LatLng(latTween.evaluate(curve), lonTween.evaluate(curve)),
        zoomTween.evaluate(curve),
      );
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        if (identical(_cameraAnim, controller)) {
          _cameraAnim = null;
          controller.dispose();
        }
      }
    });
    controller.forward();
  }

  void _moveCamera(LatLng target) {
    try {
      final zoom = _map.camera.zoom;
      _animateMove(target, zoom < _initialZoom ? _initialZoom : zoom);
    } catch (_) {
      // The map controller is not attached before the first FlutterMap build.
    }
  }

  void _onIncidents(List<Incident> incidents) {
    if (!mounted) return;
    final bounded = List<Incident>.unmodifiable([
      for (final i in incidents)
        if (philippinesBounds.contains(LatLng(i.latitude, i.longitude))) i,
    ]);
    setState(() {
      _loadError = false;
      final seen = _seen;
      _latest = incidents;
      _boundedIncidents = bounded;
      _updateNearby();
      if (seen != null) {
        final fresh = newHighRisk(seen, incidents);
        // A new report that is already announced as nearby needs no second banner.
        if (fresh.isNotEmpty && fresh.first.id != _nearby?.incident.id) _alert = fresh.first;
      }
      _seen = {...?seen, for (final incident in incidents) incident.id};
    });
  }

  List<Incident> _shownIncidents() {
    if (identical(_cachedBoundedSource, _boundedIncidents) &&
        _cachedFilter == _filter &&
        _cachedQuery == _query) {
      return _cachedShown;
    }
    _cachedBoundedSource = _boundedIncidents;
    _cachedFilter = _filter;
    _cachedQuery = _query;
    _cachedShown = applyMapFilter(_boundedIncidents, _filter, _query);
    return _cachedShown;
  }

  List<Marker> _markersFor(List<Incident> shown, double zoom, Color paper) {
    if (identical(_cachedMarkerShown, shown) &&
        _cachedMarkerZoom == zoom &&
        _cachedMarkerPaper == paper) {
      return _cachedMarkers;
    }
    _cachedMarkerShown = shown;
    _cachedMarkerZoom = zoom;
    _cachedMarkerPaper = paper;
    _cachedMarkers = List<Marker>.unmodifiable([
      for (final cluster in clusterPins(shown, zoom: zoom))
        cluster.isSingle ? _markerFor(cluster.members.single) : _clusterMarker(cluster),
    ]);
    return _cachedMarkers;
  }

  Future<void> _recenter() async {
    await _locate();
    final position = _fix?.position;
    if (!mounted) return;
    if (position == null || !philippinesBounds.contains(position)) {
      showError(context, 'Location is off.');
      return;
    }
    _animateMove(position, 16);
  }

  /// The user's live GPS position when available, falling back to the map center.
  LatLng _currentPosition() {
    final pos = _fix?.position;
    if (pos != null && philippinesBounds.contains(pos)) return pos;
    return _center ?? GeolocatorLocationService.fallbackCenter;
  }

  Future<void> _openChat() async {
    final chat = _chat;
    if (chat == null) return;
    unawaited(_locate(followIfMoved: true));
    final action = await showChatSheet(
      context,
      controller: chat,
      incidents: () => _latest,
      around: () {
        unawaited(_locate());
        return _currentPosition();
      },
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
    _animateMove(LatLng(incident.latitude, incident.longitude), 17);
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
      initialPosition: _fix?.position,
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
    final shown = _shownIncidents();
    final paper = context.palette.paper;
    final alert = _alert;
    final nearby = _nearby;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _initialZoom,
            minZoom: 5,
            maxZoom: 19,
            cameraConstraint: CameraConstraint.contain(bounds: philippinesBounds),
            interactionOptions: radarInteractionOptions,
            onPositionChanged: _onCamera,
            onTap: (_, point) {
              if (_pickingDestination) _planDetour(point);
            },
          ),
          children: [
            buildRadarTileLayer(tileProvider: _tiles),
            if (_route case final route?)
              PolylineLayer(
                polylines: [
                  // The route to take: green when it keeps clear of hazards or is a
                  // safer alternative (even if not perfectly safe), red only when no
                  // better route was found at all.
                  Polyline(
                    points: route.path,
                    strokeWidth: 6,
                    color: (route.isSafe || route.riskyDirect != null) ? routeSafeColor : routeRiskyColor,
                    borderColor: context.palette.ink,
                    borderStrokeWidth: 1.5,
                  ),
                  // The shortest route, in semi-transparent red when it passes a hazard.
                  // Draw it on top so both routes are visible when they overlap.
                  if (route.riskyDirect case final risky?)
                    Polyline(
                      points: risky.path,
                      strokeWidth: 3,
                      color: routeRiskyColor.withValues(alpha: 0.6),
                      borderColor: context.palette.ink.withValues(alpha: 0.4),
                      borderStrokeWidth: 0.5,
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
                        color: context.palette.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: paper, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ValueListenableBuilder<double>(
              valueListenable: _clusterZoom,
              builder: (context, zoom, _) => MarkerLayer(
                markers: _markersFor(shown, zoom, paper),
              ),
            ),
            RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MapSearchField(onChanged: _onSearchChanged),
                const SizedBox(height: 8),
                MapFilterChips(
                  incidents: _latest,
                  selected: _filter,
                  onSelected: (filter) {
                    setState(() => _filter = filter);
                    _flyToMatches();
                  },
                ),
                if (_chat != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _RadarButton(onPressed: _openChat),
                  ),
                ],
                if (_pickingDestination || _routing || _route != null) ...[
                  const SizedBox(height: 8),
                  _routePanel(),
                ],
                if (nearby != null) ...[
                  const SizedBox(height: 8),
                  NewHighRiskBanner(
                    incident: nearby.incident,
                    title: 'High-risk hazard nearby',
                    detail: '${nearby.incident.category} about ${nearby.meters.round()} m from you. Tap to open.',
                    dismissTooltip: 'Dismiss nearby alert',
                    onOpen: () {
                      setState(() => _nearby = null);
                      _focus(nearby.incident);
                    },
                    onDismiss: () => setState(() => _nearby = null),
                  ),
                ],
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
                  Material(
                    color: AppColors.error,
                    child: InkWell(
                      onTap: _subscribe,
                      child: const MapLabel(
                        text: 'Could not load hazards. Tap to try again.',
                        color: AppColors.error,
                        textColor: AppColors.onError,
                      ),
                    ),
                  ),
                  if (kDebugMode && _loadErrorDetail != null) _DebugError(text: _loadErrorDetail!),
                ],
              ],
            ),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 24,
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MapLegend(),
                const SizedBox(height: 8),
                MapLabel(text: _gpsLabel),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MapSquareButton(
                      icon: Icons.add,
                      tooltip: 'Zoom in',
                      onPressed: () => _animateMove(_map.camera.center, (_map.camera.zoom + 1).clamp(5.0, 19.0)),
                    ),
                    const SizedBox(width: 8),
                    MapSquareButton(
                      icon: Icons.remove,
                      tooltip: 'Zoom out',
                      onPressed: () => _animateMove(_map.camera.center, (_map.camera.zoom - 1).clamp(5.0, 19.0)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MapSquareButton(icon: Icons.my_location, tooltip: 'Recenter on me', onPressed: _recenter),
                if (widget.detour != null) ...[
                  const SizedBox(height: 8),
                  MapSquareButton(icon: Icons.alt_route, tooltip: 'Safe walking route', onPressed: _startDetour),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The route status block: picking a destination, planning, or the planned route.
  /// Shown under the filter chips, so it never covers the legend or the map buttons.
  Widget _routePanel() => _RoutePanel(
        text: _routing
            ? 'Finding a safe walking route...'
            : _pickingDestination
                ? 'Tap your destination on the map.'
                : _route!.summary,
        actionLabel: _routing ? null : (_pickingDestination ? 'Cancel' : 'Clear route'),
        route: _routing || _pickingDestination ? null : _route,
        onAction: () => setState(() {
          _pickingDestination = false;
          _route = null;
        }),
      );

  /// A rounded square block with the pin count, in the color of the most severe member.
  Marker _clusterMarker(PinCluster cluster) {
    final count = cluster.members.length;
    final risk = cluster.topRisk;
    return Marker(
      point: cluster.center,
      width: 48,
      height: 48,
      child: Semantics(
        button: true,
        label: '$count hazards here, highest risk $risk. Tap to zoom in.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _animateMove(cluster.center, math.min(_map.camera.zoom + 2, clusterMaxZoom)),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: riskColor(risk),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.palette.paper, width: 2),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: risk == 'High' ? AppColors.onError : AppColors.cream,
                    ),
              ),
            ),
          ),
        ),
      ),
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
                border: Border.all(color: context.palette.paper, width: 2),
              ),
              child: Icon(categoryIcon(incident.category), size: 16, color: pinIconColor(incident)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Debug builds only: the full map load error, selectable, with a copy button.
/// Limited in height so a long Firebase link never covers the map.
class _DebugError extends StatelessWidget {
  const _DebugError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', color: context.palette.ink);
    return Container(
      decoration: BoxDecoration(
        color: context.palette.paper,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: context.palette.ink.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      constraints: const BoxConstraints(maxHeight: 140),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SingleChildScrollView(child: SelectableText(text, style: style))),
          IconButton(
            tooltip: 'Copy error',
            icon: Icon(Icons.copy, color: context.palette.ink, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                showSuccess(context, 'Error copied.');
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Route line colors. Fixed, so they read the same in light and dark mode.
const Color routeSafeColor = AppColors.success;
const Color routeRiskyColor = AppColors.riskHigh;

/// Rounded route status block with one action (Cancel or Clear route). With a planned
/// [route] it adds a key for the green and red lines on the map.
class _RoutePanel extends StatelessWidget {
  const _RoutePanel({required this.text, required this.actionLabel, required this.onAction, this.route});

  final String text;
  final String? actionLabel;
  final VoidCallback onAction;
  final DetourRoute? route;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final route = this.route;
    final swatch = route == null ? context.palette.sage : ((route.isSafe || route.riskyDirect != null) ? routeSafeColor : routeRiskyColor);
    return Container(
      decoration: BoxDecoration(
        color: context.palette.paper,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: context.palette.ink.withValues(alpha: 0.28), width: 1.2),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: swatch, borderRadius: BorderRadius.circular(4)),
              ),
              Expanded(child: Text(text, style: textTheme.bodySmall)),
              if (actionLabel != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: context.palette.ink,
                    shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusSm),
                  ),
                  child: Text(actionLabel!),
                ),
            ],
          ),
          if (route != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (route.isSafe || route.riskyDirect != null) _key(textTheme, routeSafeColor, 'Suggested safe route'),
                  if (!route.isSafe || route.riskyDirect != null) _key(textTheme, routeRiskyColor, 'Passes a hazard'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _key(TextTheme textTheme, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 4,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          Text(label, style: textTheme.labelSmall),
        ],
      );
}

/// Rounded sage button below the filter chips on the right side.
class _RadarButton extends StatelessWidget {
  const _RadarButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.palette.sage,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.radiusMd,
        side: BorderSide(color: context.palette.ink.withValues(alpha: 0.35), width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppTheme.radiusMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.radar, size: 18, color: context.palette.ink),
              const SizedBox(width: 6),
              Text('Ask Radar AI', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: context.palette.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
