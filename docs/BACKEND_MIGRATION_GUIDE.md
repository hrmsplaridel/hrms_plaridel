# Backend Migration Guide: Supabase → Node.js/Express/PostgreSQL

This document describes what must change in **hrms_plaridel** when you switch from Supabase to your own backend.

---

## Is This Setup Good?

**Yes.** Your proposed stack is solid and widely used:

| Layer | Your choice | Notes |
|-------|-------------|--------|
| **Backend** | Node.js + Express.js | Standard, easy to deploy and maintain. |
| **Database** | PostgreSQL + `pg` | Same DB type Supabase uses; schema can stay similar. |
| **Auth** | JWT + bcrypt + RBAC | Stateless, works well with Flutter (store token, send in header). |
| **File storage** | Multer (local) or AWS S3 | Multer for simple/cheap; S3 for scale and CDN. |

No fundamental changes to this plan are required. You’ll mainly need to build the Express API and then change the Flutter app to call it instead of Supabase.

---

## Current State (What You Have Now)

Your app currently uses **Supabase** for:

1. **Authentication** – `Supabase.instance.client.auth`  
   - Login, sign up, sign out, current user, auth state listener, forgot password, profile/avatar updates.
2. **Database** – Direct Supabase client  
   - Tables used: `departments`, `assignments`, `shifts`, `positions`, employees (and related), plus recruitment, leave, DTR, docutracker, etc.
3. **File storage** – `Supabase.instance.client.storage`  
   - Avatar uploads, signed URLs for avatars/documents.

Supabase is initialized in `main.dart` and used in many files under `lib/`.

---

## Changes Needed

### 1. New Backend (Node.js + Express)

You need to implement:

- **Auth**
  - `POST /auth/login` – validate email/password (bcrypt), return JWT (include `userId`, `email`, `role`).
  - `POST /auth/register` – create user (hash password with bcrypt), optional role.
  - `POST /auth/forgot-password` – send reset link or token (e.g. email service).
  - `POST /auth/refresh` (optional) – refresh JWT if you use short-lived access tokens.
  - Protected routes: middleware that verifies JWT and attaches `req.user` (id, email, role) for **RBAC**.
- **Database**
  - Use `pg` to run SQL. Design schema (tables for users, departments, positions, shifts, assignments, employees, leave, DTR, documents, etc.). You can mirror or adapt your current Supabase tables.
  - One route (or set of routes) per resource, e.g.:
    - Departments: GET/POST/PUT/DELETE `/api/departments`
    - Positions, shifts, assignments, employees, etc. similarly.
  - Return JSON; Flutter will replace Supabase client calls with HTTP calls to these endpoints.
- **File storage**
  - **Multer (local):** e.g. `POST /api/upload/avatar`, save file on server, store path in DB; `GET /api/files/avatar/:userId` (or signed URL) to serve.
  - **AWS S3:** Backend generates presigned URLs; Flutter uploads to S3; backend stores key in DB and returns URL or signed URL for reading.
- **CORS** – Allow your Flutter web/mobile origins in Express.
- **Environment** – e.g. `DATABASE_URL`, `JWT_SECRET`, optional `AWS_*` for S3.

---

### 2. Flutter App Changes

#### 2.1 Dependencies

- **Remove or stop using:** `supabase_flutter` for auth, DB, and storage (you can remove it once migration is done).
- **Add:** HTTP client – e.g. `dio` or `http` – and optionally `flutter_secure_storage` (or keep `shared_preferences`) for storing the JWT.

Example `pubspec.yaml`:

```yaml
dependencies:
  dio: ^5.4.0
  flutter_secure_storage: ^9.0.0
  # remove supabase_flutter when fully migrated
```

#### 2.2 Configuration

- Add a **base URL** for your API (e.g. `https://your-api.com` or `http://localhost:3000` for dev).
- Use `--dart-define=API_BASE_URL=...` or a config file / environment so the app knows where to send requests.

#### 2.3 Authentication

- **`lib/main.dart`**
  - Remove `Supabase.initialize(...)`.
  - On startup: read JWT from secure storage; if present and not expired, set “logged-in” state and go to the appropriate dashboard (Admin/Employee) based on role stored in token or from a small “me” API; otherwise show Login or Landing.
- **`lib/providers/auth_provider.dart`**
  - Replace Supabase auth with:
    - **Login:** `POST /auth/login` with email/password → store JWT and optionally role → notify listeners.
    - **Sign out:** clear JWT and user state → notify listeners.
    - **Auth state:** no Supabase listener; derive state from stored JWT + optional `GET /auth/me` (or decode JWT for id/email/role).
  - Keep the same public API (e.g. `user`, `displayName`, `email`, `avatarPath`, `signOut`, `refreshUser`) so the rest of the app does not need to change for basic auth.
- **`lib/login/screens/login_page.dart`**
  - Replace `Supabase.instance.client.auth.signInWithPassword` with a call to your auth provider that uses `POST /auth/login` and stores the JWT.
- **Sign up**
  - Replace Supabase sign-up with `POST /auth/register` (e.g. in `sign_up_page.dart`, `admin_dashboard.dart`, `manage_employee.dart` where you create users).
- **Forgot password**
  - Replace `resetPasswordForEmail` with `POST /auth/forgot-password`.
- **Profile / password update**
  - Replace `auth.updateUser(...)` with your API (e.g. `PATCH /auth/me` for profile, `POST /auth/change-password` for password). Update `AuthProvider.refreshUser()` to call `GET /auth/me` and update local user state.

#### 2.4 Database Access (Supabase client → REST)

Every place that uses `Supabase.instance.client.from('...')` or direct Supabase DB access must call your Express API instead:

- **`lib/dtr/manage/manage_department.dart`** – departments CRUD → `/api/departments`.
- **`lib/dtr/manage/manage_position.dart`** – positions → `/api/positions`.
- **`lib/dtr/manage/manage_shift.dart`** – shifts → `/api/shifts`.
- **`lib/dtr/manage/manage_assignment.dart`** – assignments → `/api/assignments`.
- **`lib/dtr/manage/manage_employee.dart`** – employees + sign up + storage → `/api/employees`, `/auth/register`, `/api/upload/avatar` (or S3 flow).
- **`lib/dtr/dtr_provider.dart`** – replace Supabase auth and any DB calls with API + JWT.
- **`lib/docutracker/docutracker_repository.dart`** – documents → `/api/documents` (or similar).
- **`lib/data/*.dart`** – recruitment, forms, etc. that use `_client` (Supabase) → same pattern: one or more API services that use your HTTP client and send the JWT in the `Authorization` header.

Introduce a single **API client** (e.g. `lib/api/client.dart`) that:

- Uses your base URL.
- Attaches `Authorization: Bearer <token>` from storage.
- Exposes methods like `getDepartments()`, `createEmployee()`, etc., so the rest of the app stays clean.

#### 2.5 File Storage

- **Avatar upload**
  - **`lib/shared/screens/profile_page.dart`** – replace Supabase storage upload and `auth.updateUser(avatar_path)` with:
    - Multer: `POST /api/upload/avatar` (multipart) and `PATCH /auth/me` with new avatar path; then refresh user.
    - S3: get presigned URL from backend, upload from Flutter to S3, then PATCH user with key/URL and refresh.
- **Avatar display**
  - **`lib/widgets/user_avatar.dart`**, **`lib/shared/screens/profile_page.dart`** – replace `createSignedUrl` with your backend URL (e.g. `GET /api/files/avatar/:userId` or URL returned from `/auth/me`).
- **Other files** (e.g. in `manage_employee.dart`, docutracker) – same idea: upload via your API or presigned URL; download/serve via your backend or signed URL from backend.

#### 2.6 Initial routing and role

- **`_initialHome(storedLoginAs)`** in `main.dart` – instead of `Supabase.instance.client.auth.currentUser`, use “has valid JWT + role” (from token or `/auth/me`). Keep the same logic: Admin vs Employee dashboard, or Login/Landing.

---

### 3. Files to Touch (Summary)

| Area | Files |
|------|--------|
| App init & routing | `lib/main.dart` |
| Auth state | `lib/providers/auth_provider.dart` |
| Login / sign up / forgot password | `lib/login/screens/login_page.dart`, `sign_up_page.dart` |
| Profile & password | `lib/shared/screens/profile_page.dart` |
| Avatar | `lib/widgets/user_avatar.dart` |
| DTR manage | `lib/dtr/manage/manage_department.dart`, `manage_position.dart`, `manage_shift.dart`, `manage_assignment.dart`, `manage_employee.dart` |
| DTR provider | `lib/dtr/dtr_provider.dart` |
| Docutracker | `lib/docutracker/docutracker_repository.dart` |
| Data layer (Supabase `_client`) | `lib/data/selection_lineup.dart`, `recruitment_application.dart`, `action_brainstorming_coaching.dart`, `performance_evaluation_form.dart`, `training_need_analysis.dart`, `comparative_assessment.dart`, `applicants_profile.dart`, `job_vacancy_announcement.dart`, `promotion_certification.dart`, `turn_around_time.dart`, `bi_form.dart`, `individual_development_plan.dart`, `time_record.dart` |
| Admin / RSP | `lib/admin/screens/admin_dashboard.dart`, `lib/recruitment/screens/rsp_admin_screen.dart` |
| Config | `lib/supabase/supabase_config.dart` → replace with `lib/api/config.dart` (base URL, etc.) |

---

### 4. Suggested Order of Work

1. **Backend**
   - Set up Express, PostgreSQL, and `pg`.
   - Implement auth (register, login, JWT, bcrypt, RBAC middleware).
   - Add a few core resources (e.g. departments, employees) and test with Postman/curl.
   - Add file upload (Multer or S3) and an endpoint to get avatar URL.
2. **Flutter**
   - Add `dio` + secure storage; create `lib/api/client.dart` and config.
   - Migrate auth (login, sign out, token storage, initial route).
   - Migrate one module end-to-end (e.g. departments) so the pattern is clear.
   - Migrate remaining Supabase DB and storage usage to your API.
   - Remove Supabase initialization and dependency when done.

---

### 5. Security Notes

- Store JWT in **flutter_secure_storage** (or equivalent); avoid long-lived tokens; consider refresh tokens if you need long sessions.
- Use **HTTPS** in production; set CORS to your real front-end origins only.
- Keep **JWT_SECRET** and DB credentials in environment variables, not in code.
- Apply **RBAC** on the backend for every protected route (e.g. admin-only, employee-only); do not rely only on the Flutter app for access control.

---

This migration is feasible without changing your product design; the main work is implementing the Express API and swapping Supabase calls for HTTP calls and JWT-based auth in the Flutter app.
