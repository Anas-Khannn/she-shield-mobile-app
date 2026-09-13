require('dotenv').config();
const express    = require('express');
const cors       = require('cors');
const helmet     = require('helmet');
const rateLimit  = require('express-rate-limit');
const pkg        = require('./package.json');

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

// CORS — restrict origins via ALLOWED_ORIGINS (comma separated) in production.
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
  methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// Body parser
app.use(express.json({ limit: '10kb' }));

// Rate limiters
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
});
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
});

// Global API throttle (applies to every request, including health checks and
// the 404 handler). Auth routes are additionally limited by authLimiter.
app.use(apiLimiter);

// Routes
const authRoutes = require('./routes/auth');
app.use('/auth', authLimiter, authRoutes);

// Health check
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

// Global error handler
app.use((err, req, res, next) => {
  console.error('[Error]', err.message);
  res.status(500).json({ error: 'Internal Server Error' });
});

// Only listen when run directly so tests can import the app.
if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`🛡️  She_Shield API running on http://localhost:${PORT}`);
  });
}

module.exports = { app };