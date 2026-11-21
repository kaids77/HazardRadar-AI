import path from 'node:path';
import { fileURLToPath } from 'node:url';

import dotenv from 'dotenv';

import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { createGroqClient } from './groqClient.js';
import { createOsrmClient } from './detour.js';
import { createIdTokenVerifier } from './idToken.js';

// .env lives at the Flutter project root, one level above proxy/.
const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
dotenv.config({ path: path.join(projectRoot, '.env'), quiet: true });

const config = loadConfig(process.env);

const groq = createGroqClient({
  apiKey: config.groqApiKey,
  model: config.groqModel,
  timeoutMs: config.groqTimeoutMs,
});

const verifyIdToken = createIdTokenVerifier({ projectId: config.firebaseProjectId });
const osrm = createOsrmClient({ baseUrl: config.osrmBaseUrl });

const app = createApp({ config, groq, osrm, verifyIdToken });

// Bound to loopback only. adb reverse, the Android emulator alias, and Chrome all reach this address.
const server = app.listen(config.port, '127.0.0.1', () => {
  console.log(`HazardRadar proxy listening on http://127.0.0.1:${config.port}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
