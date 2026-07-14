const express  = require('express');
const router   = express.Router();
const { supabase, supabaseAdmin } = require('../utils/supabaseClient');
const { requireAuth, requireEmailVerified } = require('../middleware/auth');
const { logAuthEvent } = require('../services/auditLog');

// POST /auth/signup
router.post('/signup', async (req, res) => {
  const { email, password, full_name, phone_number } = req.body;

  if (!email || !password || !full_name) {
    return res.status(400).json({ error: 'Validation Error', message: 'email, password, and full_name are required.' });
  }
  if (password.length < 8) {
    return res.status(400).json({ error: 'Validation Error', message: 'Password must be at least 8 characters.' });
  }

  const { data, error } = await supabase.auth.signUp({
    email, password,
    options: { data: { full_name, phone_number } },
  });

  if (error) return res.status(400).json({ error: 'Sign Up Failed', message: error.message });

  await logAuthEvent(data.user?.id, 'sign_up', req, { email });

  return res.status(201).json({
    message: 'Account created! Please check your email to verify your account.',
    user: { id: data.user.id, email: data.user.email },
  });
});

// POST /auth/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Validation Error', message: 'email and password are required.' });
  }

  const { data, error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    await logAuthEvent(null, 'sign_in_failed', req, { email, reason: error.message });
    return res.status(401).json({ error: 'Authentication Failed', message: 'Invalid email or password.' });
  }

  await logAuthEvent(data.user.id, 'sign_in', req);

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
  if (!refresh_token) {
    return res.status(400).json({ error: 'Validation Error', message: 'refresh_token is required.' });
  }

  const { data, error } = await supabase.auth.refreshSession({ refresh_token });
  if (error) return res.status(401).json({ error: 'Token Refresh Failed', message: 'Please log in again.' });

  await logAuthEvent(data.user.id, 'token_refresh', req);

  return res.status(200).json({
    access_token:  data.session.access_token,
    refresh_token: data.session.refresh_token,
    expires_at:    data.session.expires_at,
  });
});

// POST /auth/logout
router.post('/logout', requireAuth, async (req, res) => {
  await supabaseAdmin.auth.admin.signOut(req.accessToken);
  await logAuthEvent(req.user.id, 'sign_out', req);
  return res.status(200).json({ message: 'Logged out successfully.' });
});

// POST /auth/forgot-password
router.post('/forgot-password', async (req, res) => {
  const { email } = req.body;
  if (!email) return res.status(400).json({ error: 'Validation Error', message: 'email is required.' });

  await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${process.env.APP_URL}/reset-password`,
  });

  return res.status(200).json({ message: 'If an account exists with that email, a reset link has been sent.' });
});

// POST /auth/reset-password
router.post('/reset-password', requireAuth, async (req, res) => {
  const { new_password } = req.body;
  if (!new_password || new_password.length < 8) {
    return res.status(400).json({ error: 'Validation Error', message: 'new_password must be at least 8 characters.' });
  }

  const { error } = await supabaseAdmin.auth.admin.updateUserById(req.user.id, { password: new_password });
  if (error) return res.status(400).json({ error: 'Reset Failed', message: error.message });

  await logAuthEvent(req.user.id, 'password_changed', req);
  return res.status(200).json({ message: 'Password updated successfully.' });
});

// GET /auth/me
router.get('/me', requireAuth, async (req, res) => {
  const { data: profile, error } = await supabaseAdmin
    .from('profiles')
    .select('id, full_name, email, phone_number, avatar_url, role, email_verified, created_at')
    .eq('id', req.user.id)
    .single();

  if (error) return res.status(404).json({ error: 'Not Found', message: 'Profile not found.' });
  return res.status(200).json({ profile });
});

// PATCH /auth/me
router.patch('/me', requireAuth, requireEmailVerified, async (req, res) => {
  const ALLOWED = ['full_name', 'phone_number', 'avatar_url', 'date_of_birth', 'blood_group', 'medical_notes'];
  const updates = {};
  for (const field of ALLOWED) {
    if (req.body[field] !== undefined) updates[field] = req.body[field];
  }

  if (Object.keys(updates).length === 0) {
    return res.status(400).json({ error: 'Validation Error', message: 'No valid fields provided.' });
  }

  const { data, error } = await supabaseAdmin
    .from('profiles').update(updates).eq('id', req.user.id).select().single();

  if (error) return res.status(400).json({ error: 'Update Failed', message: error.message });
  return res.status(200).json({ message: 'Profile updated.', profile: data });
});

module.exports = router;