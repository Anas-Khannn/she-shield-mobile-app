const { test, before, after } = require('node:test');
const assert = require('node:assert');

process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fake-anon-key-for-tests';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-service-role-key-for-tests';
process.env.ALLOWED_ORIGINS = '*';
process.env.APP_URL = 'http://localhost:3000';

const { app } = require('../server');

let server;
let baseUrl;

before(async () => {
  server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.close();
});

test('GET /health returns ok with service info', async () => {
  const res = await fetch(`${baseUrl}/health`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, 'ok');
  assert.equal(body.service, 'She_Shield API');
  assert.ok(typeof body.version === 'string');
  assert.ok(typeof body.timestamp === 'string');
});

test('unknown route returns a JSON 404', async () => {
  const res = await fetch(`${baseUrl}/does-not-exist`);
  assert.equal(res.status, 404);
  const body = await res.json();
  assert.equal(body.error, 'Not Found');
  assert.ok(body.message.includes('/does-not-exist'));
});

test('security headers are present on responses', async () => {
  const res = await fetch(`${baseUrl}/health`);
  assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(res.headers.get('x-frame-options'), 'SAMEORIGIN');
  assert.ok(res.headers.get('x-dns-prefetch-control'));
});

test('auth endpoints reject a missing payload with 400', async () => {
  const res = await fetch(`${baseUrl}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error, 'Validation Error');
});

test('protected route returns 401 without a bearer token', async () => {
  const res = await fetch(`${baseUrl}/auth/me`, {
    method: 'GET',
    headers: { 'Content-Type': 'application/json' },
  });
  assert.equal(res.status, 401);
  const body = await res.json();
  assert.equal(body.error, 'Unauthorized');
});

test('signup rejects a weak password (no uppercase)', async () => {
  const res = await fetch(`${baseUrl}/auth/signup`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'a@b.com', password: 'alllowercase1', full_name: 'Test' }),
  });
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error, 'Validation Error');
  assert.ok(body.message.includes('upper'));
});

test('signup rejects a weak password (too short)', async () => {
  const res = await fetch(`${baseUrl}/auth/signup`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'a@b.com', password: 'Ab1', full_name: 'Test' }),
  });
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error, 'Validation Error');
});

test('forgot-password does not leak whether the email exists', async () => {
  const res = await fetch(`${baseUrl}/auth/forgot-password`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'unknown@example.com' }),
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.ok(body.message.includes('If an account exists'));
});