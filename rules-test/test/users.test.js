import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';

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
});

test('a user can create only their own Level 1 profile', async () => {
  const db = guest(env, 'alice');
  await assertSucceeds(setDoc(doc(db, 'users/alice'), { ...profile(), createdAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, 'users/bob'), profile()));
});

test('a new profile cannot start above Level 1 or as staff', async () => {
  const db = guest(env, 'alice');
  await assertFails(setDoc(doc(db, 'users/alice'), profile({ tier: 2 })));
  await assertFails(setDoc(doc(db, 'users/alice'), profile({ role: 'ADMIN' })));
  await assertFails(setDoc(doc(db, 'users/alice'), profile({ accountStatus: 'BANNED' })));
  await assertFails(setDoc(doc(db, 'users/alice'), { ...profile(), extra: true }));
});

test('users read their own profile but not others', async () => {
  await seed(env, { 'users/alice': profile(), 'users/bob': profile() });
  const db = guest(env, 'alice');
  await assertSucceeds(getDoc(doc(db, 'users/alice')));
  await assertFails(getDoc(doc(db, 'users/bob')));
});

test('tier 1 to 2 needs a linked Google identity', async () => {
  await seed(env, { 'users/alice': profile() });
  await assertFails(updateDoc(doc(guest(env, 'alice'), 'users/alice'), { tier: 2 }));
  await assertSucceeds(updateDoc(doc(googleUser(env, 'alice'), 'users/alice'), { tier: 2 }));
});

test('a Google user cannot jump to tier 3 or change their role', async () => {
  await seed(env, { 'users/alice': profile() });
  const db = googleUser(env, 'alice');
  await assertFails(updateDoc(doc(db, 'users/alice'), { tier: 3 }));
  await assertFails(updateDoc(doc(db, 'users/alice'), { tier: 2, role: 'ADMIN' }));
});

test('a banned user cannot upgrade', async () => {
  await seed(env, { 'users/alice': profile({ accountStatus: 'BANNED' }) });
  await assertFails(updateDoc(doc(googleUser(env, 'alice'), 'users/alice'), { tier: 2 }));
});

test('an admin changes role and status of another user', async () => {
  await seed(env, {
    'users/admin': profile({ role: 'ADMIN', tier: 5 }),
    'users/bob': profile(),
  });
  const db = googleUser(env, 'admin');
  await assertSucceeds(updateDoc(doc(db, 'users/bob'), { accountStatus: 'BANNED' }));
  await assertFails(updateDoc(doc(guest(env, 'bob'), 'users/admin'), { accountStatus: 'BANNED' }));
});
