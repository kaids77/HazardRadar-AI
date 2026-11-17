import assert from 'node:assert/strict';
import { test } from 'node:test';

import { loadConfig } from '../src/config.js';

const VALID_TOKEN = 'a'.repeat(32);

test('loads defaults when optional values are absent', () => {
  const config = loadConfig({ GROQ_API_KEY: 'gsk_test', PROXY_TOKEN: VALID_TOKEN });

  assert.equal(config.port, 3000);
  assert.equal(config.groqModel, 'openai/gpt-oss-120b');
  assert.equal(config.groqTimeoutMs, 8000);
});

test('error names the missing variable but never prints a value', () => {
  assert.throws(
    () => loadConfig({ PROXY_TOKEN: VALID_TOKEN }),
    (error) => {
      assert.match(error.message, /GROQ_API_KEY/);
      assert.doesNotMatch(error.message, /a{32}/);
      return true;
    },
  );
});

test('rejects a proxy token shorter than 32 characters', () => {
  assert.throws(
    () => loadConfig({ GROQ_API_KEY: 'gsk_test', PROXY_TOKEN: 'short' }),
    /at least 32 characters/,
  );
});

test('rejects a non-numeric port', () => {
  assert.throws(
    () => loadConfig({ GROQ_API_KEY: 'gsk_test', PROXY_TOKEN: VALID_TOKEN, PORT: 'abc' }),
    /PORT must be a positive integer/,
  );
});
