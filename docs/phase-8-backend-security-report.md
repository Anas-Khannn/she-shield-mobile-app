# Phase 8 — Backend Security & Production Hardening Report

She Shield · Node/Express API + Supabase
Date: 2026-09-16
Scope: Authentication authorization, rate limiting, input validation, CORS,
error handling, audit logging, and database row-level security.

---

## 1. Executive summary

The Phase 6 audit established a solid auth/authorization architecture. Phase 8
hardened the remaining production-readiness gaps and added a real test suite
for the security properties. The app's public surface is intentionally small —
the Flutter client only ever calls `/auth/*` and `/health`; SOS, contacts, and
the Safety Timer are fully local and never touch the backend.

Fix list applied in this phase:

| # | Gap found | Fix |
|---|-----------|-----|
| 1 | Malformed JSON bodies fell through to a generic `500`. | Explicit `400 Invalid JSON` handler. |
| 2 | Oversized bodies were not surfaced clearly. | `413 Payload Too Large` handler matching the 10 kb body limit. |
| 3 | CORS fell back to `*` in production when `ALLOWED_ORIGINS` was unset. | `utils/corsConfig.js` resolves the allowlist; production fails closed (no browser origin allowed). |
| 4 | Rate limits were hard-coded. | `AUTH_RATE_LIMIT_*` / `API_RATE_LIMIT_*` env variables with safe defaults. |
| 5 | Input validation was mostly delegated to Supabase. | New dependency-free `middleware/validate.js`; every route validates type, length, and format before touching Supabase. |
| 6 | PATCH `/auth/me` did not constrain field values. | Per-field rules (blood group enum, ISO date, http(s) URL, lengths, phone charset). |
| 7 | Audit-log metadata could contain credential-shaped keys. | `sanitizeMetadata()` strips keys matching password/token/secret/authorization/cookie/session and truncates long strings — applied at the storage layer. |
| 8 | No database security artifact existed. | `backend/supabase/rls.sql` — idempotent RLS policies for `profiles`, ready to run in the Supabase SQL editor. |
| 9 | Authorization/IDOR behaviour was not testable without a live Supabase project. | `middleware/auth.js` exposes `makeRequireAuth()` and `routes/auth.js` exports a `createAuthRouter()` factory with overridable dependencies. |
| 10 | No security regression tests. | 40+ new tests (see §8): middleware, routes, IDOR, validation, rate limiting, CORS, error handling, audit redaction. |

**Test status**
- Backend: `npm test` → 54/54 passing (Node 24, built-in test runner).
- `npm audit` → 0 vulnerabilities.
- Flutter: 186 tests passing; `flutter analyze` clean except the pre-existing
  `anonKey` deprecation info.

---

## 2. Threat model

Assumptions the design relies on:

1. **The mobile client is untrusted.** The app is rebuilt from source by anyone;
   body fields, headers, and user ids are all attacker-controlled.
2. **Identity comes only from the verified JWT.** `supabaseAdmin.auth.getUser`
   resolves the presented Bearer token to the actual Supabase user. Every
   user-scoped operation derives `id` from `req.user.id`, never from the body.
3. **The service-role key stays server-side.** It is used only inside the
   backend (admin profile fetches, bans, audit writes) and never shipped to or
   trusted by the client. The client uses only the anon key.
4. **SOS/timer/contacts are local.** They carry no account data, so a backend
   breach does not expose emergency workflow capability.
5. **Monkey/patching of the runtime environment** (env vars, Node CVEs,
   dependencies) is a deployment concern documented in §9, outside this
   audit's code scope.

### Non-goals (documented, unchanged)
- Tokens on the device are stored in `SharedPreferences` (plaintext). Fixing
  requires keychain/keystore work; tracked for a future phase.
- No admin/role-based API beyond the existing `requireRole` middleware.
- `package-lock.json` remains untracked (repo convention): dependencies pin to
  `^` ranges, `npm audit` is clean at the pinned versions, and production
  deployments must run `npm install` on a locked resolution (see §9).

---

## 3. Endpoint security matrix

| Endpoint | Auth | Rate limit | Extra gates | Input validation |
|----------|------|-----------|-------------|------------------|
| `GET  /health` | none | global | — | — |
| `POST /auth/signup` | none | auth 20/15min | — | email (≤254, RFC-ish), password 8–128 w/ upper+lower+digit, full_name ≤100, phone optional+charset |
| `POST /auth/login` | none | auth 20/15min | generic error on failure; email-not-confirmed → 403 with guidance | email + password presence/length |
| `POST /auth/refresh` | none | auth 20/15min | — | refresh_token ≤512 |
| `POST /auth/logout` | Bearer | auth 20/15min | auth middleware (ban check) | — |
| `POST /auth/forgot-password` | none | auth 20/15min | always 200; never reveals account existence | email |
| `POST /auth/reset-password` | Bearer | auth 20/15min | auth middleware | new_password 8–128 rule |
| `GET  /auth/me` | Bearer | global | auth middleware; profile owner = `req.user.id` | — |
| `PATCH /auth/me` | Bearer | global | auth middleware + `requireEmailVerified` | field allowlist + per-field rules; `id`/`role`/`user_id` in body are ignored |

All responses keep the flat `{ error, message }` shape consumed by the Flutter
`ApiClient`. Internal error text (Supabase/DB messages) is never echoed to the
client.

---

## 4. What changed

### 4.1 `server.js`
- `express.json({ limit: '10kb' })` body limit retained; new handlers map
  `entity.parse.failed` → 400 and oversized bodies → 413.
- Global error handler sanitizes every response; stack traces are logged only
  when `NODE_ENV !== 'production'`.
- Rate-limit sizing reads `AUTH_RATE_LIMIT_WINDOW_MS` / `AUTH_RATE_LIMIT_MAX`
  and `API_RATE_LIMIT_WINDOW_MS` / `API_RATE_LIMIT_MAX` with defaults of
  20/15min and 100/min.
- CORS uses `resolveAllowedOrigins()`; `credentials: false` (bearer, not
  cookies).
- `trust proxy` enabled only in production, so `req.ip`/limiters see real
  client addresses behind an HTTPS reverse proxy.

### 4.2 `middleware/validate.js` (new)
Dependency-free validators: email, phone charset/length, UUID, http(s) URL,
ISO date (round-trips through UTC so `2024-02-30` is rejected), blood-group
enum, bounded strings.

### 4.3 `middleware/requireAuth` hardening (`makeRequireAuth`)
The production `requireAuth` is now constructed by `makeRequireAuth()` with the
default JWT-lookup and profile fetch. Tests inject fakes. Behaviour unchanged:
401 for missing/invalid token, 403 for banned accounts, populates
`req.user` / `req.profile` / `req.accessToken`.

Guard rails against common authorization mistakes:
- `makeRequireAuth` needs no request body — it only reads the `Authorization`
  header.
- `requireRole` still reads `req.profile.role` (verified server-side), never a
  body value.

### 4.4 `routes/auth.js` — factory + per-route validation
- `createAuthRouter(overrides)` returns the router wired to real Supabase
  clients by default; `server.js` calls it with no arguments.
- Every body field is validated before any Supabase call.
- `PATCH /auth/me` builds an update object from a fixed allowlist
  (`full_name`, `phone_number`, `avatar_url`, `date_of_birth`, `blood_group`,
  `medical_notes`) and writes scoped to `req.user.id`.
- Signup normalizes email to lowercase and full_name to trimmed value.
- `reset-password` returns a generic message on failure (no internal text).

### 4.5 `services/auditLog.js`
`logAuthEvent` now runs every metadata payload through `sanitizeMetadata()`
before the insert: credential-shaped keys are dropped at any depth, strings are
capped at 500 chars, and dangerous values are omitted. Logging failures remain
non-fatal.

### 4.6 `supabase/rls.sql` (new, documentation + safe default)
Idempotent DDL you run in the Supabase SQL editor (or via the Supabase CLI):
- `ENABLE ROW LEVEL SECURITY` on `profiles`.
- `profiles_select_own` / `profiles_insert_own` / `profiles_update_own`
  policies keyed on `auth.uid() = id`.
- **No** `DELETE` policy — users cannot remove their own profile.
- `auth_audit_log` table is RLS-enabled with no client policies (backend-only
  via service role).

The Flutter app never queries Postgres directly, so RLS is defense in depth —
it guarantees a leaked anon key or a compromised client cannot read/write
another user's row even if the API is bypassed entirely.

---

## 5. Authorization & IDOR verification

There are no user-id-in-URL endpoints in this API — the only resource is the
caller's own profile (`/auth/me`). The IDOR proof is encoded as a regression
test:

```
PATCH /auth/me  body: { id: 'victim-999', user_id: 'victim-999', role: 'admin', full_name: 'Attacker' }
  → update is executed with .eq('id', req.user.id)
  → asserts body id/user_id/role were NEVER written
```

A spoofed `role: 'admin'` alone returns 400 ("No valid fields provided")
because `role` is not in the PATCH allowlist.

---

## 6. CORS & CSRF notes

- CORS matters only for browser clients; the native app authenticates with a
  Bearer header and is not subject to same-origin policy.
- In production, an unset `ALLOWED_ORIGINS` resolves to an empty allowlist —
  browsers from any origin are rejected until explicitly configured. Optional
  `corsConfig` tests cover this.
- No cookies are used, so classic CSRF does not apply; `credentials` stays
  `false`.

---

## 7. Scheme of things not changed (intentional)

- `NODE_ENV=production` is honored for Helmet HSTS and `trust proxy`; local
  dev keeps HSTS off.
- Body limit stays `10kb`: the API sends no file uploads.
- The generic 500 message omits `error.code`/stack always; dev-only logging
  keeps context for debugging.
- Error shape `{ error, message }` is preserved to avoid breaking the Flutter
  client.

---

## 8. Test suite (backend)

Run with `npm test` (`node --test "test/*.test.js"`; each file runs in its
own process so env-based configs are isolated).

| File | Coverage |
|------|----------|
| `test/server.test.js` | health, 404, security headers, missing-payload, 401, password rules, forgot-password non-enumeration |
| `test/server.security.test.js` | malformed JSON → 400, oversized → 413, CORS echo, sanitized 404, production CORS fail-closed (child process) |
| `test/rate.limit.test.js` | env-configured auth limit returns 429 on the 4th request |
| `test/corsConfig.test.js` | allowlist parsing, prod fail-closed, dev default |
| `test/middleware.auth.test.js` | `makeRequireAuth`: missing/non-Bearer/invalid token, banned-profile 403, success wiring |
| `test/routes.auth.test.js` | validation on every route, IDOR/allowlist PATCH proofs, sanitized DB errors, audit events |
| `test/audit.log.test.js` | `sanitizeMetadata` redaction/truncation at top level, nested, arrays |

New files: `middleware/validate.js`, `utils/corsConfig.js`,
`backend/supabase/rls.sql`.

---

## 9. Deployment checklist

1. Set real `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
   `APP_URL`; run `NODE_ENV=production`.
2. Set `ALLOWED_ORIGINS` to the comma-separated browser origins (empty → No
   browser origin allowed).
3. Tune `AUTH_RATE_LIMIT_*` / `API_RATE_LIMIT_*` if needed (defaults match the
   docs).
4. Run `backend/supabase/rls.sql` in the Supabase SQL editor.
5. Run `npm install` on the checked-in dependency ranges, then `npm audit`
   (clean as of this report) — do not commit `package-lock.json` per repo
   convention.
6. Serve only over HTTPS behind a reverse proxy; keep the service-role key and
   `.env` out of any public channel.