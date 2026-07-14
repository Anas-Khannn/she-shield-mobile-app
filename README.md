# 🛡️ She Shield — Women's Safety App

She Shield is a full-stack mobile safety app that lets a user trigger an emergency SOS in one tap — sharing live location, alerting trusted contacts, and quietly recording audio evidence — while also offering discreet tools like a fake incoming call and a safety timer for situations that need to look ordinary from the outside.

Built as a personal full-stack project to go beyond typical CRUD apps and work with real-time location, device sensors (camera, mic, vibration), and secure authentication end-to-end.

---

## ✨ Features

- **One-Tap SOS** — Grabs the user's live GPS location, opens pre-filled emergency SMS messages to all saved contacts with a Google Maps link, places an emergency call to the primary contact, triggers a distress vibration pattern, and starts background audio recording — all from a single trigger.
- **Safety Timer** — A countdown "check-in" timer. If it isn't cancelled before it hits zero, it automatically fires the SOS flow, useful for situations like walking home alone or a late-night ride.
- **Fake Call Simulator** — A realistic fake incoming call screen to help someone exit an uncomfortable situation discreetly.
- **Emergency Contacts** — Add, edit, and manage trusted contacts who get alerted during an SOS.
- **Audio Recording** — Automatically records ambient audio during an SOS event and saves it locally as evidence.
- **Authentication & Profile** — Email/password sign up with verification, login, token refresh, logout, forgot/reset password, and an editable profile (name, phone, avatar, date of birth, blood group, medical notes).
- **Security-first backend** — Rate-limited auth endpoints, security headers, banned-user checks, email-verification gating, and an audit log of every auth event (sign-ups, logins, failed logins, password changes, token refreshes) with IP and user-agent capture.

---

## 🏗️ Tech Stack

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart"/>
  <img src="https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=node.js&logoColor=white" alt="Node.js"/>
  <img src="https://img.shields.io/badge/Express.js-000000?style=for-the-badge&logo=express&logoColor=white" alt="Express"/>
  <img src="https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase"/>
  <img src="https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white" alt="PostgreSQL"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android"/>
  <img src="https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="iOS"/>
  <img src="https://img.shields.io/badge/Google_Maps-4285F4?style=for-the-badge&logo=googlemaps&logoColor=white" alt="Google Maps"/>
  <img src="https://img.shields.io/badge/JSON_Web_Tokens-000000?style=for-the-badge&logo=jsonwebtokens&logoColor=white" alt="JWT"/>
</p>

### 📱 Frontend — Mobile App

| Tech | Purpose |
|------|---------|
| ![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white) | Cross-platform UI (Android, iOS, and desktop targets are scaffolded) |
| ![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat-square&logo=dart&logoColor=white) | Core app language |
| ![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=flat-square&logo=supabase&logoColor=white) | `supabase_flutter` SDK for client-side auth/session handling |
| **Provider** | State management |
| **Geolocator** | Live GPS location |
| **Camera** / **record** | Camera access and audio recording |
| **Vibration** | Custom vibration/alert patterns |
| **URL Launcher** | Launching SMS/tel intents for SOS |
| **Permission Handler** | Runtime permissions (location, mic, camera) |
| **Shared Preferences** | Lightweight local storage |
| **Google Fonts** / **animate_do** | UI styling and animation |
| **flutter_dotenv** | Environment config |

### ⚙️ Backend — API

| Tech | Purpose |
|------|---------|
| ![Node.js](https://img.shields.io/badge/Node.js-339933?style=flat-square&logo=node.js&logoColor=white) | JavaScript runtime for the API server |
| ![Express](https://img.shields.io/badge/Express.js-000000?style=flat-square&logo=express&logoColor=white) | REST API framework |
| ![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=flat-square&logo=supabase&logoColor=white) | Auth + PostgreSQL database, via anon client (user-scoped) and service-role admin client (privileged operations) |
| ![Helmet](https://img.shields.io/badge/Helmet.js-000000?style=flat-square&logo=javascript&logoColor=white) | Secure HTTP headers |
| **CORS** | Configurable allowed origins |
| **express-rate-limit** | Separate, stricter rate limits on auth routes vs. general API routes |
| **dotenv** | Environment configuration |

### 🗄️ Database / Auth Layer

| Tech | Purpose |
|------|---------|
| ![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=flat-square&logo=supabase&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat-square&logo=postgresql&logoColor=white) | Backend-as-a-Service: user auth (sign up, sessions, password resets), a `profiles` table (role, ban status, verification status, medical info), and an `auth_audit_log` table recording every auth event for traceability |

---

## 📂 Project Structure

```
she-shield-mobile-app/
├── lib/                        # Flutter app source
│   ├── controllers/            # auth_controller, contact_controller, sos_controller
│   ├── models/                 # contact_model
│   ├── services/               # auth_service, location_service, media_service
│   ├── utils/                  # app_colors, app_theme
│   ├── views/                  # login, signup, home, contacts, fake call,
│   │                           # safety timer, settings, forgot password
│   └── main.dart
├── backend/                    # Node.js/Express API
│   ├── routes/                 # auth.js (signup/login/refresh/logout/me/...)
│   ├── middleware/              # auth.js (requireAuth, requireEmailVerified, requireRole)
│   ├── services/                # auditLog.js
│   ├── utils/                   # supabaseClient.js
│   └── server.js
├── android/ ios/ web/ linux/ macos/ windows/  # Flutter platform targets
└── pubspec.yaml
```

---

## 🔌 API Overview (`/auth`)

| Method | Endpoint                | Description                                     |
|--------|--------------------------|--------------------------------------------------|
| POST   | `/auth/signup`           | Create account, sends email verification         |
| POST   | `/auth/login`            | Log in, returns access + refresh tokens           |
| POST   | `/auth/refresh`          | Refresh an expired access token                   |
| POST   | `/auth/logout`           | Sign out (requires auth)                          |
| POST   | `/auth/forgot-password`  | Request a password reset email                    |
| POST   | `/auth/reset-password`   | Set a new password (requires auth)                |
| GET    | `/auth/me`               | Get the logged-in user's profile                  |
| PATCH  | `/auth/me`               | Update profile fields (requires verified email)   |
| GET    | `/health`                | Health check                                      |

Every auth event (sign-up, login, failed login, refresh, logout, password change) is written to an audit log with IP address and user agent.

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (^3.11.1)
- Node.js
- A Supabase project (URL + anon key + service role key)

### Backend Setup
```bash
cd backend
npm install
```
Create a `.env` file in `backend/`:
```
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
ALLOWED_ORIGINS=http://localhost:3000
APP_URL=http://localhost:3000
PORT=3000
```
Run the server:
```bash
npm run dev
```

### Flutter App Setup
```bash
flutter pub get
```
Create a `.env` file in the project root (already referenced as an asset in `pubspec.yaml`):
```
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_anon_key
API_BASE_URL=http://localhost:3000
```
Run the app:
```bash
flutter run
```

---

## 📚 What I Learned

Building She Shield end-to-end taught me a lot beyond just "making a CRUD app":

- **Working with real device hardware from Flutter** — requesting and handling runtime permissions for location, camera, and microphone, and dealing with platform differences (Android vs iOS) around background recording and vibration.
- **Designing a real emergency flow** — chaining multiple async operations (get location → format a maps link → message every contact → place a call → start recording) so that if one step fails (e.g., no GPS), the rest of the flow still tries to help the user.
- **Supabase as a real backend, not just an auth demo** — using the anon client for user-scoped calls and a separate service-role admin client for privileged server-side operations (banning users, force sign-out, admin password resets) instead of trusting the client for everything.
- **API security fundamentals** — adding Helmet for secure headers, separate/stricter rate limits on auth routes vs general routes, and validating input server-side even though Supabase does some validation itself.
- **Auditability matters for safety apps** — logging every auth event (including failed logins) with IP and user-agent so suspicious activity on an account can be traced later, since this is a safety-critical app.
- **Role- and status-aware middleware** — writing reusable Express middleware (`requireAuth`, `requireEmailVerified`, `requireRole`) so routes can be gated by verification status, ban status, or role without repeating logic.
- **Thinking about UX under stress** — features like the Safety Timer and Fake Call only work if they're fast and require minimal taps, which changed how I approached state management and screen design.
- **Structuring a Flutter app for growth** — separating concerns cleanly into controllers, services, models, and views instead of putting logic directly in widgets, which made the SOS logic testable and reusable across screens.

---

## 🔮 Future Improvements
- True background SMS/audio upload without relying on the native SMS/dialer app UI
- Cloud upload of SOS audio/location evidence to Supabase Storage instead of local-only storage
- Push notifications to contacts instead of relying on SMS/call intents
- Admin dashboard for reviewing audit logs and managing flagged accounts

---

## 👤 Author

**Anas Khan** ([@Anas-Khannn](https://github.com/Anas-Khannn)) — Computer Science undergraduate, UET Peshawar.
