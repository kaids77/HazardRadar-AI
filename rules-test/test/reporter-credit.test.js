import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc, Timestamp, updateDoc, writeBatch } from 'firebase/firestore';

import { createEnv, googleUser, guest, newIncident, profile, seed } from './helpers.js';

let env;

before(async () => {
  env = await createEnv();
});

after(async () => {
  await env.cleanup();
});

const resolvedAt = Timestamp.fromMillis(1_700_000_000_000);

beforeEach(async () => {
  await env.clearFirestore();
  await seed(env, {
    'users/fan': profile({ tier: 2, displayName: 'Bob Santos', creditName: true }),
    'users/shy': profile({ tier: 2, displayName: 'Ana Cruz' }),
    'users/newbie': profile({ tier: 1 }),
    'users/banned': profile({ tier: 2, accountStatus: 'BANNED', creditName: true }),
    'users/disp': profile({ role: 'DISPATCHER', tier: 4 }),
    'incidents/fanWork': { ...newIncident('fan'), status: 'IN_PROGRESS', assignedCrew: 'Crew 4' },
    'incidents/shyWork': { ...newIncident('shy'), status: 'IN_PROGRESS', assignedCrew: 'Crew 4' },
    'incidents/fanOld': {
      ...newIncident('fan'),
      status: 'RESOLVED',
      assignedCrew: 'Crew 7',
      resolutionNote: 'Patched.',
      resolvedAt,
    },
    'incidents/fanQ': { ...newIncident('fan'), visibility: 'QUARANTINED', netVotes: -3 },
  });
});

function entry(overrides = {}) {
  return {
    category: 'Pothole',
    riskLevel: 'Medium',
    kind: 'RESOLVED',
    reason: '',
    crew: 'Crew 4',
    resolutionNote: 'Patched.',
    at: serverTimestamp(),
    ...overrides,
  };
}

/** The resolve transaction as the app sends it, for the reporter [uid] of `${uid}Work`. */
function resolve(uid, log = {}) {
  const db = googleUser(env, 'disp');
  const batch = writeBatch(db);
  batch.update(doc(db, `incidents/${uid}Work`), {
    status: 'RESOLVED',
    resolvedAt: serverTimestamp(),
    resolvedBy: 'disp',
    resolutionNote: 'Patched.',
  });
  batch.update(doc(db, `users/${uid}`), { ctp: 10, reportsResolved: 1, lastResolvedId: `${uid}Work` });
  batch.set(doc(db, `transparency/${uid}Work`), entry(log));
  return batch.commit();
}

test('an account turns its own credit on and off', async () => {
  const db = googleUser(env, 'shy');
  await assertSucceeds(updateDoc(doc(db, 'users/shy'), { creditName: true }));
  await assertSucceeds(updateDoc(doc(db, 'users/shy'), { creditName: false }));
  await assertFails(updateDoc(doc(db, 'users/shy'), { creditName: 'yes' }));
  await assertFails(updateDoc(doc(db, 'users/shy'), { creditName: true, ctp: 999 }));
});

test('guests and other users cannot set the credit', async () => {
  await assertFails(updateDoc(doc(guest(env, 'newbie'), 'users/newbie'), { creditName: true }));
  await assertFails(updateDoc(doc(googleUser(env, 'fan'), 'users/shy'), { creditName: true }));
});

test('a blocked account can turn the credit off but not on', async () => {
  const db = googleUser(env, 'banned');
  await assertSucceeds(updateDoc(doc(db, 'users/banned'), { creditName: false }));
  await assertFails(updateDoc(doc(db, 'users/banned'), { creditName: true }));
});

test('a resolved entry may name a reporter who opted in, with their exact name', async () => {
  await assertFails(resolve('fan', { reporterName: 'Someone Else' }));
  await assertSucceeds(resolve('fan', { reporterName: 'Bob Santos' }));
});

test('a resolved entry may not name a reporter who did not opt in', async () => {
  await assertFails(resolve('shy', { reporterName: 'Ana Cruz' }));
  await assertSucceeds(resolve('shy'));
});

test('quarantine entries never carry a name', async () => {
  const db = googleUser(env, 'disp');
  await assertFails(
    setDoc(doc(db, 'transparency/fanQ'), entry({
      kind: 'QUARANTINED',
      reason: 'COMMUNITY_VOTES',
      crew: '',
      resolutionNote: '',
      reporterName: 'Bob Santos',
    })),
  );
});

test('staff sync an older resolved report with the opted-in name', async () => {
  const db = googleUser(env, 'disp');
  const log = entry({ crew: 'Crew 7', at: resolvedAt });
  await assertFails(setDoc(doc(db, 'transparency/fanOld'), { ...log, reporterName: 'Wrong Name' }));
  await assertSucceeds(setDoc(doc(db, 'transparency/fanOld'), { ...log, reporterName: 'Bob Santos' }));
});

test('a reporter updates their own resolved entry when toggling their name credit', async () => {
  const fanDb = googleUser(env, 'fan');
  const shyDb = googleUser(env, 'shy');
  const log = entry({ crew: 'Crew 7', at: resolvedAt });

  // The reporter can add their opted-in name to their own already-resolved report.
  await assertSucceeds(setDoc(doc(fanDb, 'transparency/fanOld'), { ...log, reporterName: 'Bob Santos' }));
  // Another citizen cannot write someone else's resolved report.
  await assertFails(setDoc(doc(shyDb, 'transparency/fanOld'), log));
  // Turning the credit off lets the reporter remove their name from their resolved entry.
  await assertSucceeds(updateDoc(doc(fanDb, 'users/fan'), { creditName: false }));
  await assertFails(setDoc(doc(fanDb, 'transparency/fanOld'), { ...log, reporterName: 'Bob Santos' }));
  await assertSucceeds(setDoc(doc(fanDb, 'transparency/fanOld'), log));
});
