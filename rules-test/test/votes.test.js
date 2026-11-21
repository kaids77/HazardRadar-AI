import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, writeBatch } from 'firebase/firestore';

import { createEnv, googleUser, guest, newIncident, profile, seed } from './helpers.js';

let env;

before(async () => {
  env = await createEnv();
});
after(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
  await seed(env, {
    'users/reporter': profile(),
    'users/guest': profile(),
    'users/scout': profile({ tier: 2 }),
    'users/sentinel': profile({ tier: 3, role: 'VERIFIER' }),
    'incidents/i1': newIncident('reporter'),
  });
});

/** Casts a vote the way the app does: vote doc and netVotes change together. */
function vote(db, uid, value, { netVotes, visibility } = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, `incidents/i1/votes/${uid}`), { value, createdAt: serverTimestamp() });
  batch.update(doc(db, 'incidents/i1'), {
    netVotes: netVotes ?? value,
    ...(visibility ? { visibility } : {}),
  });
  return batch.commit();
}

test('a Civic Scout votes with weight 1', async () => {
  await assertSucceeds(vote(googleUser(env, 'scout'), 'scout', 1));
});

test('a Sentinel votes with weight 2, not 1', async () => {
  await assertFails(vote(googleUser(env, 'sentinel'), 'sentinel', 1));
  await assertSucceeds(vote(googleUser(env, 'sentinel'), 'sentinel', 2));
});

test('a guest cannot vote', async () => {
  await assertFails(vote(guest(env, 'guest'), 'guest', 1));
});

test('a scout cannot use double weight', async () => {
  await assertFails(vote(googleUser(env, 'scout'), 'scout', 2));
});

test('a reporter cannot vote on their own report', async () => {
  await seed(env, { 'users/reporter': profile({ tier: 2 }) });
  await assertFails(vote(googleUser(env, 'reporter'), 'reporter', 1));
});

test('netVotes must move by exactly the vote value', async () => {
  await assertFails(vote(googleUser(env, 'scout'), 'scout', 1, { netVotes: 5 }));
});

test('one vote per user', async () => {
  const db = googleUser(env, 'scout');
  await assertSucceeds(vote(db, 'scout', 1));
  await assertFails(vote(db, 'scout', 1, { netVotes: 2 }));
});

test('a report at -3 must be quarantined in the same write', async () => {
  await seed(env, { 'incidents/i1': newIncident('reporter', { netVotes: -1 }) });
  const db = googleUser(env, 'sentinel');
  await assertFails(vote(db, 'sentinel', -2, { netVotes: -3 }));
  await assertSucceeds(vote(db, 'sentinel', -2, { netVotes: -3, visibility: 'QUARANTINED' }));
});

test('a report above -3 cannot be quarantined by a vote', async () => {
  await assertFails(vote(googleUser(env, 'scout'), 'scout', -1, { netVotes: -1, visibility: 'QUARANTINED' }));
});
