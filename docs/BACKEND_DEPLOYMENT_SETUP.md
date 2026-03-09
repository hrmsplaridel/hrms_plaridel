# Backend Deployment Setup

Step-by-step setup to run the HRMS backend for deployment (same machine or LAN). Use this when you are ready to deploy.

---

## Prerequisites

- **Node.js** 18 or newer  
- **PostgreSQL** installed and running  
- (For LAN) All devices on the same network (same router)

---

## 1. Install dependencies

On the machine that will run the backend:

```bash
cd backend
npm install
```

---

## 2. Environment configuration

Create your `.env` from the example (do this only on the server machine; never commit `.env`):

```bash
cp .env.example .env
```

Edit `.env` and set at least:

| Variable        | Required | Example / notes |
|-----------------|----------|------------------|
| `DATABASE_URL`  | Yes      | `postgresql://USER:PASSWORD@localhost:5432/hrms_plaridel` |
| `JWT_SECRET`    | Yes      | Long random string (see below) |
| `HOST`          | For LAN  | `0.0.0.0` so other devices can connect |
| `PORT`          | Optional | `3000` (default) |

**Generate a safe JWT secret:**

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Put the output in `.env` as `JWT_SECRET=...`.

**Example `.env` for deployment:**

```env
DATABASE_URL=postgresql://postgres:yourpassword@localhost:5432/hrms_plaridel
JWT_SECRET=<paste the 64-char hex from above>
HOST=0.0.0.0
PORT=3000
```

---

## 3. Database setup

Create the database (if it does not exist):

```bash
# Option A: createdb (if in PATH)
createdb hrms_plaridel

# Option B: psql
psql -U postgres -c "CREATE DATABASE hrms_plaridel;"
```

Apply the main schema:

```bash
psql -d hrms_plaridel -f scripts/init-schema.sql
```

If you use other modules (e.g. leave balances, docutracker), run their scripts as needed:

- `scripts/init-schema-leave-balances.sql`
- `scripts/init-schema-docutracker.sql`
- `scripts/init-schema-ld.sql`
- `scripts/init-schema-rsp.sql`

---

## 4. Run the backend

**Development (auto-restart on file changes):**

```bash
npm run dev
```

**Production (no auto-restart):**

```bash
npm start
```

You should see: `HRMS API listening on http://0.0.0.0:3000` (or `http://127.0.0.1:3000` if you set `HOST=127.0.0.1`).

**Quick health check:**

- Browser or `curl`: `http://localhost:3000/health`
- DB check: `http://localhost:3000/health/db`

---

## 5. Deployment checklist (LAN)

If other devices on the network will use the app:

| Step | Action |
|------|--------|
| 1 | In `.env`, set `HOST=0.0.0.0` (or omit; it defaults to 0.0.0.0). |
| 2 | Allow port **3000** in the server’s firewall (see [Firewall](#6-firewall) below). |
| 3 | Find the server’s LAN IP (e.g. `ipconfig` on Windows, `ip addr` on Linux). Example: `192.168.1.100`. |
| 4 | On each client, point the app to `http://<SERVER_IP>:3000` (e.g. via `config/api_base_url.txt` and your run script). |

---

## 6. Firewall

If clients cannot connect, open TCP port **3000** on the machine running the backend.

**Windows (PowerShell as Administrator):**

```powershell
New-NetFirewallRule -DisplayName "HRMS API (port 3000)" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow
```

**Linux (ufw):**

```bash
sudo ufw allow 3000
sudo ufw reload
```

**macOS:** System Preferences → Security & Privacy → Firewall → Firewall Options → allow Node (or your Node app).

---

## 7. Keep the backend running (optional)

For a real deployment you usually want the backend to keep running after you close the terminal.

**Option A – PM2 (Node process manager)**

```bash
npm install -g pm2
pm2 start src/index.js --name hrms-api
pm2 save
pm2 startup   # enable start on boot (follow the command it prints)
```

**Option B – Windows (run in background)**

- Use `start /B node src/index.js` in a script, or
- Run `node src/index.js` in a separate terminal or as a scheduled task.

**Option C – Linux systemd**

Create a unit file (e.g. `/etc/systemd/system/hrms-api.service`) that runs `node /path/to/backend/src/index.js` with the correct `WorkingDirectory` and `Environment`, then:

```bash
sudo systemctl enable hrms-api
sudo systemctl start hrms-api
```

---

## 8. Summary

| Task              | Command / action |
|-------------------|------------------|
| Install deps      | `cd backend && npm install` |
| Configure         | `cp .env.example .env` then set `DATABASE_URL`, `JWT_SECRET`, `HOST=0.0.0.0` |
| Create DB         | `createdb hrms_plaridel` or `psql -U postgres -c "CREATE DATABASE hrms_plaridel;"` |
| Init schema       | `psql -d hrms_plaridel -f scripts/init-schema.sql` |
| Run server        | `npm run dev` or `npm start` |
| LAN access        | Firewall allow TCP 3000; clients use `http://<SERVER_IP>:3000` |

For Flutter client configuration (API base URL, run scripts), see [LAN_DEPLOYMENT.md](LAN_DEPLOYMENT.md).
