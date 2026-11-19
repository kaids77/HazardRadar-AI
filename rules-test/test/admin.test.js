import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDocs, Timestamp, updateDoc } from 'firebase/firestore';

import { createEnv, googleUser, guest, profile, seed } from './helpers.js';

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
    'users/admin': profile({ role: 'ADMIN', tier: 5 }),
    'users/disp': profile({ role: 'DISPATCHER', tier: 4 }),
    'users/bob': profile({ tier: 2 }),
  });
});

const admin = () => googleUser(env, 'admin');

test('an admin promotes a user to dispatcher with the matching level', async () => {
  await assertSucceeds(updateDoc(doc(admin(), 'users/bob'), { role: 'DISPATCHER', tier: 4 }));
});

test('role and level must match', async () => {
  await assertFails(updateDoc(doc(admin(), 'users/bob'), { role: 'DISPATCHER', tier: 2 }));
  await assertFails(updateDoc(doc(admin(), 'users/bob'), { role: 'CITIZEN', tier: 5 }));
  await assertFails(updateDoc(doc(admin(), 'users/bob'), { role: 'KING', tier: 9 }));
});

test('an admin suspends until a date, bans, and sets the rate-limit override', async () => {
  const db = admin();
  await assertSucceeds(
    updateDoc(doc(db, 'users/bob'), { accountStatus: 'SUSPENDED', suspendedUntil: Timestamp.fromMillis(Date.now() + 86400000) }),
  );
  await assertSucceeds(updateDoc(doc(db, 'users/bob'), { accountStatus: 'BANNED', suspendedUntil: null }));
  await assertSucceeds(updateDoc(doc(db, 'users/bob'), { rateLimitOverride: true }));
  await assertFails(updateDoc(doc(db, 'users/bob'), { accountStatus: 'DELETED' }));
  await assertFails(updateDoc(doc(db, 'users/bob'), { ctp: 9999 }));
});

test('an admin cannot change their own role or status', async () => {
  await assertFails(updateDoc(doc(admin(), 'users/admin'), { accountStatus: 'BANNED' }));
  await assertFails(updateDoc(doc(admin(), 'users/admin'), { role: 'CITIZEN', tier: 1 }));
});

test('dispatchers and citizens cannot manage users', async () => {
  await assertFails(updateDoc(doc(googleUser(env, 'disp'), 'users/bob'), { accountStatus: 'BANNED' }));
  await assertFails(updateDoc(doc(googleUser(env, 'bob'), 'users/disp'), { accountStatus: 'BANNED' }));
});

test('staff list users; citizens cannot', async () => {
  await assertSucceeds(getDocs(collection(admin(), 'users')));
  await assertFails(getDocs(collection(guest(env, 'bob'), 'users')));
});

test('a user sets only their own display name, up to 40 characters', async () => {
  const db = googleUser(env, 'bob');
  await assertSucceeds(updateDoc(doc(db, 'users/bob'), { displayName: 'Bob Santos' }));
  await assertFails(updateDoc(doc(db, 'users/bob'), { displayName: 'x'.repeat(41) }));
  await assertFails(updateDoc(doc(db, 'users/disp'), { displayName: 'Hacked' }));
  await assertFails(updateDoc(doc(db, 'users/bob'), { displayName: 'Bob', tier: 3 }));
});
