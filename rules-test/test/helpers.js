import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc, Timestamp, writeBatch } from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
const RULES_PATH = path.resolve(here, '..', '..', 'firestore.rules');

export const PROJECT_ID = 'demo-hazardradar';

/** Starts a test environment against the running Firestore emulator. */
export async function createEnv() {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8085').split(':');
  return initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host,
      port: Number(port),
    },
  });
}

/** Firestore for a guest (anonymous) user. */
export function guest(env, uid) {
  return env
    .authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous', identities: {} } })
    .firestore();
}

/** Firestore for a user with a linked Google account. */
export function googleUser(env, uid) {
  return env
    .authenticatedContext(uid, {
      firebase: { sign_in_provider: 'google.com', identities: { 'google.com': ['g-' + uid] } },
    })
    .firestore();
}

/** Writes documents with rules disabled. */
export async function seed(env, writes) {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [docPath, data] of Object.entries(writes)) {
      await setDoc(doc(db, docPath), data);
    }
  });
}

export function profile(overrides = {}) {
  return { role: 'CITIZEN', tier: 1, accountStatus: 'ACTIVE', ...overrides };
}

/** A valid new incident by [uid], matching the create allow-list. */
export function newIncident(uid, overrides = {}) {
  return {
    reporterUid: uid,
    category: 'Pothole',
    riskLevel: 'Medium',
    aiSummary: 'Pothole in the right lane.',
    recommendedAction: 'Patch the road.',
    note: 'big pothole',
    latitude: 10.3236,
    longitude: 123.9322,
    geohash: 'wdu3yz',
    photoBytes: 90000,
    reporterTier: 1,
    status: 'ACTIVE',
    visibility: 'PUBLIC',
    netVotes: 0,
    aiProcessed: true,
    ...overrides,
  };
}

/** Midnight of the current Philippine day (UTC+8), as the app writes it. */
export function phToday(offsetDays = 0) {
  const ph = new Date(Date.now() + 8 * 3600 * 1000);
  return Timestamp.fromDate(new Date(Date.UTC(ph.getUTCFullYear(), ph.getUTCMonth(), ph.getUTCDate() + offsetDays)));
}

/**
 * Files a report the way the app does: incident, photo, and the reporter's daily
 * counter in one batch. [count] is the new reportCount the client claims.
 */
export function fileReport(db, uid, id, { count = 1, day = phToday(), tier = 1, incident = {}, profileExtra = {} } = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, `incidents/${id}`), {
    ...newIncident(uid),
    reporterTier: tier,
    ...incident,
    createdAt: serverTimestamp(),
  });
  batch.set(doc(db, `incidents/${id}/photo/main`), {
    reporterUid: uid,
    mimeType: 'image/jpeg',
    imageBase64: 'abc',
    createdAt: serverTimestamp(),
  });
  batch.update(doc(db, `users/${uid}`), { reportDay: day, reportCount: count, lastReportId: id, ...profileExtra });
  return batch.commit();
}
