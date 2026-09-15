const { test } = require('node:test');
const assert = require('node:assert');

process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fake-anon-key-for-tests';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-service-role-key-for-tests';
process.env.ALLOWED_ORIGINS = '*';
process.env.APP_URL = 'http://localhost:3000';

const { sanitizeMetadata } = require('../services/auditLog');

test('sanitizeMetadata: drops credential-shaped keys at the top level', () => {
  const out = sanitizeMetadata({
    email: 'a@example.com',
    reason: 'wrong password',
    password: 'supersecret',
    access_token: 'abc',
    Authorization: 'Bearer x',
  });
  assert.equal(out.email, 'a@example.com');
  assert.equal(out.reason, 'wrong password');
  assert.equal(out.password, undefined);
  assert.equal(out.access_token, undefined);
  assert.equal(out.Authorization, undefined);
});

test('sanitizeMetadata: drops credential-shaped keys in nested objects/arrays', () => {
  const out = sanitizeMetadata({
    context: {
      refresh_token: 'abc',
      safe: 'ok',
      nested: [{ secret_key: 'x', keep: 1 }],
    },
  });
  assert.equal(out.context.safe, 'ok');
  assert.equal(out.context.refresh_token, undefined);
  assert.deepEqual(out.context.nested, [{ keep: 1 }]);
});

test('sanitizeMetadata: truncates oversized strings to 500 characters', () => {
  const out = sanitizeMetadata({ big: 'x'.repeat(2000), small: 'y'.repeat(10) });
  assert.ok(out.big.length < 2000, 'oversized value must be truncated');
  assert.ok(out.big.endsWith('…'));
  assert.equal(out.small, 'y'.repeat(10));
});

test('sanitizeMetadata: keeps primitives and null', () => {
  const out = sanitizeMetadata({ n: 42, ok: true, nil: null });
  assert.equal(out.n, 42);
  assert.equal(out.ok, true);
  assert.equal(out.nil, null);
});

test('sanitizeMetadata: drops callable values and keeps plain data', () => {
  const out = sanitizeMetadata({ fn: () => 1, sym: Symbol('x'), arr: [1, { a: 2 }, 'ok'], empty: {} });
  assert.deepEqual(out.arr, [1, { a: 2 }, 'ok']);
  assert.equal(out.fn, undefined);
  assert.equal(out.sym, undefined);
  assert.deepEqual(out.empty, {});
});