import { createRemoteJWKSet, jwtVerify } from 'jose';

// Google's public keys for Firebase Auth ID tokens. No service account is needed.
const FIREBASE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

/**
 * Builds a function that verifies a Firebase ID token and returns its uid.
 * Signature, issuer, audience, and expiry are all checked by jose.
 *
 * @param {{ projectId: string, jwks?: Function }} options jwks is injectable for tests.
 */
export function createIdTokenVerifier({ projectId, jwks = createRemoteJWKSet(new URL(FIREBASE_JWKS_URL)) }) {
  const issuer = `https://securetoken.google.com/${projectId}`;

  return async function verifyIdToken(token) {
    const { payload } = await jwtVerify(token, jwks, {
      issuer,
      audience: projectId,
      algorithms: ['RS256'],
    });
    if (typeof payload.sub !== 'string' || payload.sub.length === 0 || payload.sub.length > 128) {
      throw new Error('token has no valid subject');
    }
    return payload.sub;
  };
}

/**
 * Express middleware: requires `Authorization: Bearer <Firebase ID token>` and sets req.uid.
 * Failure reasons are never sent to the client.
 */
export function requireFirebaseUser(verifyIdToken) {
  return async (req, res, next) => {
    const header = req.get('authorization') ?? '';
    const match = /^Bearer ([A-Za-z0-9._-]{20,4096})$/.exec(header);
    if (!match) {
      res.status(401).json({ error: 'unauthorized' });
      return;
    }
    try {
      req.uid = await verifyIdToken(match[1]);
      next();
    } catch {
      res.status(401).json({ error: 'unauthorized' });
    }
  };
}
