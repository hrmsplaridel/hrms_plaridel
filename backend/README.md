# HRMS Plaridel – Backend

Node.js + Express + PostgreSQL API for the HRMS Plaridel Flutter app.

Implements the full backend from `docs/BACKEND_MIGRATION_GUIDE.md`:

- **Auth:** JWT, bcrypt, register, login, `/auth/me`, change password, forgot-password (stub)
- **RBAC:** Middleware for admin-only routes
- **CRUD:** departments, positions, shifts, assignments, employees
- **File storage:** Multer (local) for avatar upload; `GET /api/files/avatar/:userId` to serve

---

## Prerequisites

- **Node.js** 18+
- **PostgreSQL** installed and running

---

## Setup

### 1. Install dependencies

```bash
cd backend
npm install
```

### 2. Configure environment

- Copy `.env.example` to `.env`
- Set `DATABASE_URL` (e.g. `postgresql://postgres:password@localhost:5432/hrms_plaridel`)
- Set `JWT_SECRET` (use a long random string; e.g. `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`)

### 3. Initialize database

Create the database (if needed):

```bash
createdb hrms_plaridel
```

Run the schema (Schema v2 – effective dates, override times, policy_assignments, etc.):

```bash
psql -d hrms_plaridel -f scripts/init-schema.sql
```

(Or use pgAdmin: create DB, then run the SQL file.)

### 4. Run the server

```bash
npm run dev
```

---

## Endpoints

| Method | Path                        | Description                                             |
| ------ | --------------------------- | ------------------------------------------------------- |
| GET    | `/health`                   | App health                                              |
| GET    | `/health/db`                | Database health                                         |
| POST   | `/auth/register`            | Register (email, password, fullName?, role?)            |
| POST   | `/auth/login`               | Login (email, password) → returns JWT                   |
| GET    | `/auth/me`                  | Current user (requires `Authorization: Bearer <token>`) |
| PATCH  | `/auth/me`                  | Update profile                                          |
| POST   | `/auth/change-password`     | Change password                                         |
| POST   | `/auth/forgot-password`     | Forgot password (stub)                                  |
| GET    | `/api/departments`          | List departments (?status=Active\|Inactive\|All)        |
| POST   | `/api/departments`          | Create (admin)                                          |
| PUT    | `/api/departments/:id`      | Update (admin)                                          |
| GET    | `/api/positions`            | List positions (?status, ?department_id)                |
| POST   | `/api/positions`            | Create (admin)                                          |
| PUT    | `/api/positions/:id`        | Update (admin)                                          |
| GET    | `/api/shifts`               | List shifts (?status)                                   |
| POST   | `/api/shifts`               | Create (admin)                                          |
| PUT    | `/api/shifts/:id`           | Update (admin)                                          |
| GET    | `/api/assignments`          | List by `?employee_id=uuid`                             |
| POST   | `/api/assignments`          | Create (admin)                                          |
| PUT    | `/api/assignments/:id`      | Update (admin)                                          |
| GET    | `/api/employees`            | List employees (?status, ?role)                         |
| GET    | `/api/employees/:id`        | Get one employee                                        |
| POST   | `/api/employees`            | Create (admin)                                          |
| PUT    | `/api/employees/:id`        | Update (admin)                                          |
| GET    | `/api/holidays`             | List holidays (?year=YYYY)                              |
| POST   | `/api/holidays`             | Create (admin)                                           |
| PUT    | `/api/holidays/:id`         | Update (admin)                                          |
| DELETE | `/api/holidays/:id`         | Delete (admin)                                           |
| GET    | `/api/attendance-policies`   | List policies (?status)                                 |
| POST   | `/api/attendance-policies`   | Create (admin)                                           |
| PUT    | `/api/attendance-policies/:id` | Update (admin)                                        |
| DELETE | `/api/attendance-policies/:id` | Delete (admin)                                        |
| GET    | `/api/dtr-corrections`      | List corrections (?status, ?employee_id)                |
| POST   | `/api/dtr-corrections`      | Create (employee or admin)                               |
| PATCH  | `/api/dtr-corrections/:id/review` | Approve/reject (admin)                             |
| GET    | `/api/biometric-devices`    | List devices (?status)                                  |
| POST   | `/api/biometric-devices`    | Create (admin)                                           |
| PUT    | `/api/biometric-devices/:id` | Update (admin)                                         |
| DELETE | `/api/biometric-devices/:id` | Delete (admin)                                         |
| GET    | `/api/overtime`             | List OT requests (?status, ?employee_id)               |
| POST   | `/api/overtime`             | Submit OT request (employee or admin)                   |
| PATCH  | `/api/overtime/:id/review`  | Approve/reject (admin/hr/supervisor)                    |
| PATCH  | `/api/overtime/:id/payroll` | Mark added to payroll (admin)                           |
| GET    | `/api/calendar/events`      | Calendar events (?start_date, ?end_date, ?employee_id) |
| POST   | `/api/upload/avatar`        | Upload avatar (multipart, auth)                         |
| GET    | `/api/files/avatar/:userId` | Serve avatar image                                      |

---

## Project layout

```
backend/
├── .env              # Secrets (do not commit)
├── .env.example
├── package.json
├── README.md
├── scripts/
│   └── init-schema.sql
├── src/
│   ├── config/
│   │   └── db.js
│   ├── middleware/
│   │   ├── auth.js      # JWT verify
│   │   └── rbac.js      # requireAdmin
│   ├── routes/
│   │   ├── auth.js
│   │   ├── departments.js
│   │   ├── positions.js
│   │   ├── shifts.js
│   │   ├── assignments.js
│   │   ├── employees.js
│   │   ├── upload.js
│   │   └── files.js
│   └── index.js
└── uploads/           # Avatar files (created on first upload)
```

---

## Next: Flutter migration

See `docs/BACKEND_MIGRATION_GUIDE.md` section **2. Flutter App Changes** to switch the Flutter app from Supabase to this API.
