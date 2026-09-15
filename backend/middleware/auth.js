const { supabaseAdmin } = require('../utils/supabaseClient');

async function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorized', message: 'Missing token.' });
  }

  const accessToken = authHeader.split(' ')[1];
  const { data: { user }, error } = await supabaseAdmin.auth.getUser(accessToken);

  if (error || !user) {
    return res.status(401).json({ error: 'Unauthorized', message: 'Invalid or expired token.' });
  }

  const { data: profile } = await supabaseAdmin
    .from('profiles')
    .select('id, role, is_banned, banned_reason, email_verified')
    .eq('id', user.id)
    .single();

  if (profile?.is_banned) {
    return res.status(403).json({ error: 'Forbidden', message: `Account suspended: ${profile.banned_reason}` });
  }

  req.user        = user;
  req.profile     = profile;
  req.accessToken = accessToken;
  next();
}

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

module.exports = { requireAuth, requireEmailVerified, requireRole };