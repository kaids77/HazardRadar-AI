import assert from 'node:assert/strict';
import { test } from 'node:test';

import { loadConfig } from '../src/config.js';

test('loads defaults when optional values are absent', () => {
  const config = loadConfig({ GROQ_API_KEY: 'gsk_test' });

  assert.equal(config.port, 3000);
  assert.equal(config.groqModel, 'openai/gpt-oss-120b');
  assert.equal(config.groqTimeoutMs, 8000);
  assert.equal(config.firebaseProjectId, 'hazardradarai');
  assert.equal(config.rateLimitPerMinute, 30);
});

test('error names the missing variable but never prints a value', () => {
  assert.throws(
    () => loadConfig({ FIREBASE_PROJECT_ID: 'hazardradarai' }),
    (error) => {
      assert.match(error.message, /GROQ_API_KEY/);
      return true;
    },
  );
});

test('rejects an invalid project id', () => {
  assert.throws(
    () => loadConfig({ GROQ_API_KEY: 'gsk_test', FIREBASE_PROJECT_ID: 'Bad Project!' }),
    /FIREBASE_PROJECT_ID/,
  );
});

test('rejects a non-numeric port or rate limit', () => {
  assert.throws(() => loadConfig({ GROQ_API_KEY: 'gsk_test', PORT: 'abc' }), /PORT must be a positive integer/);
  assert.throws(
    () => loadConfig({ GROQ_API_KEY: 'gsk_test', RATE_LIMIT_PER_MINUTE: '0' }),
    /RATE_LIMIT_PER_MINUTE/,
  );
});
