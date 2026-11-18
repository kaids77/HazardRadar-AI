import assert from 'node:assert/strict';
import { test } from 'node:test';

import { perUserRateLimit } from '../src/rateLimit.js';

function run(limiter, uid) {
  let status = 200;
  const res = {
    set() {},
    status(code) {
      status = code;
      return this;
    },
    json() {},
  };
  let passed = false;
  limiter({ uid }, res, () => {
    passed = true;
  });
  return passed ? 200 : status;
}

test('allows up to the limit per user, then returns 429 until the window resets', () => {
  let now = 0;
  const limiter = perUserRateLimit({ limit: 2, windowMs: 1000, now: () => now });

  assert.equal(run(limiter, 'a'), 200);
  assert.equal(run(limiter, 'a'), 200);
  assert.equal(run(limiter, 'a'), 429);
  assert.equal(run(limiter, 'b'), 200);

  now = 1000;
  assert.equal(run(limiter, 'a'), 200);
});
