import assert from 'node:assert/strict';
import { before, test } from 'node:test';

import { generateKeyPair } from 'jose';

import { createTestTokens } from './tokens.js';

let tokens;

before(async () => {
  tokens = await createTestTokens();
});

test('a valid token returns its uid', async () => {
  assert.equal(await tokens.verifyIdToken(await tokens.sign('alice')), 'alice');
});

test('expired, wrong-issuer, and wrong-audience tokens are rejected', async () => {
  const past = Math.floor(Date.now() / 1000) - 60;
  await assert.rejects(tokens.verifyIdToken(await tokens.sign('alice', { expiresIn: past })));
  await assert.rejects(
    tokens.verifyIdToken(await tokens.sign('alice', { issuer: 'https://securetoken.google.com/other' })),
  );
  await assert.rejects(tokens.verifyIdToken(await tokens.sign('alice', { audience: 'other' })));
});

test('a token signed by another key is rejected', async () => {
  const { privateKey } = await generateKeyPair('RS256');
  await assert.rejects(tokens.verifyIdToken(await tokens.sign('alice', { key: privateKey })));
});

test('garbage is rejected', async () => {
  await assert.rejects(tokens.verifyIdToken('not.a.token'));
});
