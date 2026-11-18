import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, serverTimestamp, setDoc, updateDoc, writeBatch } from 'firebase/firestore';

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
    'users/alice': profile(),
    'users/banned': profile({ accountStatus: 'BANNED' }),
  });
});

function photo(uid) {
  return { reporterUid: uid, mimeType: 'image/jpeg', imageBase64: 'abc', createdAt: serverTimestamp() };
}

test('a user creates a report and its photo in one batch', async () => {
  const db = guest(env, 'alice');
  const batch = writeBatch(db);
  batch.set(doc(db, 'incidents/i1'), { ...newIncident('alice'), createdAt: serverTimestamp() });
  batch.set(doc(db, 'incidents/i1/photo/main'), photo('alice'));
  await assertSucceeds(batch.commit());
});

test('report create rejects bad fields', async () => {
  const db = guest(env, 'alice');
  const bad = [
    newIncident('bob'),
    newIncident('alice', { status: 'RESOLVED' }),
    newIncident('alice', { visibility: 'QUARANTINED' }),
    newIncident('alice', { netVotes: 5 }),
    newIncident('alice', { riskLevel: 'Critical' }),
    newIncident('alice', { note: 'x'.repeat(501) }),
    newIncident('alice', { latitude: 95 }),
    newIncident('alice', { category: 'Road' }),
    newIncident('alice', { aiProcessed: 'yes' }),
    { ...newIncident('alice'), extra: 1 },
  ];
  for (const [i, data] of bad.entries()) {
    await assertFails(setDoc(doc(db, `incidents/bad${i}`), data));
  }
  const { aiProcessed, ...missingFlag } = newIncident('alice');
  await assertFails(setDoc(doc(db, 'incidents/noflag'), missingFlag));
});

test('every fixed category is accepted', async () => {
  const db = guest(env, 'alice');
  for (const category of ['Pothole', 'Electrical', 'Flooding', 'Obstruction', 'Lighting', 'Other']) {
    await assertSucceeds(setDoc(doc(db, `incidents/${category}`), newIncident('alice', { category })));
  }
});

const aiResult = {
  category: 'Electrical',
  riskLevel: 'High',
  aiSummary: 'Sparking wire.',
  recommendedAction: 'Call the utility.',
  aiProcessed: true,
};

test('the owner applies the AI result once to an offline-triaged report', async () => {
  await seed(env, { 'incidents/i1': newIncident('alice', { aiProcessed: false }) });
  const db = guest(env, 'alice');
  await assertSucceeds(updateDoc(doc(db, 'incidents/i1'), aiResult));
  await assertFails(updateDoc(doc(db, 'incidents/i1'), { ...aiResult, riskLevel: 'Low' }));
});

test('AI enrichment is limited to the owner, triage fields, and valid values', async () => {
  await seed(env, { 'incidents/i1': newIncident('alice', { aiProcessed: false }) });
  await assertFails(updateDoc(doc(guest(env, 'bob'), 'incidents/i1'), aiResult));
  const db = guest(env, 'alice');
  await assertFails(updateDoc(doc(db, 'incidents/i1'), { ...aiResult, netVotes: 10 }));
  await assertFails(updateDoc(doc(db, 'incidents/i1'), { ...aiResult, category: 'Road' }));
  await assertFails(updateDoc(doc(db, 'incidents/i1'), { ...aiResult, aiProcessed: false }));
});

test('an AI-processed report cannot be re-triaged by its owner', async () => {
  await seed(env, { 'incidents/i1': newIncident('alice') });
  await assertFails(updateDoc(doc(guest(env, 'alice'), 'incidents/i1'), aiResult));
});

test('a banned user cannot report', async () => {
  await assertFails(setDoc(doc(guest(env, 'banned'), 'incidents/i1'), newIncident('banned')));
});

test('a photo must belong to a report by the same user', async () => {
  await seed(env, { 'incidents/i1': newIncident('bob') });
  const db = guest(env, 'alice');
  await assertFails(setDoc(doc(db, 'incidents/i1/photo/main'), photo('alice')));
});

test('public reports are readable, quarantined ones only by the owner', async () => {
  await seed(env, {
    'incidents/pub': newIncident('bob'),
    'incidents/q': newIncident('bob', { visibility: 'QUARANTINED' }),
  });
  const db = guest(env, 'alice');
  await assertSucceeds(getDoc(doc(db, 'incidents/pub')));
  await assertFails(getDoc(doc(db, 'incidents/q')));
  await assertSucceeds(getDoc(doc(guest(env, 'bob'), 'incidents/q')));
});

test('owners cannot edit their report', async () => {
  await seed(env, { 'incidents/i1': newIncident('alice') });
  await assertFails(updateDoc(doc(guest(env, 'alice'), 'incidents/i1'), { riskLevel: 'High' }));
});
