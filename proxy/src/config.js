const DEFAULT_MODEL = 'openai/gpt-oss-120b';
const MIN_TOKEN_LENGTH = 32;

/**
 * Reads and validates proxy settings from an environment object.
 * Error messages name the missing variable but never print a value.
 *
 * @param {Record<string, string | undefined>} env
 */
export function loadConfig(env) {
  const missing = [];

  const groqApiKey = env.GROQ_API_KEY?.trim();
  if (!groqApiKey) missing.push('GROQ_API_KEY');

  const proxyToken = env.PROXY_TOKEN?.trim();
  if (!proxyToken) {
    missing.push('PROXY_TOKEN');
  } else if (proxyToken.length < MIN_TOKEN_LENGTH) {
    throw new Error(`PROXY_TOKEN must be at least ${MIN_TOKEN_LENGTH} characters`);
  }

  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }

  const port = parseInteger(env.PORT, 3000, 'PORT');
  const groqTimeoutMs = parseInteger(env.GROQ_TIMEOUT_MS, 8000, 'GROQ_TIMEOUT_MS');

  return Object.freeze({
    groqApiKey,
    groqModel: env.GROQ_MODEL?.trim() || DEFAULT_MODEL,
    groqTimeoutMs,
    proxyToken,
    port,
  });
}

function parseInteger(raw, fallback, name) {
  if (raw === undefined || raw.trim() === '') return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}
