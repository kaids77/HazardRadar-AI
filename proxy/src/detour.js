import { UpstreamError, ValidationError } from './errors.js';

// Philippines bounding box, same as lib/geo/philippines.dart.
const BOUNDS = { minLat: 4.5, maxLat: 21.3, minLon: 116.7, maxLon: 127.0 };
export const MAX_HAZARDS = 50;
export const MAX_TRIP_METERS = 10_000;
const AVOIDED_RISKS = new Set(['High', 'Medium']);

/** Great-circle distance in meters. */
export function haversineMeters(a, b) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * 6_371_000 * Math.asin(Math.min(1, Math.sqrt(h)));
}

function point(raw, name) {
  const lat = raw?.lat;
  const lon = raw?.lon;
  if (typeof lat !== 'number' || typeof lon !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lon)) {
    throw new ValidationError(`${name} must have numeric lat and lon`);
  }
  if (lat < BOUNDS.minLat || lat > BOUNDS.maxLat || lon < BOUNDS.minLon || lon > BOUNDS.maxLon) {
    throw new ValidationError(`${name} must be inside the Philippines`);
  }
  return { lat, lon };
}

/** Validates {from, to, hazards}. Only High and Medium hazards are kept. */
export function validateDetourRequest(body) {
  if (body === null || typeof body !== 'object') throw new ValidationError('request body must be a JSON object');
  const from = point(body.from, 'from');
  const to = point(body.to, 'to');
  if (haversineMeters(from, to) > MAX_TRIP_METERS) {
    throw new ValidationError('the destination must be within 10 km for a walking route');
  }
  const raw = body.hazards ?? [];
  if (!Array.isArray(raw)) throw new ValidationError('hazards must be an array');
  if (raw.length > MAX_HAZARDS) throw new ValidationError(`hazards must have at most ${MAX_HAZARDS} items`);
  const hazards = raw
    .map((h, i) => ({ ...point(h, `hazards[${i}]`), riskLevel: h.riskLevel }))
    .filter((h) => AVOIDED_RISKS.has(h.riskLevel));
  return { from, to, hazards };
}

/** A route closer than this to a High or Medium hazard counts as pointing at it. */
export const SAFE_METERS = 40;
/** How far from a hazard the detour waypoints are placed. */
const DETOUR_OFFSET_METERS = 90;
/** How many times to look for a way around the hazards that are still too close. */
const MAX_ROUNDS = 2;

/** Meters from [p] to the segment a-b, on a flat local grid (accurate over a few hundred meters). */
function distanceToSegmentMeters(p, a, b) {
  const mPerDegLat = 111_320;
  const mPerDegLon = 111_320 * Math.cos((p.lat * Math.PI) / 180);
  const ax = (a.lon - p.lon) * mPerDegLon;
  const ay = (a.lat - p.lat) * mPerDegLat;
  const bx = (b.lon - p.lon) * mPerDegLon;
  const by = (b.lat - p.lat) * mPerDegLat;
  const dx = bx - ax;
  const dy = by - ay;
  const lengthSquared = dx * dx + dy * dy;
  const t = lengthSquared === 0 ? 0 : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / lengthSquared));
  return Math.hypot(ax + t * dx, ay + t * dy);
}

/** Distance from [hazard] to the nearest point of the line [path], not just its vertices. */
export function distanceToPathMeters(path, hazard) {
  if (path.length === 1) return haversineMeters(path[0], hazard);
  let best = Infinity;
  for (let i = 1; i < path.length; i++) {
    const d = distanceToSegmentMeters(hazard, path[i - 1], path[i]);
    if (d < best) best = d;
  }
  return best;
}

/** Smallest distance from the line [path] ({lat, lon}[]) to any hazard, or null without hazards. */
export function clearanceMeters(path, hazards) {
  if (hazards.length === 0) return null;
  return Math.min(...hazards.map((h) => distanceToPathMeters(path, h)));
}

/**
 * Picks the route to show. A route that keeps at least [SAFE_METERS] from every hazard
 * wins, and the shortest of those is chosen. When none is that clear, the one that
 * keeps farthest away wins (routes within 10 m of the best count as equal, then the
 * shortest).
 */
export function pickSafest(routes, hazards) {
  if (routes.length === 0) return null;
  const shortest = (a, b) => (b.route.distanceMeters < a.route.distanceMeters ? b : a);
  const scored = routes.map((route) => ({ route, clearance: clearanceMeters(route.path, hazards) }));
  if (hazards.length === 0) return scored.reduce(shortest);
  const clear = scored.filter((s) => s.clearance >= SAFE_METERS);
  if (clear.length > 0) return clear.reduce(shortest);
  const top = Math.max(...scored.map((s) => s.clearance));
  return scored.filter((s) => s.clearance >= top - 10).reduce(shortest);
}

/** The point [meters] from [p] in the compass direction [bearingDegrees]. */
export function offsetPoint(p, meters, bearingDegrees) {
  const rad = (bearingDegrees * Math.PI) / 180;
  return {
    lat: p.lat + (meters * Math.cos(rad)) / 111_320,
    lon: p.lon + (meters * Math.sin(rad)) / (111_320 * Math.cos((p.lat * Math.PI) / 180)),
  };
}

/**
 * Finds a walking route that stays away from the hazards.
 *
 * Starts with the routes the router offers. While the best one still passes within
 * [SAFE_METERS] of a hazard, it asks for extra routes that go through a waypoint placed
 * beside that hazard (four sides), then picks again. A route that is far longer than the
 * shortest one is ignored, since nobody walks 3 km around one pothole. A hazard that sits
 * at the start or the destination cannot be avoided and is skipped.
 *
 * @returns {Promise<{ route: object, clearance: number | null, alternatives: number } | null>}
 */
export async function findSafeRoute({ osrm, from, to, hazards }) {
  const pool = [...(await osrm.routes(from, to))];
  if (pool.length === 0) return null;

  // The shortest route the router offers, so the app can show it when it passes a hazard.
  const shortestRoute = pool.reduce((a, b) => (b.distanceMeters < a.distanceMeters ? b : a));
  const direct = { route: shortestRoute, clearance: clearanceMeters(shortestRoute.path, hazards) };

  const choose = () => {
    const shortest = Math.min(...pool.map((r) => r.distanceMeters));
    const limit = Math.max(shortest * 1.7, shortest + 1000);
    return pickSafest(pool.filter((r) => r.distanceMeters <= limit), hazards);
  };

  let choice = choose();
  for (let round = 0; round < MAX_ROUNDS; round++) {
    if (choice.clearance === null || choice.clearance >= SAFE_METERS) break;
    const blocking = hazards
      .filter((h) => haversineMeters(h, from) > SAFE_METERS && haversineMeters(h, to) > SAFE_METERS)
      .map((h) => ({ h, d: distanceToPathMeters(choice.route.path, h) }))
      .filter((x) => x.d < SAFE_METERS)
      .sort((a, b) => a.d - b.d);
    if (blocking.length === 0) break;

    const vias = [0, 90, 180, 270].map((bearing) => offsetPoint(blocking[0].h, DETOUR_OFFSET_METERS, bearing));
    const results = await Promise.allSettled(vias.map((via) => osrm.routes(from, to, [via])));
    for (const result of results) if (result.status === 'fulfilled') pool.push(...result.value);
    choice = choose();
  }
  return { ...choice, alternatives: pool.length, direct };
}

/**
 * Client for the public OSRM foot profile. Responses are cached for 5 minutes per
 * rounded start and end, so repeated questions do not hit the free service again.
 *
 * @param {{ baseUrl: string, timeoutMs?: number, fetchImpl?: typeof fetch, now?: () => number }} options
 */
export function createOsrmClient({ baseUrl, timeoutMs = 8000, fetchImpl = fetch, now = Date.now }) {
  const cache = new Map();
  const ttlMs = 5 * 60_000;

  return {
    /** Routes from [from] to [to], optionally through [via] waypoints (then only one route comes back). */
    async routes(from, to, via = []) {
      const stops = [from, ...via, to];
      const key = stops.flatMap((p) => [p.lat, p.lon]).map((n) => n.toFixed(4)).join(',');
      const hit = cache.get(key);
      if (hit && now() - hit.at < ttlMs) return hit.routes;

      const coords = stops.map((p) => `${p.lon},${p.lat}`).join(';');
      const alternatives = via.length === 0 ? 3 : 'false';
      const url = `${baseUrl}/route/v1/foot/${coords}?alternatives=${alternatives}&geometries=geojson&overview=full`;
      let response;
      try {
        response = await fetchImpl(url, {
          headers: { 'User-Agent': 'HazardRadarAI/1.0 (student project)' },
          signal: AbortSignal.timeout(timeoutMs),
        });
      } catch {
        throw new UpstreamError('routing service unavailable', 502);
      }
      if (!response.ok) throw new UpstreamError('routing service unavailable', 502);
      const body = await response.json().catch(() => null);
      if (body?.code !== 'Ok' || !Array.isArray(body.routes)) {
        throw new UpstreamError('no walking route found', 502);
      }
      const routes = body.routes
        .filter((r) => Array.isArray(r?.geometry?.coordinates) && r.geometry.coordinates.length >= 2)
        .map((r) => ({
          path: r.geometry.coordinates.map(([lon, lat]) => ({ lat, lon })),
          distanceMeters: Math.round(r.distance ?? 0),
          durationSeconds: Math.round(r.duration ?? 0),
        }));

      if (cache.size >= 200) cache.delete(cache.keys().next().value);
      cache.set(key, { at: now(), routes });
      return routes;
    },
  };
}

/**
 * Response body: the chosen path as [lat, lon] pairs, its length, walking time, and clearance.
 * [direct] is the shortest route, included only when it is a different route from the chosen
 * one, so the app can draw it in red next to the green safe route.
 */
export function toDetourResponse(choice, alternatives, direct = null) {
  const toBody = (c) => ({
    path: c.route.path.map((p) => [p.lat, p.lon]),
    distanceMeters: c.route.distanceMeters,
    durationSeconds: c.route.durationSeconds,
    clearanceMeters: c.clearance === null ? null : Math.round(c.clearance),
  });
  return {
    ...toBody(choice),
    alternatives,
    direct: direct && direct.route !== choice.route ? toBody(direct) : null,
  };
}
