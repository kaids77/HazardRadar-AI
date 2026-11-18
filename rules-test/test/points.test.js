import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, updateDoc } from 'firebase/firestore';

import { createEnv, fileReport, googleUser, guest, profile, seed } from './helpers.js';

let env;

before(async () => {
  env = await createEnv();
});
after(async () => {
  await env.cleanup();
});
beforeEach(async () => {
  await env.clearFirestore();
});

test('publishing earns exactly +10 CTP and +1 report', async () => {
  await seed(env, { 'users/g': profile({ ctp: 40, reportsTotal: 4 }) });
  const db = guest(env, 'g');
  await assertFails(fileReport(db, 'g', 'r1', { ctp: 60, total: 5 }));
  await assertFails(fileReport(db, 'g', 'r1', { ctp: 50, total: 4 }));
  await assertSucceeds(fileReport(db, 'g', 'r1', { ctp: 50, total: 5 }));
});

test('points cannot be added without a report', async () => {
  await seed(env, { 'users/g': profile({ ctp: 40 }) });
  await assertFails(updateDoc(doc(guest(env, 'g'), 'users/g'), { ctp: 50 }));
});

test('a guest with 50 CTP becomes a Civic Scout without Google', async () => {
  await seed(env, { 'users/g': profile({ ctp: 50 }), 'users/low': profile({ ctp: 40 }) });
  await assertSucceeds(updateDoc(doc(guest(env, 'g'), 'users/g'), { tier: 2 }));
  await assertFails(updateDoc(doc(guest(env, 'low'), 'users/low'), { tier: 2 }));
});

test('a scout becomes a Sentinel at 250 CTP with 85% resolved', async () => {
  await seed(env, {
    'users/ok': profile({ tier: 2, ctp: 250, reportsTotal: 20, reportsResolved: 17 }),
    'users/inaccurate': profile({ tier: 2, ctp: 300, reportsTotal: 20, reportsResolved: 16 }),
    'users/poor': profile({ tier: 2, ctp: 200, reportsTotal: 10, reportsResolved: 10 }),
  });
  await assertSucceeds(updateDoc(doc(googleUser(env, 'ok'), 'users/ok'), { tier: 3, role: 'VERIFIER' }));
  await assertFails(updateDoc(doc(googleUser(env, 'inaccurate'), 'users/inaccurate'), { tier: 3, role: 'VERIFIER' }));
  await assertFails(updateDoc(doc(googleUser(env, 'poor'), 'users/poor'), { tier: 3, role: 'VERIFIER' }));
});

test('a level-up cannot skip levels, claim staff roles, or change points', async () => {
  await seed(env, { 'users/g': profile({ ctp: 500, reportsTotal: 10, reportsResolved: 10 }) });
  const db = guest(env, 'g');
  await assertFails(updateDoc(doc(db, 'users/g'), { tier: 3, role: 'VERIFIER' }));
  await assertFails(updateDoc(doc(db, 'users/g'), { tier: 2, ctp: 1000 }));
  await seed(env, { 'users/s': profile({ tier: 2, ctp: 500, reportsTotal: 10, reportsResolved: 10 }) });
  await assertFails(updateDoc(doc(googleUser(env, 's'), 'users/s'), { tier: 3, role: 'ADMIN' }));
});

test('a suspended user cannot level up', async () => {
  await seed(env, { 'users/g': profile({ ctp: 100, accountStatus: 'SUSPENDED' }) });
  await assertFails(updateDoc(doc(guest(env, 'g'), 'users/g'), { tier: 2 }));
});

test('only Sentinels pick a focus badge, from the fixed list', async () => {
  await seed(env, { 'users/v': profile({ tier: 3, role: 'VERIFIER' }), 'users/s': profile({ tier: 2 }) });
  await assertSucceeds(updateDoc(doc(googleUser(env, 'v'), 'users/v'), { focusBadge: 'Grid Guardian' }));
  await assertFails(updateDoc(doc(googleUser(env, 'v'), 'users/v'), { focusBadge: 'Boss' }));
  await assertFails(updateDoc(doc(googleUser(env, 's'), 'users/s'), { focusBadge: 'Grid Guardian' }));
});
