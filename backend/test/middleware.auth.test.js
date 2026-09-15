const { test } = require('node:test');
const assert = require('node:assert');

process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fake-anon-key-for-tests';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-service-role-key-for-tests';
process.env.ALLOWED_ORIGINS = '*';
process.env.APP_URL = 'http://localhost:3000';

const { makeRequireAuth } = require('../middleware/auth');

const user = { id: 'user-1', email: 'a@example.com', email_confirmed_at: '2025-01-01T00:00:00.000Z' };
const profile = { id: 'user-1', role: 'user', is_banned: false, email_verified: true };

function mockRes() {
  const res = {};
  res.status = (code) => {
    res.statusCode = code;
    return res;
  };
  res.json = (body) => {
    res.body = body;
    return res;
  };
  return res;
}

test('requireAuth: 401 when no Authorization header', async () => {
  const requireAuth = makeRequireAuth({ verifyAccessToken: async () => user });
  const res = mockRes();
  await requireAuth({ headers: {} }, res, () => { throw new Error('next called'); });
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.message, 'Missing token.');
});

test('requireAuth: 401 for non-Bearer header', async () => {
  const requireAuth = makeRequireAuth({ verifyAccessToken: async () => user });
  const res = mockRes();
  await requireAuth({ headers: { authorization: 'Basic abc' } }, res, () => { throw new Error('next called'); });
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.message, 'Missing token.');
});

test('requireAuth: 401 when the token is invalid or rejected', async () => {
  const requireAuth = makeRequireAuth({ verifyAccessToken: async () => null });
  const res = mockRes();
  await requireAuth({ headers: { authorization: 'Bearer bad-token' } }, res, () => { throw new Error('next called'); });
  assert.equal(res.statusCode, 401);
  assert.equal(res.body.message, 'Invalid or expired token.');
});

test('requireAuth: 403 when the profile is banned', async () => {
  const requireAuth = makeRequireAuth({
    verifyAccessToken: async () => user,
    fetchProfile: async () => ({ ...profile, is_banned: true, banned_reason: 'violation' }),
  });
  const res = mockRes();
  await requireAuth({ headers: { authorization: 'Bearer ok-token' } }, res, () => { throw new Error('next called'); });
  assert.equal(res.statusCode, 403);
  assert.ok(res.body.message.includes('violation'));
});

test('requireAuth: populates req.user/profile and calls next on success', async () => {
  const requireAuth = makeRequireAuth({
    verifyAccessToken: async () => user,
    fetchProfile: async () => profile,
  });
  const req = { headers: { authorization: 'Bearer ok-token' } };
  const res = mockRes();
  let calledNext = false;
  await requireAuth(req, res, () => { calledNext = true; });
  assert.equal(calledNext, true);
  assert.equal(req.user.id, 'user-1');
  assert.equal(req.profile.role, 'user');
  assert.equal(req.accessToken, 'ok-token');
});