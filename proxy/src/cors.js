// Browsers send a CORS preflight before the app's POST because of the x-proxy-token
// header. The proxy listens on loopback only, so it accepts only pages served from this
// machine (the Flutter web dev server). Any other site gets no CORS headers, and the
// browser blocks its request.
const LOOPBACK_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d{1,5})?$/;

export function isAllowedOrigin(origin) {
  return typeof origin === 'string' && LOOPBACK_ORIGIN.test(origin);
}

/** Adds CORS headers for loopback origins and answers preflights before token auth runs. */
export function loopbackCors() {
  return (req, res, next) => {
    const origin = req.get('origin');
    if (origin !== undefined) res.vary('Origin');

    if (isAllowedOrigin(origin)) {
      res.set('Access-Control-Allow-Origin', origin);
      if (req.method === 'OPTIONS') {
        res.set('Access-Control-Allow-Methods', 'GET, POST');
        res.set('Access-Control-Allow-Headers', 'content-type, x-proxy-token');
        res.set('Access-Control-Max-Age', '600');
        res.status(204).end();
        return;
      }
    }
    next();
  };
}
