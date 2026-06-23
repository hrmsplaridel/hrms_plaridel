# HRMS - Municipality of Plaridel

Human Resource Management System (HRMS) for the Municipality of Plaridel, Misamis Occidental.

The system supports recruitment, employee records, time and attendance (DTR), leave and locator slips, learning and development, HR forms, document tracking, and employee/admin self-service workflows. The frontend is a responsive Flutter app for web, desktop, and mobile. The backend is a Node.js/Express API backed by PostgreSQL.

## Project Structure

```text
hrms_plaridel/
  frontend/  # Flutter app
  backend/   # Node/Express/PostgreSQL API
  docs/      # Architecture, deployment, and module documentation
  scripts/   # Local development and deployment helper scripts
```

## Prerequisites

- Flutter SDK 3.9+
- Dart SDK compatible with the Flutter version
- Node.js 18+
- PostgreSQL
- Git

## Frontend Setup

Run Flutter commands from `frontend/`:

```bash
cd frontend
flutter pub get
flutter run
```

To point the app at a specific API URL:

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

For release APK builds, use the public HTTPS domain:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR_DOMAIN
```

Build the public applicant landing page:

```bash
flutter build web --release -t lib/main_landing.dart --dart-define=API_BASE_URL=https://YOUR_DOMAIN
```

Build the full HRMS web app:

```bash
flutter build web --release --dart-define=API_BASE_URL=https://YOUR_DOMAIN
```

## Backend Setup

Run backend commands from `backend/`:

```bash
cd backend
npm install
```

Create `backend/.env` from `backend/.env.example`, then set at least:

```env
DATABASE_URL=postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@localhost:YOUR_DB_PORT/hrms_plaridel
HOST=0.0.0.0
PORT=3000
TRUST_PROXY=1
HRMS_TIMEZONE=Asia/Manila
JWT_SECRET=long_random_secret
JWT_REFRESH_SECRET=another_long_random_secret
UNISMS_API_SECRET_KEY=your_unisms_api_secret_key
```

Initialize a new database:

```bash
createdb hrms_plaridel
psql -d hrms_plaridel -f scripts/init-schema.sql
psql -d hrms_plaridel -f scripts/rsp-storage-attachment-policy.sql
```

Start the API:

```bash
npm run dev
```

Health checks:

```bash
curl http://localhost:3000/health
curl http://localhost:3000/health/db
```

See [backend/README.md](backend/README.md) for endpoint details and backend-specific setup notes.

## Production Architecture

The current live deployment uses a hybrid Kamatera VPS + office PC setup:

```text
Users/mobile/web
-> VPS Nginx HTTPS
-> Tailscale private tunnel
-> office Node backend
-> office PostgreSQL
```

In this architecture:

- The VPS exposes public HTTPS through Nginx.
- The office PC runs the live Node backend and PostgreSQL database.
- Tailscale privately connects the VPS to the office backend.
- PostgreSQL and backend port `3000` are not exposed publicly.
- Mobile release builds should use `https://YOUR_DOMAIN` as `API_BASE_URL`.

Use [docs/KAMATERA_VPN_DEPLOYMENT.md](docs/KAMATERA_VPN_DEPLOYMENT.md) for the full deployment and rollback guide.

## Useful Docs

- [Kamatera VPS deployment](docs/KAMATERA_VPN_DEPLOYMENT.md)
- [Hybrid health checks](docs/HRMS_HYBRID_HEALTH_CHECKS.md)
- [Security checks](docs/HRMS_SECURITY_CHECKS.md)
- [Backend README](backend/README.md)

## Common Commands

```bash
# Flutter
cd frontend
flutter pub get
flutter run

# Backend
cd ../backend
npm install
npm run dev

# Backend production start
npm start
```
