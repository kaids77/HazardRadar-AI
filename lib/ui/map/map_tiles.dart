import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../geo/philippines.dart';
import 'map_style.dart';

/// Tiles are cached on the device by flutter_map's built-in cache (Android, iOS, desktop;
/// a no-op on web). The library default is 1 GB, which is too much for a phone that is
/// already low on space, so the cap is set to 150 MB. Freshness follows the tile
/// server's HTTP cache headers.
const int tileCacheBytes = 150 * 1000 * 1000;

/// Minimum interval between tile load/prune sweeps during rapid zoom or pan gestures.
/// Uses wall-clock timestamps instead of a [Timer] so no dangling timer is left behind
/// when the map is disposed and intermediate frames don't allocate timers.
const Duration tileUpdateThrottle = Duration(milliseconds: 50);

/// Throttles non-final camera move/zoom events using wall-clock elapsed time, while
/// always letting final events (e.g. [MapEventMoveEnd], [MapEventFlingAnimationEnd])
/// pass through immediately so the final viewport always loads all visible tiles.
TileUpdateTransformer throttledTileUpdateTransformer([
  Duration interval = tileUpdateThrottle,
  DateTime Function()? now,
]) {
  final clock = now ?? DateTime.now;
  final minMicros = interval.inMicroseconds;
  return TileUpdateTransformer.fromHandlers(
    handleData: _createThrottledHandler(minMicros, clock),
  );
}

void Function(TileUpdateEvent, EventSink<TileUpdateEvent>) _createThrottledHandler(
  int minMicros,
  DateTime Function() clock,
) {
  DateTime? lastEmit;
  return (event, sink) {
    if (event.wasTriggeredByTap()) return;
    final mapEvent = event.mapEvent;
    final isContinuous = mapEvent is MapEventMove ||
        mapEvent is MapEventRotate ||
        mapEvent is MapEventFlingAnimation ||
        mapEvent is MapEventDoubleTapZoom ||
        mapEvent is MapEventScrollWheelZoom;
    final current = clock();
    if (!isContinuous || lastEmit == null || current.difference(lastEmit!).inMicroseconds >= minMicros) {
      lastEmit = current;
      sink.add(event);
    }
  };
}

TileProvider cachedTileProvider() => NetworkTileProvider(
      cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(maxCacheSize: tileCacheBytes),
    );

/// Shared [InteractionOptions] for both the main Radar map and the Report Wizard map:
/// disables accidental 2-finger/Ctrl+drag rotation so pinch-to-zoom never fights rotation,
/// enables multi-finger gesture race for responsive mobile pinch zooming, and tunes scroll
/// wheel velocity for smooth desktop/web zooming.
final InteractionOptions radarInteractionOptions = InteractionOptions(
  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
  enableMultiFingerGestureRace: true,
  pinchZoomThreshold: 0.3,
  pinchMoveThreshold: 32.0,
  scrollWheelVelocity: 0.008,
  cursorKeyboardRotationOptions: CursorKeyboardRotationOptions.disabled(),
);

/// Builds the tinted OpenStreetMap [TileLayer] bounded to the Philippines, with throttled
/// tile updates and extra keep-buffer tiles so zooming and panning stay smooth on mobile and web.
Widget buildRadarTileLayer({TileProvider? tileProvider}) => wrapTintedTileLayer(
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.hazardradarai',
        tileProvider: tileProvider ?? cachedTileProvider(),
        tileBounds: philippinesBounds,
        minNativeZoom: 5,
        maxNativeZoom: 19,
        keepBuffer: 3,
        panBuffer: 1,
        evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
        tileUpdateTransformer: throttledTileUpdateTransformer(),
      ),
    );
