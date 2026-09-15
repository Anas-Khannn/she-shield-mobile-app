// Resolves the CORS origin allowlist from process environment.
//
// The mobile app authenticates with a Bearer token (not cookies) and is not a
// browser client, so CORS only matters for web/other browser clients. Browser
// origins must be explicitly allowlisted; anything else fails closed.
//
// Behaviour:
//   - ALLOWED_ORIGINS set  → comma-separated list, trimmed, empties dropped.
//     "*" is preserved for the explicit dev/test cases that request it.
//   - ALLOWED_ORIGINS unset:
//       - production  → []  (no browser origin allowed; native app unaffected)
//       - else        → "*" (local development convenience)

const DEFAULT_DEV_ORIGINS = '*';

function resolveAllowedOrigins(env = process.env) {
  const raw = env.ALLOWED_ORIGINS;
  if (raw !== undefined && raw !== null && String(raw).trim() !== '') {
    return String(raw)
      .split(',')
      .map((origin) => origin.trim())
      .filter((origin) => origin.length > 0);
  }
  if (env.NODE_ENV === 'production') {
    return [];
  }
  return [DEFAULT_DEV_ORIGINS];
}

module.exports = { resolveAllowedOrigins, DEFAULT_DEV_ORIGINS };