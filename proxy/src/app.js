import express from 'express';

import { buildChatMessages, parseChatResult, validateChatRequest } from './chat.js';
import { loopbackCors } from './cors.js';
import { findSafeRoute, toDetourResponse, validateDetourRequest } from './detour.js';
import { UpstreamError, ValidationError } from './errors.js';
import { requireFirebaseUser } from './idToken.js';
import { perUserRateLimit } from './rateLimit.js';
import { buildTriageMessages, parseTriageResult, validateNote } from './triage.js';

const JSON_BODY_LIMIT = '16kb';

/**
 * Builds the Express app. Dependencies are passed in so tests can supply fakes.
 *
 * @param {{
 *   config: { rateLimitPerMinute: number, detourPerMinute?: number },
 *   groq: { complete: Function },
 *   osrm?: { routes: Function },
 *   verifyIdToken: (token: string) => Promise<string>,
 *   log?: Function,
 * }} deps
 */
export function createApp({ config, groq, osrm, verifyIdToken, log = console.log }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(loopbackCors());

  // Logs method, path, status, and duration only. Bodies and headers are never logged.
  app.use((req, res, next) => {
    const started = performance.now();
    res.on('finish', () => {
      const ms = Math.round(performance.now() - started);
      log(`${req.method} ${req.path} ${res.statusCode} ${ms}ms`);
    });
    next();
  });

  // Health has no secrets, so it does not need a signed-in user.
  app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
  });

  // Authenticate and rate-limit before reading the body, so anonymous callers cost nothing.
  app.use(requireFirebaseUser(verifyIdToken));
  app.use(perUserRateLimit({ limit: config.rateLimitPerMinute }));
  app.use(express.json({ limit: JSON_BODY_LIMIT }));

  app.post('/triage', async (req, res) => {
    const note = validateNote(req.body?.note);
    const raw = await groq.complete({
      messages: buildTriageMessages(note),
      jsonMode: true,
      maxTokens: 1024,
    });
    res.json(parseTriageResult(raw));
  });

  app.post('/chat', async (req, res) => {
    const request = validateChatRequest(req.body);
    const raw = await groq.complete({
      messages: buildChatMessages(request),
      jsonMode: true,
      maxTokens: 1024,
    });
    res.json(parseChatResult(raw, request.incidents.map((incident) => incident.id)));
  });

  // Walking routes from the free public OSRM service, with a tighter per-user limit.
  if (osrm) {
    const detourLimit = perUserRateLimit({ limit: config.detourPerMinute ?? 6 });
    app.post('/detour', detourLimit, async (req, res) => {
      const { from, to, hazards } = validateDetourRequest(req.body);
      const choice = await findSafeRoute({ osrm, from, to, hazards });
      if (!choice) throw new UpstreamError('no walking route found', 502);
      res.json(toDetourResponse(choice, choice.alternatives));
    });
  }

  app.use((req, res) => {
    res.status(404).json({ error: 'not found' });
  });

  // Central error handler. Upstream and internal details stay out of responses.
  app.use((error, req, res, next) => {
    if (res.headersSent) {
      next(error);
      return;
    }
    if (error instanceof ValidationError || error instanceof UpstreamError) {
      res.status(error.status).json({ error: error.message });
      return;
    }
    if (error.type === 'entity.parse.failed') {
      res.status(400).json({ error: 'request body is not valid JSON' });
      return;
    }
    if (error.type === 'entity.too.large') {
      res.status(413).json({ error: 'request body is too large' });
      return;
    }
    log(`unhandled error: ${error.name}`);
    res.status(500).json({ error: 'internal error' });
  });

  return app;
}
