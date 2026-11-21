/**
 * Fixed-window, in-memory rate limit per signed-in user (req.uid).
 * The proxy runs as a single local process, so memory is enough.
 *
 * @param {{ limit: number, windowMs?: number, now?: () => number }} options
 */
export function perUserRateLimit({ limit, windowMs = 60_000, now = Date.now }) {
  const windows = new Map();

  return (req, res, next) => {
    const key = req.uid;
    const time = now();
    let entry = windows.get(key);
    if (!entry || time - entry.start >= windowMs) {
      entry = { start: time, count: 0 };
      windows.set(key, entry);
    }
    entry.count += 1;

    // Drop stale windows so the map cannot grow without bound.
    if (windows.size > 10_000) {
      for (const [uid, value] of windows) {
        if (time - value.start >= windowMs) windows.delete(uid);
      }
    }

    if (entry.count > limit) {
      res.set('Retry-After', String(Math.ceil((entry.start + windowMs - time) / 1000)));
      res.status(429).json({ error: 'too many requests' });
      return;
    }
    next();
  };
}
