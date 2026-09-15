const { supabaseAdmin } = require('../utils/supabaseClient');

// Keys that must never reach the audit log regardless of what callers pass in.
const SENSITIVE_KEY_RULE = /password|token|secret|authorization|cookie|session/i;
const MAX_STRING_LENGTH = 500;

// Recursively copies `obj`, dropping any key that could carry credentials and
// truncating oversized strings. Audit metadata should contain safe context
// (event, user id, email, reason) — never secrets.
function sanitizeMetadata(value, depth = 0) {
  if (value === null || value === undefined || typeof value === 'boolean' || typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string') {
    return value.length > MAX_STRING_LENGTH
      ? `${value.slice(0, MAX_STRING_LENGTH)}…`
      : value;
  }
  if (typeof value !== 'object' || depth > 4) {
    return undefined; // Unsupported value — omit it.
  }

  if (Array.isArray(value)) {
    return value
      .map((item) => sanitizeMetadata(item, depth + 1))
      .filter((item) => item !== undefined);
  }

  const out = {};
  for (const [key, item] of Object.entries(value)) {
    if (SENSITIVE_KEY_RULE.test(key)) continue;
    const sanitized = sanitizeMetadata(item, depth + 1);
    if (sanitized !== undefined) out[key] = sanitized;
  }
  return out;
}

async function logAuthEvent(userId, event, req, metadata = {}) {
  try {
    await supabaseAdmin.from('auth_audit_log').insert({
      user_id:    userId,
      event,
      ip_address: req.ip || req.headers['x-forwarded-for'] || null,
      user_agent: req.headers['user-agent'] || null,
      // Defense in depth: strip any credential-shaped keys before persistence,
      // so a future call site cannot accidentally log secrets.
      metadata: sanitizeMetadata(metadata),
    });
  } catch (err) {
    // Logging must never take down the request path.
    console.warn('[AuditLog] Error:', err.message);
  }
}

module.exports = { logAuthEvent, sanitizeMetadata };