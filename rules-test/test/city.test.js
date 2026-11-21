import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, serverTimestamp, updateDoc, writeBatch } from 'firebase/firestore';

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
    'users/disp': profile({ role: 'DISPATCHER', tier: 4 }),
    'users/admin': profile({ role: 'ADMIN', tier: 5 }),
    'users/rep': profile({ ctp: 20, reportsResolved: 1 }),
    'users/citizen': profile({ tier: 2 }),
    'users/sentinel': profile({ tier: 3, role: 'VERIFIER' }),
    'incidents/a': newIncident('rep'),
    'incidents/p': newIncident('rep', { status: 'IN_PROGRESS' }),
    'incidents/q': newIncident('rep', { visibility: 'QUARANTINED', netVotes: -3 }),
  });
});

const staff = () => googleUser(env, 'disp');

function resolve(db, id, { note = 'Patched by crew B.', ctp = 30, resolved = 2, credit = true, by = 'disp' } = {}) {
  const batch = writeBatch(db);
  batch.update(doc(db, `incidents/${id}`), {
    status: 'RESOLVED',
    resolvedAt: serverTimestamp(),
    resolvedBy: by,
    resolutionNote: note,
  });
  if (credit) {
    batch.update(doc(db, 'users/rep'), { ctp, reportsResolved: resolved, lastResolvedId: id });
  }
  return batch.commit();
}

test('a dispatcher moves ACTIVE to IN_PROGRESS with a server timestamp and a crew', async () => {
  await assertSucceeds(
    updateDoc(doc(staff(), 'incidents/a'), {
      status: 'IN_PROGRESS',
      inProgressAt: serverTimestamp(),
      assignedCrew: 'DPWH Patch Crew 4',
    }),
  );
});

test('IN_PROGRESS needs the inProgressAt stamp and cannot skip or go back', async () => {
  const db = staff();
  await assertFails(updateDoc(doc(db, 'incidents/a'), { status: 'IN_PROGRESS' }));
  await assertFails(updateDoc(doc(db, 'incidents/a'), { status: 'RESOLVED', resolvedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db, 'incidents/p'), { status: 'ACTIVE' }));
});

test('resolving needs a note and credits the reporter +10 CTP in the same write', async () => {
  const db = staff();
  await assertFails(resolve(db, 'p', { credit: false }));
  await assertFails(resolve(db, 'p', { note: '' }));
  await assertFails(resolve(db, 'p', { note: 'x'.repeat(301) }));
  await assertFails(resolve(db, 'p', { ctp: 99 }));
  await assertFails(resolve(db, 'p', { by: 'someone-else' }));
  await assertSucceeds(resolve(db, 'p'));
});

test('a reporter cannot be credited without a real resolution', async () => {
  const db = staff();
  await assertFails(updateDoc(doc(db, 'users/rep'), { ctp: 30, reportsResolved: 2, lastResolvedId: 'a' }));
});

test('citizens cannot change status', async () => {
  await assertFails(
    updateDoc(doc(googleUser(env, 'citizen'), 'incidents/a'), { status: 'IN_PROGRESS', inProgressAt: serverTimestamp() }),
  );
  await assertFails(resolve(googleUser(env, 'citizen'), 'p'));
});

test('a dispatcher overrides the AI category and risk with valid values only', async () => {
  const db = staff();
  await assertSucceeds(updateDoc(doc(db, 'incidents/a'), { category: 'Electrical', riskLevel: 'High' }));
  await assertFails(updateDoc(doc(db, 'incidents/a'), { category: 'Road' }));
  await assertFails(updateDoc(doc(db, 'incidents/a'), { assignedCrew: 'x'.repeat(61) }));
});

test('staff restore a quarantined report with netVotes reset to 0', async () => {
  const db = staff();
  await assertFails(updateDoc(doc(db, 'incidents/q'), { visibility: 'PUBLIC' }));
  await assertSucceeds(updateDoc(doc(db, 'incidents/q'), { visibility: 'PUBLIC', netVotes: 0 }));
});

test('a Sentinel flags someone else\'s public report into quarantine', async () => {
  const db = googleUser(env, 'sentinel');
  await assertSucceeds(updateDoc(doc(db, 'incidents/a'), { visibility: 'QUARANTINED', flaggedBy: 'sentinel' }));
});

test('a Civic Scout cannot flag, and a Sentinel cannot flag their own report', async () => {
  await assertFails(
    updateDoc(doc(googleUser(env, 'citizen'), 'incidents/a'), { visibility: 'QUARANTINED', flaggedBy: 'citizen' }),
  );
  await seed(env, { 'incidents/own': newIncident('sentinel') });
  await assertFails(
    updateDoc(doc(googleUser(env, 'sentinel'), 'incidents/own'), { visibility: 'QUARANTINED', flaggedBy: 'sentinel' }),
  );
});

test('only an admin deletes a report, its photo, and its votes', async () => {
  await seed(env, {
    'incidents/q/photo/main': { reporterUid: 'rep', mimeType: 'image/jpeg', imageBase64: 'abc' },
    'incidents/q/votes/citizen': { value: -1 },
  });
  await assertFails(deleteDoc(doc(staff(), 'incidents/q/photo/main')));
  await assertFails(deleteDoc(doc(guest(env, 'rep'), 'incidents/q')));
  const db = googleUser(env, 'admin');
  await assertSucceeds(deleteDoc(doc(db, 'incidents/q/votes/citizen')));
  await assertSucceeds(deleteDoc(doc(db, 'incidents/q/photo/main')));
  await assertSucceeds(deleteDoc(doc(db, 'incidents/q')));
});
