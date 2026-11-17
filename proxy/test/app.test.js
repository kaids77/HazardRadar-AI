import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { createApp } from '../src/app.js';
import { UpstreamError } from '../src/errors.js';

const TOKEN = 'b'.repeat(32);
const SECRET_KEY = 'gsk_test_secret_value_should_never_leak';

/** Fake Groq client that returns whatever the test sets, and records calls. */
function fakeGroq(reply) {
  const calls = [];
  return {
    calls,
    async complete(request) {
      calls.push(request);
      if (reply instanceof Error) throw reply;
      return reply;
    },
  };
}

function startApp(groq) {
  const app = createApp({
    config: { proxyToken: TOKEN },
    groq,
    log: () => {},
  });
  return new Promise((resolve) => {
    const server = app.listen(0, '127.0.0.1', () => {
      resolve({ server, base: `http://127.0.0.1:${server.address().port}` });
    });
  });
}

const triageReply = JSON.stringify({
  category: 'Road',
  riskLevel: 'Medium',
  aiSummary: 'Deep crater in the right lane.',
  recommendedAction: 'Mark the crater and schedule a patch.',
});

let running;
const cleanup = [];

async function post(base, path, body, headers = {}) {
  return fetch(`${base}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-proxy-token': TOKEN, ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

after(() => {
  for (const close of cleanup) close();
});

test('health responds without a token', async () => {
  running = await startApp(fakeGroq(triageReply));
  cleanup.push(() => running.server.close());

  const response = await fetch(`${running.base}/health`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: 'ok' });
});

test('triage rejects a missing token', async () => {
  const response = await post(running.base, '/triage', { note: 'crater' }, { 'x-proxy-token': '' });
  assert.equal(response.status, 401);
});

test('triage rejects a wrong token', async () => {
  const response = await post(running.base, '/triage', { note: 'crater' }, { 'x-proxy-token': 'wrong' });
  assert.equal(response.status, 401);
});

test('triage returns validated structured output', async () => {
  const groq = fakeGroq(triageReply);
  const app = await startApp(groq);
  cleanup.push(() => app.server.close());

  const response = await post(app.base, '/triage', { note: '  big crater on Rizal  ' });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).riskLevel, 'Medium');

  const sent = groq.calls[0];
  assert.equal(sent.jsonMode, true);
  assert.equal(sent.messages[1].content, 'big crater on Rizal');
});

test('triage returns 400 for an empty note without calling Groq', async () => {
  const groq = fakeGroq(triageReply);
  const app = await startApp(groq);
  cleanup.push(() => app.server.close());

  const response = await post(app.base, '/triage', { note: '' });
  assert.equal(response.status, 400);
  assert.equal(groq.calls.length, 0);
});

test('upstream failure returns a generic error that never contains the key', async () => {
  const groq = {
    async complete() {
      throw new UpstreamError('AI service timed out', 504);
    },
  };
  const app = await startApp(groq);
  cleanup.push(() => app.server.close());

  const response = await post(app.base, '/triage', { note: 'crater' });
  const text = await response.text();
  assert.equal(response.status, 504);
  assert.doesNotMatch(text, new RegExp(SECRET_KEY));
  assert.match(text, /timed out/);
});

test('chat drops actions that reference incidents the app did not send', async () => {
  const groq = fakeGroq(
    JSON.stringify({
      reply: 'Avoid the crater near Rizal.',
      actions: [
        { type: 'showOnMap', incidentId: 'abc' },
        { type: 'showOnMap', incidentId: 'made-up' },
        { type: 'openReport' },
        { type: 'deleteEverything' },
      ],
    }),
  );
  const app = await startApp(groq);
  cleanup.push(() => app.server.close());

  const response = await post(app.base, '/chat', {
    message: 'Is Rizal safe?',
    incidents: [{ id: 'abc', category: 'Road', riskLevel: 'Medium', aiSummary: 'Crater' }],
  });
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.deepEqual(body.actions, [
    { type: 'showOnMap', incidentId: 'abc' },
    { type: 'openReport' },
  ]);
});

test('chat rejects more than 20 incidents', async () => {
  const app = await startApp(fakeGroq(triageReply));
  cleanup.push(() => app.server.close());

  const incidents = Array.from({ length: 21 }, (_, i) => ({ id: `i${i}` }));
  const response = await post(app.base, '/chat', { message: 'hi', incidents });
  assert.equal(response.status, 400);
});

test('malformed JSON body returns 400', async () => {
  const app = await startApp(fakeGroq(triageReply));
  cleanup.push(() => app.server.close());

  const response = await post(app.base, '/triage', '{not json');
  assert.equal(response.status, 400);
});

test('oversized body returns 413', async () => {
  const app = await startApp(fakeGroq(triageReply));
  cleanup.push(() => app.server.close());

  const response = await post(app.base, '/triage', { note: 'x'.repeat(20000) });
  assert.equal(response.status, 413);
});

test('unknown route returns 404 with a token', async () => {
  const app = await startApp(fakeGroq(triageReply));
  cleanup.push(() => app.server.close());

  const response = await fetch(`${app.base}/nope`, { headers: { 'x-proxy-token': TOKEN } });
  assert.equal(response.status, 404);
});
