import 'package:flutter_map/flutter_map.dart';

/// Tiles are cached on the device by flutter_map's built-in cache (Android, iOS, desktop;
/// a no-op on web). The library default is 1 GB, which is too much for a phone that is
/// already low on space, so the cap is set to 150 MB. Freshness follows the tile
/// server's HTTP cache headers.
const int tileCacheBytes = 150 * 1000 * 1000;

TileProvider cachedTileProvider() => NetworkTileProvider(
      cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(maxCacheSize: tileCacheBytes),
    );
