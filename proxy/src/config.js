const DEFAULT_MODEL = 'openai/gpt-oss-120b';
const DEFAULT_PROJECT_ID = 'hazardradarai';
const PROJECT_ID_PATTERN = /^[a-z][a-z0-9-]{4,29}$/;

/**
 * Reads and validates proxy settings from an environment object.
 * Error messages name the missing variable but never print a value.
 *
 * @param {Record<string, string | undefined>} env
 */
export function loadConfig(env) {
  const groqApiKey = env.GROQ_API_KEY?.trim();
  if (!groqApiKey) {
    throw new Error('Missing required environment variables: GROQ_API_KEY');
  }

  const firebaseProjectId = env.FIREBASE_PROJECT_ID?.trim() || DEFAULT_PROJECT_ID;
  if (!PROJECT_ID_PATTERN.test(firebaseProjectId)) {
    throw new Error('FIREBASE_PROJECT_ID is not a valid Firebase project id');
  }

  return Object.freeze({
    groqApiKey,
    groqModel: env.GROQ_MODEL?.trim() || DEFAULT_MODEL,
    groqTimeoutMs: parseInteger(env.GROQ_TIMEOUT_MS, 8000, 'GROQ_TIMEOUT_MS'),
    firebaseProjectId,
    rateLimitPerMinute: parseInteger(env.RATE_LIMIT_PER_MINUTE, 30, 'RATE_LIMIT_PER_MINUTE'),
    port: parseInteger(env.PORT, 3000, 'PORT'),
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
