import { createHash, timingSafeEqual } from 'node:crypto';

const TOKEN_HEADER = 'x-proxy-token';

/**
 * Rejects requests that do not carry the shared proxy token.
 * Both values are hashed first so the comparison runs in constant time
 * and the buffers always have equal length.
 *
 * @param {string} expectedToken
 */
export function requireProxyToken(expectedToken) {
  const expectedDigest = sha256(expectedToken);

  return (req, res, next) => {
    const provided = req.get(TOKEN_HEADER) ?? '';
    if (timingSafeEqual(expectedDigest, sha256(provided))) {
      next();
      return;
    }
    res.status(401).json({ error: 'unauthorized' });
  };
}

function sha256(value) {
  return createHash('sha256').update(value, 'utf8').digest();
}
