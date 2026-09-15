require('dotenv').config();
const express    = require('express');
const cors       = require('cors');
const helmet     = require('helmet');
const rateLimit  = require('express-rate-limit');
const pkg        = require('./package.json');

const { resolveAllowedOrigins } = require('./utils/corsConfig');

const app  = express();
const PORT = process.env.PORT || 3000;
const isProduction = process.env.NODE_ENV === 'production';

// When deployed behind an HTTPS reverse proxy (nginx, cloud run, etc.) let
// Express trust the first hop so rate limiters and req.ip see the real client
// address instead of the proxy IP.
app.set('trust proxy', isProduction ? 1 : false);

// Security headers. HSTS is only advertised for production deployments that
// terminate TLS; over plain http it would be ignored, and enabling it for
// local development would be meaningless.
app.use(helmet({
  hsts: isProduction
    ? { maxAge: 63072000, includeSubDomains: true, preload: false }
    : false,
}));

// CORS — browser origins must be explicitly allowlisted via ALLOWED_ORIGINS.
// Production fails closed (no browser origin allowed) when the variable is
// missing; the native mobile app authenticates with a Bearer header and is not
// subject to browser same-origin policy. Credentials are never enabled because
// the API uses token (not cookie) authentication.
app.use(cors({
  origin(origin, callback) {
    const allowed = resolveAllowedOrigins();
    if (allowed.includes('*')) return callback(null, true);
    if (!origin || allowed.includes(origin)) return callback(null, true);
    return callback(null, false);
  },
  methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: false,
}));

// Body parser — small, bounded payloads. The API only exchanges JSON.
app.use(express.json({ limit: '10kb' }));

// Read a positive-integer env override, falling back to a default.
function limitFromEnv(name, fallback) {
  const raw = process.env[name];
  const parsed = Number.parseInt(raw, 10);
  if (raw !== undefined && !Number.isNaN(parsed) && parsed > 0) return parsed;
  return fallback;
}

// Rate limiters — sizes are configurable so high-traffic or CI environments
// can adapt without code changes. Auth endpoints always get a strict limit.
const authLimiter = rateLimit({
  windowMs: limitFromEnv('AUTH_RATE_LIMIT_WINDOW_MS', 15 * 60 * 1000),
  max: limitFromEnv('AUTH_RATE_LIMIT_MAX', 20),
  standardHeaders: true,
  legacyHeaders: false,
});
const apiLimiter = rateLimit({
  windowMs: limitFromEnv('API_RATE_LIMIT_WINDOW_MS', 60 * 1000),
  max: limitFromEnv('API_RATE_LIMIT_MAX', 100),
  standardHeaders: true,
  legacyHeaders: false,
});

// Global API throttle (applies to every request, including health checks and
// the 404 handler). Auth routes are additionally limited by authLimiter.
app.use(apiLimiter);

// Routes — the auth router factory returns a router wired to the real
// Supabase clients by default.
const createAuthRoutes = require('./routes/auth');
app.use('/auth', authLimiter, createAuthRoutes());

// Health check — intentionally reveals only safe operational information.
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'She_Shield API',
    version: pkg.version,
    timestamp: new Date().toISOString(),
  });
});

// 404
app.use((req, res) => {
  res.status(404).json({ error: 'Not Found', message: `Route ${req.method} ${req.path} not found.` });
});

// Global error handler — client-facing errors are always sanitized.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  // Malformed JSON body.
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'Invalid JSON', message: 'Request body is not valid JSON.' });
  }
  // Payload larger than the configured limit.
  if (err.type === 'entity.too.large' || err.status === 413) {
    return res.status(413).json({ error: 'Payload Too Large', message: 'Request body exceeds the allowed size.' });
  }
  if (err.status && err.status >= 400 && err.status < 500) {
    return res.status(err.status).json({ error: 'Bad Request', message: 'Invalid request.' });
  }

  if (!isProduction) {
    // Stack traces are useful for developers only — never in production.
    console.error('[Error]', err.stack || err.message);
  } else {
    console.error('[Error]', err.message);
  }
  return res.status(500).json({ error: 'Internal Server Error', message: 'An unexpected error occurred.' });
});

// Only listen when run directly so tests can import the app.
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`🛡️  She_Shield API running on http://localhost:${PORT}`);
  });
}

module.exports = { app };