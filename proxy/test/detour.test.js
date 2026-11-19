import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { createApp } from '../src/app.js';
import { clearanceMeters, createOsrmClient, pickSafest, validateDetourRequest } from '../src/detour.js';
import { createTestTokens } from './tokens.js';

const FROM = { lat: 10.3236, lon: 123.9322 };
const TO = { lat: 10.3300, lon: 123.9322 };
const HAZARD = { lat: 10.3268, lon: 123.9322, riskLevel: 'High' };

// Route A goes straight past the hazard; route B swings ~300 m east.
const straight = [[123.9322, 10.3236], [123.9322, 10.3268], [123.9322, 10.33]];
const around = [[123.9322, 10.3236], [123.935, 10.3268], [123.9322, 10.33]];

function osrmBody() {
  return {
    code: 'Ok',
    routes: [
      { distance: 710, duration: 510, geometry: { coordinates: straight } },
      { distance: 900, duration: 650, geometry: { coordinates: around } },
    ],
  };
}

function fakeFetch(body = osrmBody(), { ok = true } = {}) {
  const calls = [];
  const impl = async (url, options) => {
    calls.push({ url, options });
    return { ok, json: async () => body };
  };
  return { impl, calls };
}

test('validation keeps routes inside the Philippines and within 10 km', () => {
  assert.throws(() => validateDetourRequest({ from: FROM, to: { lat: 1.35, lon: 103.8 } }), /Philippines/);
  assert.throws(() => validateDetourRequest({ from: FROM, to: { lat: 10.5, lon: 123.9 } }), /10 km/);
  assert.throws(() => validateDetourRequest({ from: { lat: 'x' }, to: TO }), /numeric/);
  const { hazards } = validateDetourRequest({
    from: FROM,
    to: TO,
    hazards: [HAZARD, { ...HAZARD, riskLevel: 'Low' }],
  });
  assert.equal(hazards.length, 1);
});

test('the safest route keeps farthest from High and Medium hazards', () => {
  const routes = [straight, around].map((coords, i) => ({
    path: coords.map(([lon, lat]) => ({ lat, lon })),
    distanceMeters: [710, 900][i],
    durationSeconds: 0,
  }));
  assert.equal(clearanceMeters(routes[0].path, [HAZARD]), 0);
  assert.equal(pickSafest(routes, [HAZARD]).route.distanceMeters, 900);
  assert.equal(pickSafest(routes, []).route.distanceMeters, 710);
});

test('the OSRM client sends a User-Agent, caches for 5 minutes, and maps failures', async () => {
  let now = 0;
  const fetch = fakeFetch();
  const client = createOsrmClient({ baseUrl: 'https://osrm.test/routed-foot', fetchImpl: fetch.impl, now: () => now });

  const routes = await client.routes(FROM, TO);
  await client.routes(FROM, TO);
  assert.equal(routes.length, 2);
  assert.equal(fetch.calls.length, 1);
  assert.match(fetch.calls[0].url, /^https:\/\/osrm\.test\/routed-foot\/route\/v1\/foot\/123\.9322,10\.3236;123\.9322,10\.33\?alternatives=3/);
  assert.match(fetch.calls[0].options.headers['User-Agent'], /HazardRadarAI/);

  now = 5 * 60_000;
  await client.routes(FROM, TO);
  assert.equal(fetch.calls.length, 2);

  const down = createOsrmClient({ baseUrl: 'x', fetchImpl: fakeFetch(null, { ok: false }).impl });
  await assert.rejects(down.routes(FROM, TO), /unavailable/);
});

let tokens;
const servers = [];

before(async () => {
  tokens = await createTestTokens();
});
after(() => servers.forEach((s) => s.close()));

async function start(osrm) {
  const app = createApp({
    config: { rateLimitPerMinute: 30, detourPerMinute: 2 },
    groq: { complete: async () => '{}' },
    osrm,
    verifyIdToken: tokens.verifyIdToken,
    log: () => {},
  });
  return new Promise((resolve) => {
    const server = app.listen(0, '127.0.0.1', () => {
      servers.push(server);
      resolve(`http://127.0.0.1:${server.address().port}`);
    });
  });
}

async function postDetour(base, body) {
  return fetch(`${base}/detour`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${await tokens.sign('alice')}` },
    body: JSON.stringify(body),
  });
}

test('POST /detour returns the safest path and has its own per-user limit', async () => {
  const base = await start(createOsrmClient({ baseUrl: 'x', fetchImpl: fakeFetch().impl }));

  const response = await postDetour(base, { from: FROM, to: TO, hazards: [HAZARD] });
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.distanceMeters, 900);
  assert.equal(body.alternatives, 2);
  assert.ok(body.clearanceMeters > 250);
  assert.deepEqual(body.path[0], [10.3236, 123.9322]);

  assert.equal((await postDetour(base, { from: FROM, to: TO })).status, 200);
  assert.equal((await postDetour(base, { from: FROM, to: TO })).status, 429);
});

test('POST /detour returns 502 when routing is down', async () => {
  const base = await start(createOsrmClient({ baseUrl: 'x', fetchImpl: fakeFetch(null, { ok: false }).impl }));
  assert.equal((await postDetour(base, { from: FROM, to: TO })).status, 502);
});
