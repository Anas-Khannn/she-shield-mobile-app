const { test, before, after } = require('node:test');
const assert = require('node:assert');

process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fake-anon-key-for-tests';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-service-role-key-for-tests';
process.env.ALLOWED_ORIGINS = '*';
process.env.APP_URL = 'http://localhost:3000';
process.env.AUTH_RATE_LIMIT_WINDOW_MS = '60000';
process.env.AUTH_RATE_LIMIT_MAX = '3';

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

test('auth rate limit configured via env rejects the 4th request with 429', async () => {
  const send = () => fetch(`${baseUrl}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });

  const first = await send();
  assert.equal(first.status, 400); // validation error, not limited

  const second = await send();
  assert.equal(second.status, 400);

  const third = await send();
  assert.equal(third.status, 400);

  const limited = await send();
  assert.equal(limited.status, 429);
  assert.ok(
    limited.headers.get('ratelimit-limit') || limited.headers.get('retry-after'),
    'expected a rate-limit signal header'
  );
});