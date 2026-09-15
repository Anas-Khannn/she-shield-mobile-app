const { test, before, after } = require('node:test');
const assert = require('node:assert');
const express = require('express');

process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fake-anon-key-for-tests';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-service-role-key-for-tests';
process.env.ALLOWED_ORIGINS = '*';
process.env.APP_URL = 'http://localhost:3000';

const createAuthRouter = require('../routes/auth');

// ---- Fakes ---------------------------------------------------------------

const USER = {
  id: 'user-1',
  email: 'a@example.com',
  email_confirmed_at: '2025-01-01T00:00:00.000Z',
};

const PROFILE = {
  id: 'user-1',
  full_name: 'Ana',
  email: 'a@example.com',
  phone_number: null,
  avatar_url: null,
  role: 'user',
  email_verified: true,
  created_at: '2025-01-01T00:00:00.000Z',
};

const SESSION = {
  access_token: 'at-123',
  refresh_token: 'rt-123',
  expires_at: 9999999999,
};

const supabaseCalls = [];
const adminCalls = [];
const eventLog = [];

function fakeSupabase() {
  return {
    auth: {
      async signUp({ email, password, options }) {
        supabaseCalls.push({ method: 'signUp', email, password, options });
        return { data: { user: { id: 'new-user', email } }, error: null };
      },
      async signInWithPassword({ email, password }) {
        supabaseCalls.push({ method: 'signInWithPassword', email, password });
        return { data: { user: USER, session: SESSION }, error: null };
      },
      async refreshSession({ refresh_token }) {
        supabaseCalls.push({ method: 'refreshSession', refresh_token });
        return { data: { user: USER, session: SESSION }, error: null };
      },
      async resetPasswordForEmail(email) {
        supabaseCalls.push({ method: 'resetPasswordForEmail', email });
        return { data: {}, error: null };
      },
    },
  };
}

function fakeAdmin({ failUpdate = false } = {}) {
  const service = {
    from() {
      const builder = {
        select(cols) { this.columns = cols; return this; },
        update(obj) { this.updates = obj; return this; },
        eq(k, v) { this.where = this.where || {}; this.where[k] = v; return this; },
        async single() {
          adminCalls.push({ where: this.where, updates: this.updates, columns: this.columns });
          if (this.updates) {
            return failUpdate
              ? { data: null, error: { message: 'permission denied' } }
              : { data: { ...this.updates, id: this.where.id }, error: null };
          }
          return { data: { ...PROFILE }, error: null };
        },
      };
      return builder;
    },
  };
  service.auth = {
    admin: {
      async signOut() { adminCalls.push({ method: 'signOut' }); return { error: null }; },
      async updateUserById() { adminCalls.push({ method: 'updateUserById' }); return { error: null }; },
    },
  };
  return service;
}

function fakeAuth(state = { user: USER, profile: PROFILE }) {
  return {
    requireAuth: async (req, res, next) => {
      if (state.deny) return res.status(401).json({ error: 'Unauthorized', message: 'denied' });
      req.user = state.user;
      req.profile = state.profile;
      req.accessToken = 'at-123';
      next();
    },
    requireEmailVerified: async (req, res, next) => {
      if (!req.user.email_confirmed_at) {
        return res.status(403).json({ error: 'Email Not Verified', message: 'nope' });
      }
      next();
    },
  };
}

const logEvent = async (userId, event, _req, metadata = {}) => {
  eventLog.push({ userId, event, metadata });
};

function buildRouter(opts = {}) {
  const supabase = opts.supabase || fakeSupabase();
  const admin = opts.admin || fakeAdmin();
  const auth = opts.auth || fakeAuth();
  return createAuthRouter({ supabase, supabaseAdmin: admin, auth, logAuthEvent: logEvent });
}

// ---- Live HTTP harness (mirrors server.js mounting + body parsing) --------

let currentRouter;
let server;
let baseUrl;

before(async () => {
  const app = express();
  app.use(express.json());
  app.use('/auth', (req, res, next) => currentRouter(req, res, next));
  server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.close();
});

async function call(path, { method = 'GET', body } = {}) {
  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { code: res.status, body: await res.json() };
}

// ---- Tests ---------------------------------------------------------------

test('signup: rejects an invalid email with 400', async () => {
  currentRouter = buildRouter();
  const { code, body } = await call('/auth/signup', { method: 'POST', body: { email: 'not-an-email', password: 'Abcdefg1', full_name: 'Ana' } });
  assert.equal(code, 400);
  assert.equal(body.error, 'Validation Error');
  assert.ok(body.message.includes('email'));
});

test('signup: rejects an invalid password with 400', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/signup', { method: 'POST', body: { email: 'a@example.com', password: 'short', full_name: 'Ana' } });
  assert.equal(code, 400);
});

test('signup: rejects an invalid phone number with 400', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/signup', { method: 'POST', body: { email: 'a@example.com', password: 'Abcdefg1', full_name: 'Ana', phone_number: '<script>' } });
  assert.equal(code, 400);
});

test('signup: full_name over 100 chars is rejected', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/signup', { method: 'POST', body: { email: 'a@example.com', password: 'Abcdefg1', full_name: 'x'.repeat(101) } });
  assert.equal(code, 400);
});

test('signup: success returns 201 and calls supabase signUp with normalized email', async () => {
  currentRouter = buildRouter();
  const { code, body } = await call('/auth/signup', { method: 'POST', body: { email: 'A@Example.com', password: 'Abcdefg1', full_name: '  Ana  ' } });
  assert.equal(code, 201);
  assert.equal(body.user.id, 'new-user');
  const call_ = supabaseCalls.find((c) => c.method === 'signUp');
  assert.equal(call_.email, 'a@example.com');
  assert.equal(call_.options.data.full_name, 'Ana');
});

test('login: rejects an invalid email with 400', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/login', { method: 'POST', body: { email: 'nope', password: 'x' } });
  assert.equal(code, 400);
});

test('login: success returns tokens and user', async () => {
  currentRouter = buildRouter();
  const { code, body } = await call('/auth/login', { method: 'POST', body: { email: 'a@example.com', password: 'Abcdefg1' } });
  assert.equal(code, 200);
  assert.equal(body.access_token, 'at-123');
  assert.equal(body.user.email, 'a@example.com');
});

test('refresh: rejects a missing refresh_token with 400', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/refresh', { method: 'POST', body: {} });
  assert.equal(code, 400);
});

test('refresh: success returns new tokens', async () => {
  currentRouter = buildRouter();
  const { code, body } = await call('/auth/refresh', { method: 'POST', body: { refresh_token: 'rt-123' } });
  assert.equal(code, 200);
  assert.equal(body.access_token, 'at-123');
});

test('logout: success returns 200', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/logout', { method: 'POST' });
  assert.equal(code, 200);
});

test('forgot-password: rejects an invalid email with 400', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/forgot-password', { method: 'POST', body: { email: 'x' } });
  assert.equal(code, 400);
});

test('forgot-password: success returns a generic message', async () => {
  currentRouter = buildRouter();
  const { code, body } = await call('/auth/forgot-password', { method: 'POST', body: { email: 'a@example.com' } });
  assert.equal(code, 200);
  assert.ok(body.message.includes('If an account exists'));
});

test('reset-password: rejects a weak password with 400', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/reset-password', { method: 'POST', body: { new_password: 'short' } });
  assert.equal(code, 400);
});

test('reset-password: success returns 200', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/reset-password', { method: 'POST', body: { new_password: 'Abcdefg1' } });
  assert.equal(code, 200);
});

test('GET /me: returns the current profile', async () => {
  currentRouter = buildRouter();
  const { code, body } = await call('/auth/me');
  assert.equal(code, 200);
  assert.equal(body.profile.id, 'user-1');
});

test('GET /me: 401 when auth is denied', async () => {
  currentRouter = buildRouter({ auth: fakeAuth({ deny: true }) });
  const { code } = await call('/auth/me');
  assert.equal(code, 401);
});

// --- IDOR prevention: identity always comes from the verified token --------

test('PATCH /me: ignores spoofed id/user_id/role and scopes updates to req.user.id', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/me', {
    method: 'PATCH',
    body: { id: 'victim-999', user_id: 'victim-999', role: 'admin', full_name: 'Attacker' },
  });
  assert.equal(code, 200);
  const update = adminCalls.find((c) => c.updates && c.where && c.where.id === 'user-1');
  assert.ok(update, 'expected an update scoped to the verified user id');
  assert.equal(update.where.id, 'user-1');
  assert.equal(update.updates.id, undefined, 'body id must not be written');
  assert.equal(update.updates.user_id, undefined, 'body user_id must not be written');
  assert.equal(update.updates.role, undefined, 'body role must not be written');
  assert.equal(update.updates.full_name, 'Attacker');
});

test('PATCH /me: rejects a spoofed role write even without other fields', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/me', { method: 'PATCH', body: { role: 'admin' } });
  assert.equal(code, 400); // role is not an allowed field → 'No valid fields provided.'
});

test('PATCH /me: rejects an invalid blood_group', async () => {
  currentRouter = buildRouter();
  const { code, body } = await call('/auth/me', { method: 'PATCH', body: { blood_group: 'Z+' } });
  assert.equal(code, 400);
  assert.ok(body.message.includes('blood_group'));
});

test('PATCH /me: rejects an invalid date_of_birth', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/me', { method: 'PATCH', body: { date_of_birth: '2024-13-99' } });
  assert.equal(code, 400);
});

test('PATCH /me: rejects a javascript avatar_url', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/me', { method: 'PATCH', body: { avatar_url: 'javascript:alert(1)' } });
  assert.equal(code, 400);
});

test('PATCH /me: rejects over-long medical_notes', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/me', { method: 'PATCH', body: { medical_notes: 'x'.repeat(2001) } });
  assert.equal(code, 400);
});

test('PATCH /me: rejects an empty body', async () => {
  currentRouter = buildRouter();
  const { code } = await call('/auth/me', { method: 'PATCH', body: {} });
  assert.equal(code, 400);
});

test('PATCH /me: success writes only allowed fields and returns the profile', async () => {
  currentRouter = buildRouter();
  const { code, body } = await call('/auth/me', { method: 'PATCH', body: { full_name: 'Anita', phone_number: '+1-555-0100', blood_group: 'O+' } });
  assert.equal(code, 200);
  assert.equal(body.profile.full_name, 'Anita');
});

test('PATCH /me: maps a database failure to a sanitized 400', async () => {
  currentRouter = buildRouter({ admin: fakeAdmin({ failUpdate: true }) });
  const { code, body } = await call('/auth/me', { method: 'PATCH', body: { full_name: 'Anita' } });
  assert.equal(code, 400);
  assert.equal(body.message, 'Could not update the profile.');
  assert.ok(!body.message.includes('permission denied'), 'internal error text must not leak');
});

test('audit log receives a login event', async () => {
  eventLog.length = 0;
  currentRouter = buildRouter();
  await call('/auth/login', { method: 'POST', body: { email: 'a@example.com', password: 'Abcdefg1' } });
  assert.equal(eventLog.some((e) => e.event === 'sign_in'), true);
});