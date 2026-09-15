const { supabaseAdmin } = require('../utils/supabaseClient');

// The identity of the caller ALWAYS comes from the verified Supabase JWT that
// the client presents — never from a user id supplied in the request body or
// URL. `makeRequireAuth` exists purely so tests can substitute the JWT lookup
// and profile fetch without network access; production wiring is unchanged.

function makeRequireAuth({ verifyAccessToken, fetchProfile } = {}) {
  const verify = verifyAccessToken || (async (token) => {
    const { data, error } = await supabaseAdmin.auth.getUser(token);
    if (error || !data?.user) return null;
    return data.user;
  });

  const loadProfile = fetchProfile || (async (userId) => {
    const { data } = await supabaseAdmin
      .from('profiles')
      .select('id, role, is_banned, banned_reason, email_verified')
      .eq('id', userId)
      .single();
    return data || null;
  });

  return async function requireAuth(req, res, next) {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Unauthorized', message: 'Missing token.' });
    }

    const accessToken = authHeader.split(' ')[1];
    const user = await verify(accessToken);

    if (!user) {
      return res.status(401).json({ error: 'Unauthorized', message: 'Invalid or expired token.' });
    }

    const profile = await loadProfile(user.id);

    if (profile?.is_banned) {
      return res.status(403).json({ error: 'Forbidden', message: `Account suspended: ${profile.banned_reason}` });
    }

    req.user        = user;
    req.profile     = profile;
    req.accessToken = accessToken;
    next();
  };
}

const requireAuth = makeRequireAuth();

function requireEmailVerified(req, res, next) {
  if (!req.user.email_confirmed_at) {
    return res.status(403).json({ error: 'Email Not Verified', message: 'Please verify your email first.' });
  }
  next();
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!roles.includes(req.profile?.role)) {
      return res.status(403).json({ error: 'Forbidden', message: `Requires role: ${roles.join(', ')}` });
    }
    next();
  };
}

module.exports = { requireAuth, requireEmailVerified, requireRole, makeRequireAuth };