const { test } = require('node:test');
const assert = require('node:assert');

const { resolveAllowedOrigins, DEFAULT_DEV_ORIGINS } = require('../utils/corsConfig');

test('corsConfig: production fails closed when ALLOWED_ORIGINS is unset', () => {
  assert.deepEqual(resolveAllowedOrigins({ NODE_ENV: 'production' }), []);
});

test('corsConfig: non-production defaults to a permissive dev origin', () => {
  assert.deepEqual(resolveAllowedOrigins({ NODE_ENV: 'development' }), [DEFAULT_DEV_ORIGINS]);
  assert.deepEqual(resolveAllowedOrigins({}), [DEFAULT_DEV_ORIGINS]);
});

test('corsConfig: parses and trims a comma-separated allowlist', () => {
  const out = resolveAllowedOrigins({
    NODE_ENV: 'production',
    ALLOWED_ORIGINS: ' https://app.example.com ,, https://admin.example.com , ',
  });
  assert.deepEqual(out, ['https://app.example.com', 'https://admin.example.com']);
});

test('corsConfig: preserves an explicit wildcard', () => {
  assert.deepEqual(resolveAllowedOrigins({ NODE_ENV: 'production', ALLOWED_ORIGINS: '*' }), ['*']);
});