import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { createApp } from '../src/app.js';
import { isAllowedOrigin } from '../src/cors.js';
import { createTestTokens } from './tokens.js';

const servers = [];
let tokens;

before(async () => {
  tokens = await createTestTokens();
});

function startApp() {
  const groq = {
    async complete() {
      return JSON.stringify({ reply: 'All clear.', actions: [] });
    },
  };
  const app = createApp({
    config: { rateLimitPerMinute: 30 },
    groq,
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

function preflight(base, origin) {
  return fetch(`${base}/chat`, {
    method: 'OPTIONS',
    headers: {
      Origin: origin,
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers': 'content-type,authorization',
    },
  });
}

after(() => {
  for (const server of servers) server.close();
});

test('only loopback origins are allowed', () => {
  assert.equal(isAllowedOrigin('http://localhost:5000'), true);
  assert.equal(isAllowedOrigin('http://127.0.0.1:61234'), true);
  assert.equal(isAllowedOrigin('http://localhost'), true);
  assert.equal(isAllowedOrigin('https://evil.example'), false);
  assert.equal(isAllowedOrigin('http://localhost.evil.example'), false);
  assert.equal(isAllowedOrigin('http://localhost:5000.evil.example'), false);
  assert.equal(isAllowedOrigin(undefined), false);
});

test('preflight from the Flutter web dev server succeeds without a token', async () => {
  const base = await startApp();
  const response = await preflight(base, 'http://localhost:5000');

  assert.equal(response.status, 204);
  assert.equal(response.headers.get('access-control-allow-origin'), 'http://localhost:5000');
  assert.match(response.headers.get('access-control-allow-headers'), /authorization/);
});

test('preflight from another site gets no CORS headers and stays unauthorized', async () => {
  const base = await startApp();
  const response = await preflight(base, 'https://evil.example');

  assert.equal(response.status, 401);
  assert.equal(response.headers.get('access-control-allow-origin'), null);
});

test('a POST from a loopback origin still needs an ID token', async () => {
  const base = await startApp();
  const body = JSON.stringify({ message: 'safe?', incidents: [] });
  const headers = { 'content-type': 'application/json', Origin: 'http://localhost:5000' };

  const without = await fetch(`${base}/chat`, { method: 'POST', headers, body });
  assert.equal(without.status, 401);

  const withToken = await fetch(`${base}/chat`, {
    method: 'POST',
    headers: { ...headers, Authorization: `Bearer ${await tokens.sign('alice')}` },
    body,
  });
  assert.equal(withToken.status, 200);
  assert.equal(withToken.headers.get('access-control-allow-origin'), 'http://localhost:5000');
});
