import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getCountFromServer,
  query,
  serverTimestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

import { createEnv, googleUser, newIncident, profile, seed } from './helpers.js';

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
    'users/rep': profile({ tier: 2, reportsRemoved: 1 }),
    'users/other': profile({ tier: 2 }),
    'users/disp': profile({ role: 'DISPATCHER', tier: 4 }),
    'users/admin': profile({ role: 'ADMIN', tier: 5 }),
    'incidents/q': { ...newIncident('rep'), visibility: 'QUARANTINED', netVotes: -3 },
    'incidents/open': { ...newIncident('rep') },
  });
});

/** The purge transaction as the app sends it: delete, log entry, and the removal count. */
function purge(uid, { id = 'q', removed = 2, reporter = 'rep', deleteReport = true, extra = {} } = {}) {
  const db = googleUser(env, uid);
  const batch = writeBatch(db);
  if (deleteReport) batch.delete(doc(db, `incidents/${id}`));
  batch.set(doc(db, `transparency/${id}`), {
    category: 'Pothole',
    riskLevel: 'Medium',
    kind: 'PURGED',
    reason: '',
    crew: '',
    resolutionNote: '',
    at: serverTimestamp(),
  });
  batch.update(doc(db, `users/${reporter}`), { reportsRemoved: removed, lastRemovedId: id, ...extra });
  return batch.commit();
}

test('an admin purge raises the reporter removal count by exactly one', async () => {
  await assertFails(purge('admin', { removed: 3 }));
  await assertFails(purge('admin', { removed: 1 }));
  await assertSucceeds(purge('admin'));
});

test('dispatchers cannot count removals', async () => {
  await assertFails(purge('disp'));
});

test('the count goes only to the reporter of the deleted report', async () => {
  await assertFails(purge('admin', { reporter: 'other', removed: 1 }));
});

test('the count needs the report to be deleted in the same write', async () => {
  await assertFails(purge('admin', { deleteReport: false }));
  const db = googleUser(env, 'admin');
  await assertFails(updateDoc(doc(db, 'users/rep'), { reportsRemoved: 2, lastRemovedId: 'gone' }));
});

test('a public report cannot be counted as removed', async () => {
  const db = googleUser(env, 'admin');
  const batch = writeBatch(db);
  batch.delete(doc(db, 'incidents/open'));
  batch.update(doc(db, 'users/rep'), { reportsRemoved: 2, lastRemovedId: 'open' });
  await assertFails(batch.commit());
});

test('the removal count cannot change other profile fields', async () => {
  await assertFails(purge('admin', { extra: { ctp: 500 } }));
});

test('the reporter cannot raise or lower their own removal count', async () => {
  const db = googleUser(env, 'rep');
  await assertFails(updateDoc(doc(db, 'users/rep'), { reportsRemoved: 0 }));
});

test('staff count a user\'s quarantined reports; other users cannot', async () => {
  const count = (uid) => {
    const db = googleUser(env, uid);
    return getCountFromServer(
      query(collection(db, 'incidents'), where('reporterUid', '==', 'rep'), where('visibility', '==', 'QUARANTINED')),
    );
  };
  await assertSucceeds(count('disp'));
  await assertSucceeds(count('admin'));
  await assertFails(count('other'));
});
