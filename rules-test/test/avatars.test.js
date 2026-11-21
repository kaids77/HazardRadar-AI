import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, Timestamp } from 'firebase/firestore';

import { createEnv, googleUser, profile, seed } from './helpers.js';

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
    'users/alice': profile({ tier: 2 }),
    'users/bob': profile({ tier: 2 }),
    'users/banned': profile({ tier: 2, accountStatus: 'BANNED' }),
    'users/disp': profile({ role: 'DISPATCHER', tier: 4 }),
    'avatars/bob': { imageBase64: 'abc', updatedAt: Timestamp.now() },
  });
});

const photo = (overrides = {}) => ({ imageBase64: 'abc', updatedAt: serverTimestamp(), ...overrides });

test('a user saves, replaces, and removes their own photo', async () => {
  const db = googleUser(env, 'alice');
  await assertSucceeds(setDoc(doc(db, 'avatars/alice'), photo()));
  await assertSucceeds(setDoc(doc(db, 'avatars/alice'), photo({ imageBase64: 'def' })));
  await assertSucceeds(getDoc(doc(db, 'avatars/alice')));
  await assertSucceeds(deleteDoc(doc(db, 'avatars/alice')));
});

test('nobody writes or deletes another user photo', async () => {
  const db = googleUser(env, 'alice');
  await assertFails(setDoc(doc(db, 'avatars/bob'), photo()));
  await assertFails(deleteDoc(doc(db, 'avatars/bob')));
});

test('photos are readable by the owner and staff only', async () => {
  await assertFails(getDoc(doc(googleUser(env, 'alice'), 'avatars/bob')));
  await assertSucceeds(getDoc(doc(googleUser(env, 'disp'), 'avatars/bob')));
});

test('oversized, extra-field, wrong-time, and banned writes are refused', async () => {
  const db = googleUser(env, 'alice');
  await assertFails(setDoc(doc(db, 'avatars/alice'), photo({ imageBase64: 'a'.repeat(40001) })));
  await assertSucceeds(setDoc(doc(db, 'avatars/alice'), photo({ imageBase64: 'a'.repeat(40000) })));
  await assertFails(setDoc(doc(db, 'avatars/alice'), photo({ imageBase64: '' })));
  await assertFails(setDoc(doc(db, 'avatars/alice'), photo({ extra: true })));
  await assertFails(setDoc(doc(db, 'avatars/alice'), photo({ updatedAt: Timestamp.fromMillis(0) })));
  await assertFails(setDoc(doc(googleUser(env, 'banned'), 'avatars/banned'), photo()));
});
