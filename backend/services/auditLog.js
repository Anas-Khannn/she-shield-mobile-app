const { supabaseAdmin } = require('../utils/supabaseClient');

async function logAuthEvent(userId, event, req, metadata = {}) {
  try {
    await supabaseAdmin.from('auth_audit_log').insert({
      user_id:    userId,
      event,
      ip_address: req.ip || req.headers['x-forwarded-for'] || null,
      user_agent: req.headers['user-agent'] || null,
      metadata,
    });
  } catch (err) {
    console.warn('[AuditLog] Error:', err.message);
  }
}

module.exports = { logAuthEvent };