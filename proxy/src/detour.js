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

/** Smallest distance from any vertex of [path] ({lat, lon}[]) to any hazard, or null without hazards. */
export function clearanceMeters(path, hazards) {
  if (hazards.length === 0) return null;
  let best = Infinity;
  for (const p of path) {
    for (const h of hazards) {
      const d = haversineMeters(p, h);
      if (d < best) best = d;
    }
  }
  return best;
}

/**
 * Picks the route that keeps farthest from hazards. Routes within 10 m of the best
 * clearance count as equally safe, and then the shortest wins.
 */
export function pickSafest(routes, hazards) {
  if (routes.length === 0) return null;
  const scored = routes.map((route) => ({ route, clearance: clearanceMeters(route.path, hazards) }));
  if (hazards.length === 0) {
    return scored.reduce((a, b) => (b.route.distanceMeters < a.route.distanceMeters ? b : a));
  }
  const top = Math.max(...scored.map((s) => s.clearance));
  return scored
    .filter((s) => s.clearance >= top - 10)
    .reduce((a, b) => (b.route.distanceMeters < a.route.distanceMeters ? b : a));
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
    async routes(from, to) {
      const key = [from.lat, from.lon, to.lat, to.lon].map((n) => n.toFixed(4)).join(',');
      const hit = cache.get(key);
      if (hit && now() - hit.at < ttlMs) return hit.routes;

      const coords = `${from.lon},${from.lat};${to.lon},${to.lat}`;
      const url = `${baseUrl}/route/v1/foot/${coords}?alternatives=3&geometries=geojson&overview=full`;
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

/** Response body: the chosen path as [lat, lon] pairs, its length, walking time, and clearance. */
export function toDetourResponse(choice, alternatives) {
  return {
    path: choice.route.path.map((p) => [p.lat, p.lon]),
    distanceMeters: choice.route.distanceMeters,
    durationSeconds: choice.route.durationSeconds,
    clearanceMeters: choice.clearance === null ? null : Math.round(choice.clearance),
    alternatives,
  };
}
