// Helper for server.security.test.js — boots the real app as if deployed to
// production with ALLOWED_ORIGINS unset and prints the CORS header for a
// request carrying a hostile Origin. The parent test asserts on stdout.
'use strict';

process.env.NODE_ENV = 'production';
delete process.env.ALLOWED_ORIGINS;
process.env.APP_URL = 'http://localhost:3000';
process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fake-anon-key-for-tests';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-service-role-key-for-tests';

const { app } = require('../server');

const server = app.listen(0, '127.0.0.1', async () => {
  try {
    const { port } = server.address();
    const res = await fetch(`http://127.0.0.1:${port}/health`, {
      headers: { Origin: 'https://evil.example.com' },
    });
    const allow = res.headers.get('access-control-allow-origin');
    console.log(`ALLOW=${allow}`);
  } finally {
    server.close();
  }
});