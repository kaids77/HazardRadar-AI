import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';

import { createEnv, fileReport, guest, newIncident, profile, seed } from './helpers.js';

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

test('a user files a report, photo, and counter update in one batch', async () => {
  await assertSucceeds(fileReport(guest(env, 'alice'), 'alice', 'i1'));
});

test('a report without the counter update is refused', async () => {
  await assertFails(setDoc(doc(guest(env, 'alice'), 'incidents/i1'), newIncident('alice')));
});

test('report create rejects bad fields', async () => {
  const db = guest(env, 'alice');
  const bad = [
    { reporterUid: 'bob' },
    { status: 'RESOLVED' },
    { visibility: 'QUARANTINED' },
    { netVotes: 5 },
    { riskLevel: 'Critical' },
    { note: 'x'.repeat(501) },
    { latitude: 95 },
    { category: 'Road' },
    { aiProcessed: 'yes' },
    { reporterTier: 5 },
    { photoBytes: 200000 },
    { photoBytes: 0 },
    { extra: 1 },
  ];
  for (const [i, incident] of bad.entries()) {
    await assertFails(fileReport(db, 'alice', `bad${i}`, { incident }));
  }
});

test('every fixed category is accepted', async () => {
  await seed(env, { 'users/alice': profile({ rateLimitOverride: true }) });
  const db = guest(env, 'alice');
  const categories = ['Pothole', 'Electrical', 'Flooding', 'Obstruction', 'Lighting', 'Other'];
  for (const [i, category] of categories.entries()) {
    await assertSucceeds(fileReport(db, 'alice', category, { count: i + 1, incident: { category } }));
  }
});

test('a banned user cannot report', async () => {
  await assertFails(fileReport(guest(env, 'banned'), 'banned', 'i1'));
});

test('a photo must belong to a report by the same user', async () => {
  await seed(env, { 'incidents/i1': newIncident('bob') });
  const photo = { reporterUid: 'alice', mimeType: 'image/jpeg', imageBase64: 'abc', createdAt: serverTimestamp() };
  await assertFails(setDoc(doc(guest(env, 'alice'), 'incidents/i1/photo/main'), photo));
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
