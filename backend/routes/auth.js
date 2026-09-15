const express  = require('express');
const { supabase, supabaseAdmin } = require('../utils/supabaseClient');
const { requireAuth, requireEmailVerified } = require('../middleware/auth');
const { logAuthEvent } = require('../services/auditLog');
const {
  isValidEmail,
  isValidOptionalPhone,
  isValidHttpUrl,
  isValidIsoDate,
  isValidBloodGroup,
  isNonEmptyString,
  hasMaxLength,
} = require('../middleware/validate');

// A single source of truth for acceptable passwords, shared by signup and
// password reset: at least 8 characters (max 128) with upper, lower, and a
// digit. Supabase Auth owns password storage; this rule only gates input.
const PASSWORD_RULE = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$/;
const PASSWORD_MESSAGE =
  'Password must be at least 8 characters with upper and lower case letters and a number.';

function isValidPassword(password) {
  return (
    typeof password === 'string' &&
    password.length <= 128 &&
    PASSWORD_RULE.test(password)
  );
}

function badRequest(res, message) {
  return res.status(400).json({ error: 'Validation Error', message });
}

// Factory so tests can substitute the Supabase clients and auth middleware
// without network access. Production wiring (server.js) uses the defaults.
function createAuthRouter(overrides = {}) {
  const client = overrides.supabase || supabase;
  const admin = overrides.supabaseAdmin || supabaseAdmin;
  const auth = overrides.auth || { requireAuth, requireEmailVerified };
  const logEvent = overrides.logAuthEvent || logAuthEvent;

  const router = express.Router();
  const { requireAuth: requireAuthMw, requireEmailVerified: requireEmailVerifiedMw } = auth;

  // POST /auth/signup
  router.post('/signup', async (req, res) => {
    const { email, password, full_name, phone_number } = req.body;

    if (!isValidEmail(email)) {
      return badRequest(res, 'A valid email address is required.');
    }
    if (!isValidPassword(password)) {
      return badRequest(res, PASSWORD_MESSAGE);
    }
    if (!isNonEmptyString(full_name) || !hasMaxLength(full_name, 100)) {
      return badRequest(res, 'full_name must be a string of at most 100 characters.');
    }
    if (!isValidOptionalPhone(phone_number)) {
      return badRequest(res, 'phone_number must be a valid phone number.');
    }

    const { data, error } = await client.auth.signUp({
      email: email.trim().toLowerCase(),
      password,
      options: { data: { full_name: full_name.trim(), phone_number } },
    });

    if (error) return res.status(400).json({ error: 'Sign Up Failed', message: error.message });

    await logEvent(data.user?.id, 'sign_up', req, { email: email.trim().toLowerCase() });

    return res.status(201).json({
      message: 'Account created! Please check your email to verify your account.',
      user: { id: data.user.id, email: data.user.email },
    });
  });

  // POST /auth/login
  router.post('/login', async (req, res) => {
    const { email, password } = req.body;

    if (!isValidEmail(email) || typeof password !== 'string' || password.length === 0 || !hasMaxLength(password, 128)) {
      return badRequest(res, 'A valid email and password are required.');
    }

    const { data, error } = await client.auth.signInWithPassword({ email: email.trim().toLowerCase(), password });

    if (error) {
      const isEmailNotConfirmed =
        error.message?.toLowerCase().includes('email not confirmed');
      if (isEmailNotConfirmed) {
        return res.status(403).json({
          error: 'Email Not Verified',
          message: 'Your email has not been verified yet. Please check your inbox for the verification link.',
        });
      }
      await logEvent(null, 'sign_in_failed', req, { email: email.trim().toLowerCase(), reason: error.message });
      return res.status(401).json({ error: 'Authentication Failed', message: 'Invalid email or password.' });
    }

    await logEvent(data.user.id, 'sign_in', req);

    return res.status(200).json({
      message: 'Login successful.',
      access_token:  data.session.access_token,
      refresh_token: data.session.refresh_token,
      expires_at:    data.session.expires_at,
      user: {
        id:    data.user.id,
        email: data.user.email,
        email_confirmed_at: data.user.email_confirmed_at,
      },
    });
  });

  // POST /auth/refresh
  router.post('/refresh', async (req, res) => {
    const { refresh_token } = req.body;
    if (!isNonEmptyString(refresh_token) || !hasMaxLength(refresh_token, 512)) {
      return badRequest(res, 'refresh_token is required.');
    }

    const { data, error } = await client.auth.refreshSession({ refresh_token });
    if (error) return res.status(401).json({ error: 'Token Refresh Failed', message: 'Please log in again.' });

    await logEvent(data.user.id, 'token_refresh', req);

    return res.status(200).json({
      access_token:  data.session.access_token,
      refresh_token: data.session.refresh_token,
      expires_at:    data.session.expires_at,
    });
  });

  // POST /auth/logout
  router.post('/logout', requireAuthMw, async (req, res) => {
    await admin.auth.admin.signOut(req.accessToken);
    await logEvent(req.user.id, 'sign_out', req);
    return res.status(200).json({ message: 'Logged out successfully.' });
  });

  // POST /auth/forgot-password
  router.post('/forgot-password', async (req, res) => {
    const { email } = req.body;
    if (!isValidEmail(email)) {
      return badRequest(res, 'A valid email address is required.');
    }

    await client.auth.resetPasswordForEmail(email.trim().toLowerCase(), {
      redirectTo: `${process.env.APP_URL}/reset-password`,
    });

    // Generic response: never reveal whether the address is registered.
    return res.status(200).json({ message: 'If an account exists with that email, a reset link has been sent.' });
  });

  // POST /auth/reset-password
  router.post('/reset-password', requireAuthMw, async (req, res) => {
    const { new_password } = req.body;
    if (!isValidPassword(new_password)) {
      return badRequest(res, PASSWORD_MESSAGE);
    }

    const { error } = await admin.auth.admin.updateUserById(req.user.id, { password: new_password });
    if (error) return res.status(400).json({ error: 'Reset Failed', message: 'Could not reset the password.' });

    await logEvent(req.user.id, 'password_changed', req);
    return res.status(200).json({ message: 'Password updated successfully.' });
  });

  // GET /auth/me
  router.get('/me', requireAuthMw, async (req, res) => {
    const { data: profile, error } = await admin
      .from('profiles')
      .select('id, full_name, email, phone_number, avatar_url, role, email_verified, created_at')
      .eq('id', req.user.id)
      .single();

    if (error) return res.status(404).json({ error: 'Not Found', message: 'Profile not found.' });
    return res.status(200).json({ profile });
  });

  // PATCH /auth/me
  router.patch('/me', requireAuthMw, requireEmailVerifiedMw, async (req, res) => {
    const ALLOWED = ['full_name', 'phone_number', 'avatar_url', 'date_of_birth', 'blood_group', 'medical_notes'];
    const updates = {};

    for (const field of ALLOWED) {
      const value = req.body[field];
      if (value === undefined) continue;

      if (field === 'full_name') {
        if (!isNonEmptyString(value) || !hasMaxLength(value, 100)) {
          return badRequest(res, 'full_name must be a string of at most 100 characters.');
        }
        updates[field] = value.trim();
      } else if (field === 'phone_number') {
        if (!isValidOptionalPhone(value)) {
          return badRequest(res, 'phone_number must be a valid phone number.');
        }
        updates[field] = value === null ? null : String(value).trim();
      } else if (field === 'avatar_url') {
        if (value !== null && !isValidHttpUrl(value)) {
          return badRequest(res, 'avatar_url must be a valid http(s) URL.');
        }
        updates[field] = value === null ? null : value;
      } else if (field === 'date_of_birth') {
        if (value !== null && !isValidIsoDate(value)) {
          return badRequest(res, 'date_of_birth must be a valid date (YYYY-MM-DD).');
        }
        updates[field] = value === null ? null : value;
      } else if (field === 'blood_group') {
        if (value !== null && !isValidBloodGroup(value)) {
          return badRequest(res, 'blood_group must be one of A+, A-, B+, B-, AB+, AB-, O+, O-, unknown.');
        }
        updates[field] = value === null ? null : value;
      } else if (field === 'medical_notes') {
        if (typeof value !== 'string' || value.length > 2000) {
          return badRequest(res, 'medical_notes must be a string of at most 2000 characters.');
        }
        updates[field] = value;
      }
    }

    if (Object.keys(updates).length === 0) {
      return badRequest(res, 'No valid fields provided.');
    }

    // Ownership is enforced by identity from the verified token. A body id /
    // user_id (if any) is never consulted — only req.user.id is used.
    const { data, error } = await admin
      .from('profiles')
      .update(updates)
      .eq('id', req.user.id)
      .select()
      .single();

    if (error) return res.status(400).json({ error: 'Update Failed', message: 'Could not update the profile.' });
    return res.status(200).json({ message: 'Profile updated.', profile: data });
  });

  return router;
}

module.exports = createAuthRouter;