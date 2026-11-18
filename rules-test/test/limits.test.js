import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, Timestamp, updateDoc } from 'firebase/firestore';

import { createEnv, fileReport, googleUser, guest, phToday, profile, seed } from './helpers.js';

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

test('a guest files 3 reports a day, not 4', async () => {
  await seed(env, { 'users/g': profile({ reportDay: phToday(), reportCount: 2 }) });
  const db = guest(env, 'g');
  await assertSucceeds(fileReport(db, 'g', 'r3', { count: 3 }));
  await assertFails(fileReport(db, 'g', 'r4', { count: 4 }));
});

test('a Civic Scout files 10 a day, not 11', async () => {
  await seed(env, { 'users/s': profile({ tier: 2, reportDay: phToday(), reportCount: 9 }) });
  const db = googleUser(env, 's');
  await assertSucceeds(fileReport(db, 's', 'r10', { count: 10 }));
  await assertFails(fileReport(db, 's', 'r11', { count: 11 }));
});

test('Level 3 and up have no daily limit', async () => {
  await seed(env, { 'users/v': profile({ tier: 3, role: 'VERIFIER', reportDay: phToday(), reportCount: 50 }) });
  await assertSucceeds(fileReport(googleUser(env, 'v'), 'v', 'r51', { count: 51 }));
});

test('the count resets on a new Philippine day', async () => {
  await seed(env, { 'users/g': profile({ reportDay: phToday(-1), reportCount: 3 }) });
  const db = guest(env, 'g');
  await assertFails(fileReport(db, 'g', 'wrong', { count: 4 }));
  await assertSucceeds(fileReport(db, 'g', 'r1', { count: 1 }));
});

test('the client cannot lie about the day or the count', async () => {
  await seed(env, { 'users/g': profile({ reportDay: phToday(), reportCount: 2 }) });
  const db = guest(env, 'g');
  await assertFails(fileReport(db, 'g', 'r1', { count: 1 }));
  await assertFails(fileReport(db, 'g', 'r2', { count: 3, day: phToday(1) }));
});

test('an admin override lifts the limit', async () => {
  await seed(env, { 'users/g': profile({ reportDay: phToday(), reportCount: 3, rateLimitOverride: true }) });
  await assertSucceeds(fileReport(guest(env, 'g'), 'g', 'r4', { count: 4 }));
});

test('the counter cannot be changed without filing a report', async () => {
  await seed(env, { 'users/g': profile({ reportDay: phToday(), reportCount: 3 }) });
  const db = guest(env, 'g');
  await assertFails(updateDoc(doc(db, 'users/g'), { reportCount: 0 }));
  await assertFails(updateDoc(doc(db, 'users/g'), { reportCount: 0, lastReportId: 'nope' }));
});

test('the counter update cannot change other profile fields', async () => {
  await seed(env, { 'users/g': profile() });
  await assertFails(fileReport(guest(env, 'g'), 'g', 'r1', { profileExtra: { tier: 3 } }));
});

test('a suspended user is blocked until suspendedUntil', async () => {
  const future = Timestamp.fromMillis(Date.now() + 3600 * 1000);
  const past = Timestamp.fromMillis(Date.now() - 3600 * 1000);
  await seed(env, {
    'users/later': profile({ accountStatus: 'SUSPENDED', suspendedUntil: future }),
    'users/ended': profile({ accountStatus: 'SUSPENDED', suspendedUntil: past }),
    'users/forever': profile({ accountStatus: 'SUSPENDED' }),
  });
  await assertFails(fileReport(guest(env, 'later'), 'later', 'a'));
  await assertFails(fileReport(guest(env, 'forever'), 'forever', 'b'));
  await assertSucceeds(fileReport(guest(env, 'ended'), 'ended', 'c'));
});

test('a warned user can still report', async () => {
  await seed(env, { 'users/w': profile({ accountStatus: 'WARNED' }) });
  await assertSucceeds(fileReport(guest(env, 'w'), 'w', 'r1'));
});
