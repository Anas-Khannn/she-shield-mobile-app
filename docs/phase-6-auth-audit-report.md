# Phase 6 — Authentication & Session Security Audit Report

She Shield · Backend + Flutter client
Date: 2026-09-15
Scope: Auth flows, session/refresh handling, API security posture, and the
emergency (SOS) flow's independence from authentication.

---

## 1. Executive summary

Authentication was re-architected end-to-end so that the client treats session
state as a single source of truth, the backend enforces the same password and
verification rules on every entry point, and the emergency SOS path is
guaranteed to never depend on an authenticated network call.

**Test status**
- Flutter: 167 tests passing (controllers, services, widgets).
- Backend: 8 tests passing (routes, security headers, rate-limited auth).
- `flutter analyze`: 0 errors, 0 warnings (1 pre-existing deprecation info in
  `supabase_initializer.dart`, intentionally left).

---

## 2. Client-side session management

| Requirement | Implemented |
|---|---|
| Single source of truth for session state | `AuthController` + `AuthState` enum (`initial / checking / authenticated / unverified / unauthenticated`) |
| Session restoration on startup | `AuthController.restoreSession()` → validates against `GET /auth/me`; offline fallback to cached user so the app stays usable without a network |
| Transparent token refresh | `AuthService.getValidAccessToken()` refreshes an expiring access token via `POST /auth/refresh` before use |
| 401 handling | Authenticated requests that get a 401 trigger **one bounded refresh** then exactly **one retry**. If the refresh fails, or the retry still 401s, `onUnauthorized` fires → `handleSessionExpired()` clears local tokens (no network) — the flow cannot loop |
| Single-flight refresh | Concurrent 401s share a single `/auth/refresh` (no refresh storm): `ApiClient._refreshSession` and `AuthService.refreshAccessToken` both dedupe in-flight calls |
| Duplicate-submission protection | `login` / `signup` / `logout` / `sendPasswordResetEmail` / `restoreSession` early-return while `isLoading` |
| Signup validation | Email format regex + password strength + **confirm-password match** on the client (backend still authoritatively enforces strength) |
| Auth-guarded navigation | `MainNavigation` watches `AuthState`; on `unauthenticated` it routes to `LoginView` once (guarded against duplicate pushes) |
| Logout | `POST /auth/logout` (best-effort) then local session clear |
| Email verification gate | Backend returns 403 `Email Not Verified` when Supabase reports an unconfirmed address; client routes to `EmailVerificationView` |
| Password reset | `AuthController.sendPasswordResetEmail` → `POST /auth/forgot-password`; success/error states in `ForgotPasswordView` |

### Storage notes
- Tokens and profile data persist in `SharedPreferences`. This matches the
  existing app design. **Future hardening** (recommended): move to a secure
  keychain/Keychain-equivalent store (e.g. `flutter_secure_storage`).
- The client never logs tokens or passwords; only network/business errors
  surface via `AppException.userMessage`.

### Password strength (new in this phase)
Enforced identically on client **and** server:

```
Rule: min 8 chars, at least one upper-case letter, one lower-case letter,
      one digit.
Client: SignUpView validator (instant feedback) + confirm-password match.
Server: POST /auth/signup and POST /auth/reset-password.
```

Backend tests added: weak password (no upper) `400`; too-short `400`.

### Password reset — known limitation (documented, non-blocking)
`ForgotPasswordView` sends the reset email via `POST /auth/forgot-password`.
The "set new password" step relies on the emailed Supabase link opened in a
browser; the app does **not** capture that deep link back into the app (the
project has no deep-link infrastructure). The backend reset endpoint still
enforces password strength. Unchanged by design — tracked as a follow-up if a
browser-to-app link flow is added.

---

## 3. SOS independence from authentication (review result)

Requirement: **an auth failure must never break or degrade the SOS flow.**

Review of every SOS dependency:

- `SOSController.triggerSos()` runs: GPS (`geolocator`), vibration, pre-filled
  SMS intents (`url_launcher`), emergency call intent, and local audio recording.
- Contacts come from local `SharedPreferences` (`ContactController`).
- **No backend API call, no access token, no `AuthController` reference exists
  anywhere in the SOS path.**
- `OfflineBanner` health probes hit `GET /health`, which is unauthenticated and
  swallows errors (returns `false`, never triggers `onUnauthorized`).
- The `MainNavigation` auth guard can only fire when `AuthState` transitions to
  `unauthenticated` — that transition is produced exclusively by
  login/signup/logout/restore/401 handlers, none of which execute during an SOS.

**Verdict: PASS.** The SOS flow cannot fail on auth errors by construction, and
each SOS step already has its own error boundary (verified by
`sos_controller_test.dart` fault-isolation suite). A dedicated test now proves
the claim: `SOS independence from authentication · runs end-to-end with an
empty (logged-out) session` executes a full `triggerSos()` with zero tokens in
storage and asserts every operation succeeds. This is the correct design for a
safety app: emergency behavior is device-local and works even offline or with a
revoked session.

---

## 4. Backend security review

| Control | Status |
|---|---|
| Security headers (Helmet, HSTS gated to production) | ✅ |
| CORS restricted to `ALLOWED_ORIGINS` in production | ✅ |
| Body size limit (`10kb`) | ✅ |
| Rate limiting: auth `20 / 15 min`, global API `100 / min` | ✅ |
| Password strength on signup and reset | ✅ (new this phase) |
| Login returns generic "invalid email or password" (no account enumeration) | ✅ |
| Forgot-password returns the same message whether or not an email exists | ✅ (test added) |
| Email-not-confirmed surfaced distinctly (403) for user clarity | ✅ |
| Ban check + `requireRole` middleware available on admin paths | ✅ |
| Service-role client used only server-side; never exposed to the app | ✅ |
| Every auth event audit-logged (IP + user-agent) with failures included | ✅ |
| Audit logging never fails a request (wrapped, best-effort) | ✅ |
| Global error handler returns generic 500, no internals leaked | ✅ |

### Residual risks / recommendations (not blocking)
1. **Secure token storage on device** — move tokens from `SharedPreferences` to
   `flutter_secure_storage` (Keychain/Keystore).
2. **Phone number validation** server-side on signup (client accepts anything
   today; only length-checked).
3. **CSP** is left permissive by Helmet's defaults — fine for an API consumed by
   a mobile client; revisit if a web client is added.
4. **Password rotation/age policy** and **concurrent-session revocation** could
   be added later via Supabase admin APIs.
5. **TOTP / recovery codes** as a second factor would materially raise account
   takeover resistance for a safety app.

---

## 5. Changes in this phase (commits `676e9b2` → `5e25b2f` → "harden auth")

- `lib/services/auth_service.dart` — `AuthSession`, refresh, validate, reset;
  single-flight `refreshAccessToken()` wired into its own `ApiClient`.
- `lib/services/api/api_client.dart` — bounded 401 refresh + single retry;
  single-flight `_refreshSession`; anonymous 401s no longer clear session state.
- `lib/controllers/auth_controller.dart` — `AuthState` state machine, 401 flow,
  duplicate-submission guards.
- `lib/main.dart` — global 401 wiring via `AuthController(onUnauthorized: ...)`.
- `lib/views/main_navigation.dart` — auth guard redirect to `LoginView`.
- `lib/views/email_verification_view.dart` — new verify-email screen.
- `lib/views/login_view.dart` / `signup_view.dart` — unverified-email routing;
  signup enforces password strength, email format, and confirm-password match.
- `lib/views/forgot_password_view.dart` — wired to the real reset endpoint.
- `lib/views/bootstrap_gate.dart` — uses `restoreSession()`.
- `backend/routes/auth.js` — 403 for unverified email; shared password rule on
  signup + reset; forgot-password non-enumeration already present.
- `backend/middleware/auth.js` — removed debug `console.log`s.
- Tests: `auth_controller_test`, `signup_view_test` (+weak-password, confirm),
  `forgot_password_view_test`, `email_verification_view_test`,
  `main_navigation_test`, updated login/splash widget tests, new backend route
  tests, new `ApiClient` 401/refresh suite (retry-once, bounded, single-flight,
  failed-refresh), and the SOS-with-cleared-session independence test.

### Logging / secrets sweep
- `lib`: `debugPrint` calls exist only in SOS/timer/media error paths; they log
  labels and exception messages — never tokens, passwords, or PII.
- `backend`: remaining `console.*` are the startup banner, the global error
  handler (`err.message` only) and best-effort audit-log warnings.
- No `.env`, secret, or service-role value is tracked (only `.env.example`;
  `SupabaseInitializer` actively rejects a service-role key in the client).

---

## 6. Sign-off

All Phase 6 hardening items are implemented, tested (167 Flutter + 8 backend
tests green), and committed. The recommended follow-ups in §4 are intentionally
non-blocking enhancements.