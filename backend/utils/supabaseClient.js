require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

function requireEnv(name) {
  const value = process.env[name];
  if (!value || value.trim() === '' || value.trim().startsWith('your_')) {
    throw new Error(
      `SheShield backend misconfigured: missing required environment variable "${name}".`
    );
  }
  return value.trim();
}

function requireHttpsUrl(raw, label) {
  let parsed;
  try {
    parsed = new URL(raw);
  } catch (_) {
    parsed = null;
  }
  if (!parsed || parsed.protocol !== 'https:') {
    throw new Error(
      `SheShield backend misconfigured: "${label}" must be a valid HTTPS URL (got "${raw}").`
    );
  }
  return raw;
}

const SUPABASE_URL = requireHttpsUrl(requireEnv('SUPABASE_URL'), 'SUPABASE_URL');

const supabase = createClient(SUPABASE_URL, requireEnv('SUPABASE_ANON_KEY'));

const supabaseAdmin = createClient(
  SUPABASE_URL,
  requireEnv('SUPABASE_SERVICE_ROLE_KEY'),
  { auth: { autoRefreshToken: false, persistSession: false } }
);

module.exports = { supabase, supabaseAdmin };