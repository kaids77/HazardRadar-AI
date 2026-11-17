import assert from 'node:assert/strict';
import { test } from 'node:test';

import { parseTriageResult, validateNote } from '../src/triage.js';
import { ValidationError } from '../src/errors.js';

const VALID_JSON = JSON.stringify({
  category: 'Electrical',
  riskLevel: 'High',
  aiSummary: 'Exposed sparking wire near the walkway.',
  recommendedAction: 'Dispatch an electrical crew to isolate the line.',
});

test('parses a valid triage result', () => {
  const result = parseTriageResult(VALID_JSON);

  assert.deepEqual(result, {
    category: 'Electrical',
    riskLevel: 'High',
    aiSummary: 'Exposed sparking wire near the walkway.',
    recommendedAction: 'Dispatch an electrical crew to isolate the line.',
  });
});

test('rejects output that is not JSON', () => {
  assert.throws(() => parseTriageResult('not json'), ValidationError);
});

test('rejects a risk level outside the allowed values', () => {
  const bad = JSON.parse(VALID_JSON);
  bad.riskLevel = 'Critical';
  assert.throws(() => parseTriageResult(JSON.stringify(bad)), /riskLevel/);
});

test('rejects a missing summary', () => {
  const bad = JSON.parse(VALID_JSON);
  delete bad.aiSummary;
  assert.throws(() => parseTriageResult(JSON.stringify(bad)), /aiSummary/);
});

test('rejects a JSON array instead of an object', () => {
  assert.throws(() => parseTriageResult('[]'), /not a JSON object/);
});

test('validateNote trims and rejects empty or oversized notes', () => {
  assert.equal(validateNote('  wire down  '), 'wire down');
  assert.throws(() => validateNote('   '), /must not be empty/);
  assert.throws(() => validateNote('x'.repeat(501)), /at most 500/);
  assert.throws(() => validateNote(42), /must be a string/);
});
