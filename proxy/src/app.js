import express from 'express';

import { requireProxyToken } from './auth.js';
import { buildChatMessages, parseChatResult, validateChatRequest } from './chat.js';
import { loopbackCors } from './cors.js';
import { UpstreamError, ValidationError } from './errors.js';
import { buildTriageMessages, parseTriageResult, validateNote } from './triage.js';

const JSON_BODY_LIMIT = '16kb';

/**
 * Builds the Express app. Dependencies are passed in so tests can supply a fake Groq client.
 *
 * @param {{ config: { proxyToken: string }, groq: { complete: Function }, log?: Function }} deps
 */
export function createApp({ config, groq, log = console.log }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(loopbackCors());
  app.use(express.json({ limit: JSON_BODY_LIMIT }));

  // Logs method, path, status, and duration only. Bodies and headers are never logged.
  app.use((req, res, next) => {
    const started = performance.now();
    res.on('finish', () => {
      const ms = Math.round(performance.now() - started);
      log(`${req.method} ${req.path} ${res.statusCode} ${ms}ms`);
    });
    next();
  });

  // Health has no secrets, so it does not need the token.
  app.get('/health', (req, res) => {
    res.json({ status: 'ok' });
  });

  app.use(requireProxyToken(config.proxyToken));

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
