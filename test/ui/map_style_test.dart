import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/geo/philippines.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/map/map_style.dart';
import 'package:hazardradarai/ui/map/map_tiles.dart';

void main() {
  test('tile tint filter can be built from the cream token', () {
    expect(tileTintFilter(), isA<ColorFilter>());
    expect(tileTintFilter(), tileTintFilter(tint: AppColors.cream));
  });

  testWidgets('tinted tile builder wraps the tile in a color filter', (tester) async {
    late Widget wrapped;
    await tester.pumpWidget(
      Builder(builder: (context) {
        wrapped = tintedTileBuilder(context, const SizedBox(), Object());
        return wrapped;
      }),
    );
    expect(find.byType(ColorFiltered), findsOneWidget);
  });

  testWidgets('wrapTintedTileLayer wraps the tile layer in a single RepaintBoundary and ColorFiltered', (tester) async {
    await tester.pumpWidget(wrapTintedTileLayer(const SizedBox(key: ValueKey('layer'))));
    expect(find.byType(RepaintBoundary), findsOneWidget);
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(find.byKey(const ValueKey('layer')), findsOneWidget);
  });

  test('buildRadarTileLayer configures Philippines bounds, buffer, and native zoom limits', () {
    final widget = buildRadarTileLayer(tileProvider: NetworkTileProvider(cachingProvider: const DisabledMapCachingProvider())) as RepaintBoundary;
    final filtered = widget.child! as ColorFiltered;
    final layer = filtered.child! as TileLayer;
    expect(layer.tileBounds, philippinesBounds);
    expect(layer.minNativeZoom, 5);
    expect(layer.maxNativeZoom, 19);
    expect(layer.keepBuffer, 3);
    expect(layer.panBuffer, 1);
    expect(layer.evictErrorTileStrategy, EvictErrorTileStrategy.notVisibleRespectMargin);
  });

  test('radarInteractionOptions disables map rotation and tunes pinch and scroll-wheel zoom', () {
    expect(radarInteractionOptions.flags & InteractiveFlag.rotate, 0);
    expect(radarInteractionOptions.flags & InteractiveFlag.pinchZoom, isNonZero);
    expect(radarInteractionOptions.flags & InteractiveFlag.drag, isNonZero);
    expect(radarInteractionOptions.enableMultiFingerGestureRace, isTrue);
    expect(radarInteractionOptions.scrollWheelVelocity, greaterThan(0.005));
  });

  test('throttledTileUpdateTransformer drops high-frequency move frames and passes move-end immediately', () async {
    var clock = DateTime(2026, 11, 25, 12, 0, 0);
    final controller = StreamController<TileUpdateEvent>(sync: true);
    final received = <MapEvent>[];
    final sub = controller.stream
        .transform(throttledTileUpdateTransformer(const Duration(milliseconds: 50), () => clock))
        .listen((e) => received.add(e.mapEvent));

    final camera = MapCamera(
      crs: const Epsg3857(),
      center: const LatLng(10.3236, 123.9322),
      zoom: 15,
      rotation: 0,
      nonRotatedSize: const Size(400, 600),
    );
    TileUpdateEvent moveEvent() => TileUpdateEvent(
          mapEvent: MapEventMove(
            source: MapEventSource.mapController,
            camera: camera,
            oldCamera: camera,
          ),
        );
    final endEvent = TileUpdateEvent(
      mapEvent: MapEventMoveEnd(source: MapEventSource.dragEnd, camera: camera),
    );

    controller.add(moveEvent());
    clock = clock.add(const Duration(milliseconds: 10));
    controller.add(moveEvent()); // throttled out
    clock = clock.add(const Duration(milliseconds: 10));
    controller.add(endEvent); // non-continuous event always passes immediately
    clock = clock.add(const Duration(milliseconds: 10));
    controller.add(moveEvent()); // throttled out (only 10ms since endEvent)
    clock = clock.add(const Duration(milliseconds: 55));
    controller.add(moveEvent()); // passes (>= 50ms)

    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    await controller.close();

    expect(received, hasLength(3));
    expect(received[0], isA<MapEventMove>());
    expect(received[1], isA<MapEventMoveEnd>());
    expect(received[2], isA<MapEventMove>());
  });
}
