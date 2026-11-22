import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, Timestamp, writeBatch } from 'firebase/firestore';

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
    'users/rep': profile({ tier: 2, ctp: 20, reportsResolved: 1 }),
    'users/scout': profile({ tier: 2 }),
    'users/sentinel': profile({ role: 'VERIFIER', tier: 3 }),
    'users/disp': profile({ role: 'DISPATCHER', tier: 4 }),
    'users/admin': profile({ role: 'ADMIN', tier: 5 }),
    'incidents/near': { ...newIncident('rep'), netVotes: -2 },
    'incidents/open': { ...newIncident('rep') },
    'incidents/work': { ...newIncident('rep'), status: 'IN_PROGRESS', assignedCrew: 'Crew 4' },
    'incidents/q': { ...newIncident('rep'), visibility: 'QUARANTINED', netVotes: -3 },
    'incidents/old': {
      ...newIncident('rep'),
      status: 'RESOLVED',
      assignedCrew: 'Crew 7',
      resolutionNote: 'Patched.',
      resolvedAt,
    },
  });
});

function entry(overrides = {}) {
  return {
    category: 'Pothole',
    riskLevel: 'Medium',
    kind: 'QUARANTINED',
    reason: 'COMMUNITY_VOTES',
    crew: '',
    resolutionNote: '',
    at: serverTimestamp(),
    ...overrides,
  };
}

/** The vote that moves "near" from -2 to -3, as the app sends it. */
function quarantineVote(db, { withEntry = true, log = {} } = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'incidents/near/votes/scout'), { value: -1, createdAt: serverTimestamp() });
  batch.update(doc(db, 'incidents/near'), { netVotes: -3, visibility: 'QUARANTINED' });
  if (withEntry) batch.set(doc(db, 'transparency/near'), entry(log));
  return batch.commit();
}

test('every signed-in user can read the log; nobody deletes it', async () => {
  await seed(env, { 'transparency/q': { ...entry(), at: Timestamp.now() } });
  await assertSucceeds(getDoc(doc(guest(env, 'stranger'), 'transparency/q')));
  await assertFails(deleteDoc(doc(googleUser(env, 'admin'), 'transparency/q')));
});

test('the quarantining vote writes a COMMUNITY_VOTES entry in the same batch', async () => {
  await assertSucceeds(quarantineVote(googleUser(env, 'scout')));
});

test('a quarantine entry must copy the report and give the right reason', async () => {
  const db = googleUser(env, 'scout');
  await assertFails(quarantineVote(db, { log: { category: 'Electrical' } }));
  await assertFails(quarantineVote(db, { log: { reason: 'SENTINEL_FLAG' } }));
  await assertFails(quarantineVote(db, { log: { crew: 'Fake crew' } }));
  await assertFails(quarantineVote(db, { log: { extra: true } }));
});

test('an entry alone, without the matching report change, is refused', async () => {
  await assertFails(setDoc(doc(googleUser(env, 'scout'), 'transparency/open'), entry()));
  await assertFails(setDoc(doc(googleUser(env, 'scout'), 'transparency/q'), entry()));
});

test('a Sentinel flag writes a SENTINEL_FLAG entry; the reason must match', async () => {
  const flag = (reason) => {
    const db = googleUser(env, 'sentinel');
    const batch = writeBatch(db);
    batch.update(doc(db, 'incidents/open'), { visibility: 'QUARANTINED', flaggedBy: 'sentinel' });
    batch.set(doc(db, 'transparency/open'), entry({ reason }));
    return batch.commit();
  };
  await assertFails(flag('COMMUNITY_VOTES'));
  await assertSucceeds(flag('SENTINEL_FLAG'));
});

test('the resolve transaction writes a RESOLVED entry with the crew and note', async () => {
  const resolve = (log) => {
    const db = googleUser(env, 'disp');
    const batch = writeBatch(db);
    batch.update(doc(db, 'incidents/work'), {
      status: 'RESOLVED',
      resolvedAt: serverTimestamp(),
      resolvedBy: 'disp',
      resolutionNote: 'Patched by crew 4.',
    });
    batch.update(doc(db, 'users/rep'), { ctp: 30, reportsResolved: 2, lastResolvedId: 'work' });
    batch.set(doc(db, 'transparency/work'), entry({
      kind: 'RESOLVED',
      reason: '',
      crew: 'Crew 4',
      resolutionNote: 'Patched by crew 4.',
      ...log,
    }));
    return batch.commit();
  };
  await assertFails(resolve({ crew: 'Someone else' }));
  await assertFails(resolve({ resolutionNote: 'Different note.' }));
  await assertSucceeds(resolve({}));
});

test('staff sync an older resolved report; citizens cannot', async () => {
  const log = entry({ kind: 'RESOLVED', reason: '', crew: 'Crew 7', resolutionNote: 'Patched.', at: resolvedAt });
  await assertFails(setDoc(doc(googleUser(env, 'scout'), 'transparency/old'), log));
  await assertFails(setDoc(doc(googleUser(env, 'disp'), 'transparency/old'), { ...log, at: Timestamp.now() }));
  await assertSucceeds(setDoc(doc(googleUser(env, 'disp'), 'transparency/old'), log));
});

test('staff sync an already quarantined report; citizens cannot', async () => {
  await assertFails(setDoc(doc(googleUser(env, 'scout'), 'transparency/q'), entry()));
  await assertSucceeds(setDoc(doc(googleUser(env, 'disp'), 'transparency/q'), entry()));
});

test('a restore by staff marks the entry RESTORED', async () => {
  const restore = (uid) => {
    const db = googleUser(env, uid);
    const batch = writeBatch(db);
    batch.update(doc(db, 'incidents/q'), { visibility: 'PUBLIC', netVotes: 0 });
    batch.set(doc(db, 'transparency/q'), entry({ kind: 'RESTORED', reason: '' }));
    return batch.commit();
  };
  await assertFails(restore('scout'));
  await assertSucceeds(restore('disp'));
});

test('an admin purge marks the entry PURGED in the deleting batch', async () => {
  const purge = (uid) => {
    const db = googleUser(env, uid);
    const batch = writeBatch(db);
    batch.delete(doc(db, 'incidents/q'));
    batch.set(doc(db, 'transparency/q'), entry({ kind: 'PURGED', reason: '' }));
    return batch.commit();
  };
  await assertFails(purge('disp'));
  await assertSucceeds(purge('admin'));
});

test('a PURGED entry cannot be written while the report still exists', async () => {
  await assertFails(setDoc(doc(googleUser(env, 'admin'), 'transparency/q'), entry({ kind: 'PURGED', reason: '' })));
});
