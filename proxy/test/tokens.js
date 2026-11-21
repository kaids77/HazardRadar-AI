import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';

import { createIdTokenVerifier } from '../src/idToken.js';

export const PROJECT_ID = 'hazardradarai';

/**
 * A local key pair that stands in for Google's signing keys, so tests can mint
 * real Firebase-style ID tokens and verify them with the production verifier.
 */
export async function createTestTokens() {
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const jwk = { ...(await exportJWK(publicKey)), kid: 'test-key', alg: 'RS256' };
  const verifyIdToken = createIdTokenVerifier({
    projectId: PROJECT_ID,
    jwks: createLocalJWKSet({ keys: [jwk] }),
  });

  async function sign(uid, { issuer, audience, expiresIn = '1h', key = privateKey } = {}) {
    return new SignJWT({})
      .setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
      .setSubject(uid)
      .setIssuer(issuer ?? `https://securetoken.google.com/${PROJECT_ID}`)
      .setAudience(audience ?? PROJECT_ID)
      .setIssuedAt()
      .setExpirationTime(expiresIn)
      .sign(key);
  }

  return { verifyIdToken, sign };
}
