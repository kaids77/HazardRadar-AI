import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, getDocs, limit, orderBy, query, Timestamp, where } from 'firebase/firestore';

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
    'users/guest': profile(),
    'users/scout': profile({ tier: 2 }),
    'users/admin': profile({ role: 'ADMIN', tier: 5 }),
    'incidents/a': { ...newIncident('someone'), createdAt: Timestamp.fromMillis(3000) },
    'incidents/b': { ...newIncident('scout'), createdAt: Timestamp.fromMillis(2000) },
    'incidents/c': { ...newIncident('someone'), visibility: 'QUARANTINED', createdAt: Timestamp.fromMillis(1000) },
  });
});

/** The exact query the Radar map runs (FirestoreIncidentRepository.watchActivePublic). */
function mapQuery(db) {
  return query(
    collection(db, 'incidents'),
    where('visibility', '==', 'PUBLIC'),
    where('status', 'in', ['ACTIVE', 'IN_PROGRESS']),
    orderBy('createdAt', 'desc'),
    limit(150),
  );
}

test('a guest, a Google user, and an admin can all load the public map', async () => {
  for (const db of [guest(env, 'guest'), googleUser(env, 'scout'), googleUser(env, 'admin')]) {
    const snapshot = await assertSucceeds(getDocs(mapQuery(db)));
    assert.deepEqual(snapshot.docs.map((d) => d.id), ['a', 'b']);
  }
});

test('a signed-in user with no profile document can still load the public map', async () => {
  const snapshot = await assertSucceeds(getDocs(mapQuery(googleUser(env, 'brand-new'))));
  assert.equal(snapshot.size, 2);
});

test('a citizen cannot list quarantined reports they do not own', async () => {
  const everything = query(collection(googleUser(env, 'scout'), 'incidents'), where('visibility', '==', 'QUARANTINED'));
  await assertFails(getDocs(everything));
});
