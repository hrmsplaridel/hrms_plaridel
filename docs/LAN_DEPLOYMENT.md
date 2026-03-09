# LAN Deployment Setup

Run the HRMS backend on one machine (server) and connect Flutter clients from other devices on the same network (router). **One config file** controls the API URL so you can easily switch between localhost and LAN.

---

## Architecture

- **Server machine**: Hosts backend (Node.js/Express) and PostgreSQL
- **Client devices**: Run the Flutter app (web, Android, iOS, desktop)
- **API URL**: Configured in a single file `config/api_base_url.txt`

---

## 1. Server Setup

On the machine that will host the backend and database:

### Start PostgreSQL

Ensure PostgreSQL is running and the database exists:

```bash
psql -U postgres -c "CREATE DATABASE hrms_plaridel;"  # if needed
```

### Configure Backend

```bash
cd backend
cp .env.example .env
# Edit .env: set DATABASE_URL, JWT_SECRET
```

Ensure `HOST=0.0.0.0` in `.env` (or omit it; it defaults to 0.0.0.0). This lets the server accept connections from other devices.

```env
HOST=0.0.0.0
PORT=3000
```

### Start the Backend

```bash
npm start
# or: npm run dev
```

You should see: `HRMS API listening on http://0.0.0.0:3000`

### Find Your Server's LAN IP

- **Windows**: `ipconfig` → look for "IPv4 Address" (e.g. `192.168.1.100`)
- **macOS/Linux**: `ip addr` or `ifconfig` → look for `192.168.x.x`

Use this IP for client configuration.

---

## 2. Client Setup (Flutter)

### Single Config File

Edit **one file** to switch between localhost and LAN:

| File | Purpose |
|------|---------|
| `config/api_base_url.txt` | API base URL (one line) |

**Examples:**

| Scenario | Contents of `config/api_base_url.txt` |
|----------|--------------------------------------|
| Dev on same machine as backend | `http://localhost:3000` |
| Dev on another device, backend on server | `http://192.168.1.100:3000` |

### Run the Flutter App

Use the run script so it reads from the config file:

**Windows:**
```cmd
scripts\run_flutter.bat
```

**macOS/Linux:**
```bash
chmod +x scripts/run_flutter.sh
./scripts/run_flutter.sh
```

To target a specific platform:
```cmd
scripts\run_flutter.bat -d chrome
scripts\run_flutter.bat -d windows
```

**Manual run** (if you prefer):
```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:3000
```

---

## 3. Quick Reference

| Task | Action |
|------|--------|
| Switch to localhost | Edit `config/api_base_url.txt` → `http://localhost:3000` |
| Switch to LAN | Edit `config/api_base_url.txt` → `http://YOUR_SERVER_IP:3000` |
| Backend not reachable from LAN | Ensure backend `HOST=0.0.0.0` and firewall allows port 3000 |
| CORS issues | Backend uses `cors()` with no origin restriction (allows any client) |

---

## 4. Firewall

If clients cannot connect, allow inbound TCP on port 3000.

### Windows Firewall: Add inbound rule for port 3000

**Option A – PowerShell (run as Administrator)**

```powershell
New-NetFirewallRule -DisplayName "HRMS API (port 3000)" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow
```

**Option B – GUI**

1. Press **Win**, type **Windows Defender Firewall**, open **Windows Defender Firewall with Advanced Security**.
2. In the left pane, click **Inbound Rules**.
3. In the right pane, click **New Rule…**.
4. Select **Port** → Next.
5. Select **TCP**, enter **3000** under “Specific local ports” → Next.
6. Select **Allow the connection** → Next.
7. Leave all profiles (Domain, Private, Public) checked if you want LAN access on any network → Next.
8. Name the rule (e.g. **HRMS API port 3000**) → Finish.

---

**Other platforms**

- **Linux (ufw)**: `sudo ufw allow 3000` then `sudo ufw reload`
- **macOS**: System Preferences → Security & Privacy → Firewall → Firewall Options → allow Node (or “Allow incoming connections” for your Node app)
