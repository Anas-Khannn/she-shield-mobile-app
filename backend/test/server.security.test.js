const { test, before, after } = require('node:test');
const assert = require('node:assert');
const { execFile } = require('node:child_process');
const path = require('node:path');

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

test('malformed JSON body returns a sanitized 400', async () => {
  const res = await fetch(`${baseUrl}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{not valid json',
  });
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.error, 'Invalid JSON');
  assert.deepEqual(Object.keys(body).sort(), ['error', 'message']);
});

test('oversized JSON body returns a 413', async () => {
  const big = JSON.stringify({ email: `${'x'.repeat(20 * 1024)}@example.com`, password: 'x' });
  const res = await fetch(`${baseUrl}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: big,
  });
  assert.equal(res.status, 413);
  const body = await res.json();
  assert.equal(body.error, 'Payload Too Large');
});

test('CORS echoes the origin when the allowlist is permissive', async () => {
  const res = await fetch(`${baseUrl}/health`, {
    headers: { Origin: 'http://localhost:3000' },
  });
  assert.equal(res.headers.get('access-control-allow-origin'), 'http://localhost:3000');
});

test('404 response is sanitized JSON without stack traces', async () => {
  const res = await fetch(`${baseUrl}/nope`);
  assert.equal(res.status, 404);
  const body = await res.json();
  assert.deepEqual(Object.keys(body).sort(), ['error', 'message']);
  assert.ok(!JSON.stringify(body).includes('at '));
});

test('production CORS fails closed when ALLOWED_ORIGINS is unset', async () => {
  const child = path.join(__dirname, '_production_cors_check.js');
  const output = await new Promise((resolve, reject) => {
    execFile(process.execPath, [child], { timeout: 15000 }, (err, stdout, stderr) => {
      if (err) return reject(new Error(`child failed: ${stderr || err.message}`));
      resolve(stdout);
    });
  });
  assert.ok(output.includes('ALLOW=null'), `expected ALLOW=null, got: ${output}`);
});