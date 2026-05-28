# HRMS Plaridel Kamatera VPS hosting guide sheet

This guide covers two supported deployments where PostgreSQL remains on the office LAN as the single source of truth. Remote users call HTTPS on the VPS. Private traffic between the VPS and office uses Tailscale.

Choose one architecture before following the backend/Nginx steps:

## Architecture A: VPS backend, office PostgreSQL

```text
Users/mobile/web -> VPS Nginx HTTPS -> VPS Node backend -> Tailscale -> office PostgreSQL
```

Use this when you want the API process to run on Kamatera. It is simpler for Linux/systemd management, but data-heavy screens can be slower because every SQL query crosses Tailscale.

## Architecture B: office backend, office PostgreSQL, VPS HTTPS gateway

```text
Users/mobile/web -> VPS Nginx HTTPS -> Tailscale -> office Node backend -> office PostgreSQL
```

Use this when the office database must remain the main truth and speed is the priority. The backend runs beside PostgreSQL, so SQL queries are local. The VPS only terminates public HTTPS and proxies to the office backend over Tailscale.

If you are unsure, start with Architecture A. If data loading over VPN is too slow and the office PC can stay online 24/7, switch to Architecture B.

Use these placeholders:

- `YOUR_SERVER_IP`: your VPS public IP, example `79.108.225.134`
- `YOUR_DOMAIN`: your API domain, example `hrms.example.gov.ph`
- `YOUR_REPO_URL`: your Git repository URL (GitHub or other)
- `YOUR_OFFICE_TAILSCALE_IP`: the office PostgreSQL host Tailscale address (Tailscale admin → Machines, or `tailscale ip -4` on that PC), example `100.88.123.26`
- `YOUR_VPS_TAILSCALE_IP`: the VPS Tailscale address (for `pg_hba.conf` and optional firewall allow rules), example `100.108.196.109`
- `YOUR_DB_USER`: PostgreSQL role the API uses, often `postgres` on a dev/office install or a dedicated role such as `hrms_api`
- `YOUR_DB_PASSWORD`: that role password (avoid raw `@` in passwords or encode as `%40` inside URLs)
- `YOUR_DB_PORT`: PostgreSQL port on the office host, default `5432`; use `5433` if you installed PostgreSQL 18 alongside an older version on `5432`
- `YOUR_EMAIL`: email for Let's Encrypt certificate notices
- `YOUR_OFFICE_BACKEND_URL`: office backend URL over Tailscale for Architecture B, example `http://100.88.123.26:3000`

Example names you can copy or rename:

- VPS Linux user: `deploy`
- Project folder: `/opt/hrms-plaridel`
- Backend folder: `/opt/hrms-plaridel/backend`
- Flutter web folder on VPS: `/var/www/hrms`
- systemd service: `hrms-api`
- Backend local bind: `127.0.0.1:3000`
- Office backend bind for Architecture B: `0.0.0.0:3000` on the office PC, reachable from the VPS only over Tailscale/firewall allow rules
- Public API root: `https://YOUR_DOMAIN`

Important layout:

- PostgreSQL runs in the office, not on the VPS.
- Do not expose PostgreSQL (`5432`, `5433`, or any custom port) to the public internet. Only the VPS reaches it over Tailscale.
- Do not expose the Node backend port (`3000`) to the public internet. For Architecture B, only the VPS Tailscale IP should be allowed to reach office port `3000`.
- Tailscale runs on the Kamatera VPS and on the Windows PC that hosts PostgreSQL (machine name in Tailscale is often something like `earlbullet`). Install Tailscale on your dev laptop only if that laptop is not the DB host and you want admin access to the tailnet.
- Node.js on the VPS (API runtime) and `postgresql-client` on the VPS (`psql` for tests) do not need to match the PostgreSQL server major version on the office PC. PostgreSQL 18 on the office with client tools 16 on the VPS is fine.

**Deployment order, Architecture A:** VPS basics (sections 1–5) → Node.js (6) → Tailscale VPS (7) → Tailscale office PC (8) → PostgreSQL config on office (9) → `psql` test from VPS (10) → clone app on VPS (11+) → DNS/HTTPS when Nginx is ready (16–17). DNS A records can point at the VPS before steps 16–17; Certbot needs Nginx on port 80 first.

**Deployment order, Architecture B:** VPS basics (sections 1–5) → Tailscale VPS (7) → Tailscale office PC (8) → PostgreSQL config on office (9) → run backend on office PC (14.2) → test office backend from VPS (14.3) → configure VPS Nginx to proxy to office backend (15, Option B) → DNS/HTTPS (16–17). You do not need the VPS `hrms-api` systemd service for live traffic in Architecture B.

---

# 1. Kamatera account and VPS creation

## 1.1 Login to Kamatera

1. Open Kamatera in your browser.
2. Log in to the client area or cloud console.
3. Go to Servers or Create New Server.

## 1.2 Choose region

For Philippines users, choose:

- Singapore

Reason:

- Lower latency from PH than US or EU defaults
- Reasonable default for employee mobile and web traffic

## 1.3 Server type

Choose:

- General Purpose

Do not choose Dedicated unless you need sustained high CPU or compliance features that require it.

## 1.4 Server specs

Recommended starter specs:

- 2 vCPU
- 4 GB RAM
- 50 GB to 60 GB SSD
- Ubuntu Server 22.04 LTS or 24.04 LTS
- Public IP enabled

Backups:

- Enable Kamatera provider snapshots when production traffic starts.
- Keep the office Windows Task Scheduler backup as the primary backup when the office PostgreSQL database is the source of truth.
- Use a VPS cron or systemd timer backup for VPS-owned data and optional offsite copies. See section 14.4.

## 1.5 Advanced configuration

Use:

- Name or hostname: `hrms-plaridel` or `hrms-sg-01`
- Public network: on
- Private local network: off for this single-VPS pattern

The public IP is assigned after creation. Do not use the IP as the hostname in Linux.

---

# 2. First SSH login

Run on your local Windows PowerShell:

```powershell
ssh root@YOUR_SERVER_IP
```

Accept the host key if prompted.

If Windows reports old host key mismatch:

```powershell
ssh-keygen -R YOUR_SERVER_IP
ssh root@YOUR_SERVER_IP
```

---

# 3. Create deploy user

Run on the VPS while logged in as root:

```bash
adduser deploy
usermod -aG sudo deploy
id deploy
```

During adduser:

- Set a password for deploy
- Optional fields can be left blank with Enter
- Confirm with Y

Generate an SSH key on local Windows if you do not have one:

```powershell
ssh-keygen -t ed25519 -C "admin@hrms"
```

Copy the public key to deploy:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh deploy@YOUR_SERVER_IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

Test:

```powershell
ssh deploy@YOUR_SERVER_IP
sudo whoami
```

Expected:

```text
root
```

Prefer SSH as deploy for daily work, not root.

---

# 4. SSH hardening

Only after deploy login works.

On the VPS as deploy:

```bash
sudo nano /etc/ssh/sshd_config
```

Set or uncomment these lines without a leading hash:

```text
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
```

Save in nano:

```text
Ctrl + O
Enter
Ctrl + X
```

Validate and restart:

```bash
sudo sshd -t
sudo systemctl restart ssh
```

Open a second terminal and test deploy login before closing the root session.

---

# 5. Firewall with UFW

Run on the VPS as deploy:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Do not allow PostgreSQL ports on the public internet. The database stays in the office. The VPS only needs SSH, HTTP, and HTTPS for clients.

If you temporarily opened the Node port for testing, remove it after Nginx works:

```bash
sudo ufw delete allow 3000/tcp
sudo ufw status
```

## 5.1 Optional: apply Ubuntu updates and reboot

After first login, Ubuntu may report packages that can be upgraded and sometimes `*** System restart required ***`.

```bash
sudo apt update
sudo apt list --upgradable
sudo apt upgrade -y
```

If reboot is required:

```bash
test -f /var/run/reboot-required && echo "Reboot needed" || echo "No reboot needed"
sudo reboot
```

SSH back in as `deploy`, then continue with section 6. Rebooting before Tailscale or PostgreSQL testing is fine and often recommended after kernel updates.

---

# 6. Install Node.js LTS

Use **Node.js 22 or 24** on the VPS (Active or Maintenance LTS). Do **not** install Node 20 on new deployments in 2026; it is end-of-life.

Your development PC can stay on Node 22 while the VPS uses 24; they do not have to match exactly.

Run on the VPS:

```bash
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs build-essential
node -v
npm -v
```

Expected: `node -v` shows **v24.x** (or v22.x if you deliberately chose `setup_22.x`).

`build-essential` is required so npm packages with native code (for example `bcrypt`) compile during `npm install`.

### 6.1 Node on your Windows dev PC (optional)

Updating Node on the PC is separate from the VPS. If the API already runs locally, you can keep Node 22 until you choose to upgrade. To align with the VPS later, install Node 24 LTS from https://nodejs.org or run `winget install OpenJS.NodeJS.LTS` (use the same Tailscale/Google account only for Tailscale, not for Node).

Installing Node on Windows does **not** change files in your project folder; after a major Node upgrade, refresh dependencies if needed:

```powershell
cd C:\path\to\hrms_plaridel\backend
Remove-Item -Recurse -Force node_modules -ErrorAction SilentlyContinue
npm install
```

---

# 7. Install Tailscale on the VPS

Run on the VPS:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

The command prints a URL like `https://login.tailscale.com/a/...`. Open it on your PC (not on the VPS), sign in with **Google or GitHub**, and approve adding the machine (hostname often `hrmsplaridel`).

After login, confirm on the VPS:

```bash
tailscale ip -4
tailscale status
```

Save the IPv4 address as `YOUR_VPS_TAILSCALE_IP` (example `100.108.196.109`). You need it for `pg_hba.conf` on the office PC.

---

# 8. Install Tailscale on the office PostgreSQL host

On the **Windows PC where PostgreSQL actually runs** (not only your dev laptop unless that laptop hosts the database):

1. Install Tailscale from https://tailscale.com/download (Windows).
2. Sign in with the **same account** you used on the VPS (Google or GitHub is fine; use the same provider and email on both).
3. When the installer finishes, you can click **Close** on the “Connect to your tailnet devices” dialog.
4. Note this PC’s Tailscale IP (`100.x.x.x`) from the system tray Tailscale icon or https://login.tailscale.com/admin/machines → Machines.

Save it as `YOUR_OFFICE_TAILSCALE_IP` (example `100.88.123.26`, hostname example `earlbullet`).

From the VPS, test connectivity (high latency from PH to Singapore is normal):

```bash
ping -c 4 YOUR_OFFICE_TAILSCALE_IP
tailscale status
```

You should see the office machine as **active** (ideally `direct`, not only relay).

---

# 9. Office PostgreSQL listen addresses and authentication

PostgreSQL must accept TCP connections on the office machine. The VPS connects to `YOUR_OFFICE_TAILSCALE_IP`:`YOUR_DB_PORT`, not to `localhost` on the VPS.

### 9.1 Find your port and config folder (Windows)

Default PostgreSQL uses port **5432**. If you installed **PostgreSQL 18** alongside an older version, it may use **5433** (check in pgAdmin, or `postgresql.conf`).

Typical data directory on Windows:

```text
C:\Program Files\PostgreSQL\18\data\
```

Files to edit:

```text
postgresql.conf
pg_hba.conf
```

Find the Windows service name in `services.msc` (example `postgresql-x64-18`).

### 9.2 `postgresql.conf` (Windows and Linux)

Open `postgresql.conf` as Administrator and set:

```conf
listen_addresses = '*'
port = 5433
```

Use your real port (`5432` or `5433`). `listen_addresses = '*'` is normal when access is restricted by `pg_hba.conf` and the office firewall, not by port-forwarding from the internet.

Save the file, then **restart** the PostgreSQL Windows service (Services → postgresql-x64-… → Restart). On Linux: `sudo systemctl restart postgresql`.

### 9.3 `pg_hba.conf` — allow only the VPS Tailscale IP

Open `pg_hba.conf` in the same `data` folder (Notepad **as Administrator**, File → Open → show **All files**).

In the `# IPv4 local connections:` section, **keep** existing lines such as `127.0.0.1`. Add **one new line** below them (tabs or spaces are fine):

```text
host    hrms_plaridel    YOUR_DB_USER    YOUR_VPS_TAILSCALE_IP/32    scram-sha-256
```

Example if user is `postgres`, VPS Tailscale IP is `100.108.196.109`:

```text
host    hrms_plaridel    postgres    100.108.196.109/32    scram-sha-256
```

- Database name must match your DB (`hrms_plaridel`).
- `YOUR_DB_USER` must match what you put in `DATABASE_URL` on the VPS.
- Using the `postgres` superuser works for small deployments; a dedicated `hrms_api` role is better for production.

Save, then **restart** the PostgreSQL service again.

### 9.4 Windows Firewall (inbound)

Allow the database port for Tailscale/private networks so the VPS can connect.

**Windows Defender Firewall with Advanced Security** → **Inbound Rules** → **New Rule**:

1. Rule type: **Port**
2. TCP, specific local ports: **YOUR_DB_PORT** (example `5433`)
3. Action: **Allow the connection**
4. Profile: check **Domain**, **Private**, and **Public** (or at least **Private** while testing)
5. Name: example `PostgreSQL YOUR_DB_PORT Tailscale`

Do **not** set up router port-forwarding of 5432/5433 to the internet.

### 9.5 Linux office server (if applicable)

Same logic: `listen_addresses`, `port` in `postgresql.conf`, `pg_hba.conf` line with `YOUR_VPS_TAILSCALE_IP/32`, `ufw` or firewalld allowing the port from Tailscale only if you use host firewall rules.

### 9.6 Local test on the office PC

```powershell
psql -U YOUR_DB_USER -p YOUR_DB_PORT -d hrms_plaridel -c "SELECT 1;"
```

---

# 10. Test database connectivity from the VPS

Install the PostgreSQL **client** on the VPS (provides `psql`; version 16 client against PostgreSQL 18 server is OK):

```bash
sudo apt install -y postgresql-client
```

If you see `Command 'psql' not found`, the package is not installed yet; run the command above.

Test from the VPS to the office over Tailscale (use **your** port and password):

```bash
    psql "postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@YOUR_OFFICE_TAILSCALE_IP:YOUR_DB_PORT/hrms_plaridel" -c "SELECT 1;"
```

Example with port `5433`:

```bash
psql "postgresql://postgres:YOUR_DB_PASSWORD@100.88.123.26:5433/hrms_plaridel" -c "SELECT 1;"
```

Success looks like:

```text
 ?column?
----------
        1
(1 row)
```

If this fails, fix Tailscale on both sides, `listen_addresses`, `port`, `pg_hba.conf`, Windows Firewall, user/password, or database name before continuing.

| Symptom | Likely fix |
|--------|------------|
| `psql: command not found` | Run `sudo apt install -y postgresql-client` on the VPS |
| `Connection refused` | PostgreSQL not listening on that port; wrong `port` in `postgresql.conf`; service stopped |
| `no pg_hba.conf entry` | Add/fix `pg_hba` line; restart PostgreSQL |
| `password authentication failed` | Wrong user/password in URL |
| Timeout | Windows Firewall blocking `YOUR_DB_PORT`; Tailscale offline on office PC |

---

# 11. Clone the HRMS project on the VPS

Run on the VPS:

```bash
sudo mkdir -p /opt/hrms-plaridel
sudo chown -R deploy:deploy /opt/hrms-plaridel
cd /opt/hrms-plaridel
git clone YOUR_REPO_URL .
ls -la
```

Expected top-level entries include:

```text
backend
lib
pubspec.yaml
```

For private Git over HTTPS, use a GitHub personal access token as the password when Git prompts.

---

# 12. Backend environment file on VPS (Architecture A)

Use this section when the Node backend runs on the VPS.

For Architecture B, the live backend `.env` is on the office PC instead. See section 14.2. You may still keep a VPS `.env` for tests or rollback, but VPS Nginx will proxy to the office backend and the VPS `hrms-api` service is not required for live traffic.

Path:

```text
/opt/hrms-plaridel/backend/.env
```

Generate JWT secrets on the VPS:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Run twice and use two different outputs for JWT_SECRET and JWT_REFRESH_SECRET.

Create the file:

```bash
cd /opt/hrms-plaridel/backend
nano .env
```

Minimal content:

```env
DATABASE_URL=postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@YOUR_OFFICE_TAILSCALE_IP:YOUR_DB_PORT/hrms_plaridel
JWT_SECRET=PASTE_FIRST_HEX_HERE
JWT_REFRESH_SECRET=PASTE_SECOND_HEX_HERE
HOST=127.0.0.1
PORT=3000
TRUST_PROXY=1
HRMS_TIMEZONE=Asia/Manila
```

Notes:

- HOST 127.0.0.1 means only Nginx on the same machine reaches Node directly. Clients never hit 3000 on the public IP.
- TRUST_PROXY=1 matches Express sitting behind Nginx with X-Forwarded headers.
- Optional if VPN latency causes timeouts:

```env
PG_CONNECTION_TIMEOUT_MS=15000
```

Optional Flutter web production lock:

```env
CORS_ORIGINS=https://YOUR_DOMAIN
```

Optional biometric punch ingestion from the office sync script must match the same key:

```env
BIO_SYNC_API_KEY=generate_a_long_random_secret
```

Secure the file:

```bash
chmod 600 .env
```

---

# 13. Install backend dependencies and smoke test on VPS (Architecture A)

Run on the VPS:

```bash
cd /opt/hrms-plaridel/backend
npm install
```

Temporary public test (optional, only if you opened port 3000 in UFW earlier):

```bash
HOST=0.0.0.0 PORT=3000 node src/index.js
```

From a browser or curl:

```text
http://YOUR_SERVER_IP:3000/health
http://YOUR_SERVER_IP:3000/health/db
```

Stop with Ctrl+C.

Prefer testing through localhost after systemd binds to 127.0.0.1:

```bash
cd /opt/hrms-plaridel/backend
HOST=127.0.0.1 PORT=3000 node src/index.js
```

Then in another SSH session:

```bash
curl -s http://127.0.0.1:3000/health/db
```

---

# 14. systemd service for the HRMS API on VPS (Architecture A)

Run on the VPS:

```bash
sudo nano /etc/systemd/system/hrms-api.service
```

Content:

```ini
[Unit]
Description=HRMS Plaridel Node API
After=network.target

[Service]
User=deploy
Group=deploy
WorkingDirectory=/opt/hrms-plaridel/backend
EnvironmentFile=/opt/hrms-plaridel/backend/.env
ExecStart=/usr/bin/node src/index.js
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now hrms-api
sudo systemctl status hrms-api --no-pager
curl -s http://127.0.0.1:3000/health/db
```

Logs:

```bash
sudo journalctl -u hrms-api -n 80 --no-pager
```

## 14.2 Office backend setup (Architecture B)

Use this section when the office PC is the live backend host and the VPS only proxies HTTPS traffic to it.

On the office PC, keep the project at your normal local path, for example:

```text
C:\Users\Admin\hrms_plaridel
```

Install backend dependencies if needed:

```powershell
cd C:\Users\Admin\hrms_plaridel\backend
npm install
```

Office backend `.env`:

```env
DATABASE_URL=postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@localhost:YOUR_DB_PORT/hrms_plaridel
HOST=0.0.0.0
PORT=3000
TRUST_PROXY=1
HRMS_TIMEZONE=Asia/Manila

JWT_SECRET=SAME_VALUE_ON_OFFICE_AND_VPS
JWT_REFRESH_SECRET=SAME_VALUE_ON_OFFICE_AND_VPS
JWT_EXPIRATION=15m
JWT_REFRESH_EXPIRATION=30d

BIO_SYNC_API_KEY=SAME_VALUE_USED_BY_ZKTECO_SYNC
HRMS_API_URL=http://localhost:3000
ZK_POLL_INTERVAL=10
ZK_TIMEZONE_OFFSET=+08:00
```

Important:

- `DATABASE_URL` uses `localhost` because PostgreSQL is on the same office PC.
- `HOST=0.0.0.0` allows the VPS to reach the office backend over Tailscale.
- `JWT_SECRET` and `JWT_REFRESH_SECRET` should match any VPS backend values during migration. If they differ, users may need to log in again after switching traffic.
- `HRMS_API_URL=http://localhost:3000` is for the office biometric sync script when it runs on the same PC as the office backend.

Start the office backend:

```powershell
cd C:\Users\Admin\hrms_plaridel\backend
npm start
```

Test locally on the office PC:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health/db
```

Allow only the VPS Tailscale IP to reach the office backend port:

```powershell
New-NetFirewallRule `
  -DisplayName "HRMS Office API from VPS Tailscale" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort 3000 `
  -RemoteAddress YOUR_VPS_TAILSCALE_IP `
  -Profile Any
```

For testing from phones on the same office Wi-Fi, you may also allow the LAN profile temporarily:

```powershell
cd C:\Users\Admin\hrms_plaridel
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\allow-backend-firewall-windows.ps1
```

Do not port-forward office port `3000` on the router.

### Optional: run office backend automatically after reboot

For quick operations, keep a visible PowerShell running `npm start`. For production-like use, run it with a service manager such as NSSM or a Windows Task Scheduler task.

Simple Task Scheduler pattern:

- Trigger: At startup
- User: the Windows account that owns the project
- Action/program: `powershell.exe`
- Arguments:

```text
-NoProfile -ExecutionPolicy Bypass -Command "cd C:\Users\Admin\hrms_plaridel\backend; npm start"
```

If using Task Scheduler, test by rebooting the office PC and checking:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health/db
```

## 14.3 Test office backend from the VPS (Architecture B)

On the office PC, get its Tailscale IP:

```powershell
tailscale ip -4
```

On the VPS, test:

```bash
tailscale ping YOUR_OFFICE_TAILSCALE_IP
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health/db
```

Expected:

```json
{"ok":true,"message":"HRMS API is running"}
```

and `/health/db` should report `PostgreSQL connection OK`.

If `curl http://YOUR_OFFICE_TAILSCALE_IP:3000/health` fails:

- Confirm the office backend is running.
- Confirm office `.env` has `HOST=0.0.0.0`.
- Confirm Windows Firewall allows `YOUR_VPS_TAILSCALE_IP` to TCP `3000`.
- Confirm Tailscale is connected on both machines.

## 14.4 VPS backup scheduler

Use this only for data that lives on the VPS, or as a secondary/offsite backup through Tailscale. If PostgreSQL on the office Windows server is the source of truth, the primary backup must still run on that Windows server with Task Scheduler.

Backups contain HR records and attachments. Keep `/var/backups/hrms-plaridel` locked down and use encrypted storage for any copy that leaves the server.

Install PostgreSQL client tools so the VPS can run `pg_dump` when needed:

```bash
sudo apt update
sudo apt install -y postgresql-client tar gzip
```

Install the repo backup helper:

```bash
sudo install -m 750 -o root -g root /opt/hrms-plaridel/scripts/backup-vps-linux.sh /usr/local/sbin/hrms-vps-backup
sudo mkdir -p /var/backups/hrms-plaridel
sudo chown root:root /var/backups/hrms-plaridel
sudo chmod 700 /var/backups/hrms-plaridel
```

The script reads `/opt/hrms-plaridel/backend/.env` for `DATABASE_URL` and `UPLOAD_DIR`. It creates:

```text
/var/backups/hrms-plaridel/daily
/var/backups/hrms-plaridel/weekly
/var/backups/hrms-plaridel/monthly
/var/backups/hrms-plaridel/logs
```

Default retention:

```text
Daily snapshots: keep 7
Weekly snapshots: keep 4
Monthly snapshots: keep 12
```

Manual test:

```bash
sudo /usr/local/sbin/hrms-vps-backup
sudo ls -lah /var/backups/hrms-plaridel/daily
```

If the VPS should only back up local uploads/config and should not run `pg_dump` over Tailscale, use:

```bash
sudo SKIP_DB=1 /usr/local/sbin/hrms-vps-backup
```

If you have a mounted offsite folder, set `HRMS_OFFSITE_BACKUP_ROOT`:

```bash
sudo HRMS_OFFSITE_BACKUP_ROOT=/mnt/hrms-offsite /usr/local/sbin/hrms-vps-backup
```

### Option A: systemd timer, recommended on Ubuntu

Create the service:

```bash
sudo nano /etc/systemd/system/hrms-vps-backup.service
```

Content:

```ini
[Unit]
Description=HRMS Plaridel VPS backup

[Service]
Type=oneshot
Environment=HRMS_BACKUP_ROOT=/var/backups/hrms-plaridel
ExecStart=/usr/local/sbin/hrms-vps-backup
```

Create the timer:

```bash
sudo nano /etc/systemd/system/hrms-vps-backup.timer
```

Content:

```ini
[Unit]
Description=Run HRMS Plaridel VPS backup daily

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
Unit=hrms-vps-backup.service

[Install]
WantedBy=timers.target
```

Enable and verify:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now hrms-vps-backup.timer
systemctl list-timers --all | grep hrms-vps-backup
sudo systemctl start hrms-vps-backup.service
sudo journalctl -u hrms-vps-backup.service -n 80 --no-pager
```

### Option B: cron

Use cron if you prefer the classic scheduler:

```bash
sudo crontab -e
```

Add:

```cron
30 2 * * * HRMS_BACKUP_ROOT=/var/backups/hrms-plaridel /usr/local/sbin/hrms-vps-backup >> /var/backups/hrms-plaridel/logs/cron.log 2>&1
```

To skip database dumps from the VPS and back up only VPS local files:

```cron
30 2 * * * HRMS_BACKUP_ROOT=/var/backups/hrms-plaridel SKIP_DB=1 /usr/local/sbin/hrms-vps-backup >> /var/backups/hrms-plaridel/logs/cron.log 2>&1
```

Check results:

```bash
sudo tail -n 80 /var/backups/hrms-plaridel/logs/cron.log
sudo find /var/backups/hrms-plaridel -maxdepth 2 -type d | sort
```

### Restore test

At least monthly, restore one dump into a test database:

```bash
createdb hrms_restore_test
pg_restore -d hrms_restore_test /var/backups/hrms-plaridel/daily/YYYYMMDD_HHMMSS/database.dump
```

Do not overwrite production during restore tests. Use a separate restore database.

---

# 15. Install Nginx

Run on the VPS:

```bash
sudo apt update
sudo apt install -y nginx
```

Create site:

```bash
sudo nano /etc/nginx/sites-available/hrms-api
```

HTTP-only first (Certbot will upgrade later).

## Option A: proxy to VPS backend

Use this when the Node backend runs as `hrms-api` on the VPS:

```nginx
server {
    listen 80;
    listen [::]:80;

    server_name YOUR_DOMAIN www.YOUR_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Option B: proxy to office backend over Tailscale

Use this when the Node backend runs on the office PC beside PostgreSQL. Replace `YOUR_OFFICE_TAILSCALE_IP` with the office PC's Tailscale IP.

```nginx
server {
    listen 80;
    listen [::]:80;

    server_name YOUR_DOMAIN www.YOUR_DOMAIN;

    location / {
        proxy_pass http://YOUR_OFFICE_TAILSCALE_IP:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 10s;
        proxy_send_timeout 120s;
        proxy_read_timeout 120s;
    }
}
```

For Architecture B, verify the target before reloading Nginx:

```bash
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health/db
```

Enable:

```bash
sudo ln -sf /etc/nginx/sites-available/hrms-api /etc/nginx/sites-enabled/hrms-api
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

After enabling Architecture B, verify public HTTPS reaches the office backend:

```bash
curl -s https://YOUR_DOMAIN/health
curl -s https://YOUR_DOMAIN/health/db
```

If these work, you can stop the VPS backend service to avoid confusion:

```bash
sudo systemctl stop hrms-api
sudo systemctl disable hrms-api
```

Only stop `hrms-api` after `https://YOUR_DOMAIN/health/db` works through Nginx. Keep the project on the VPS for Nginx config, static web hosting, scripts, or rollback.

---

# 16. Domain DNS

You can create these records **before** finishing sections 11–15. The domain can point to the VPS while you still configure Tailscale and PostgreSQL. HTTPS (section 17) only works after Nginx listens on port 80.

In your DNS provider, add:

```text
Type: A
Name: @
Value: YOUR_SERVER_IP
TTL: 600
```

If you use www:

```text
Type: A
Name: www
Value: YOUR_SERVER_IP
TTL: 600
```

Check from Windows:

```powershell
nslookup YOUR_DOMAIN
```

The `Server:` line in `nslookup` may show your router (`fe80::1`); that is normal. What matters is that the **Address** for your hostname is `YOUR_SERVER_IP`.

---

# 17. HTTPS with Certbot

Run on the VPS:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d YOUR_DOMAIN -d www.YOUR_DOMAIN
```

Follow prompts for email and terms. Choose redirect HTTP to HTTPS when asked.

Verify:

```text
https://YOUR_DOMAIN/health/db
```

---

# 18. Nginx notes for Flutter web on the same domain

If you later host Flutter web static files on this VPS under the same hostname, add a root and split locations so `/` serves web and API paths proxy to Node. In Architecture A, API paths proxy to `127.0.0.1:3000`. In Architecture B, API paths proxy to `http://YOUR_OFFICE_TAILSCALE_IP:3000`.

- `location /api/` proxies to Node if your app used an `/api` prefix (this HRMS backend mounts auth at `/auth` and `/api/...` at paths like `/api/employees`; adjust to match your chosen URL layout).

This repository expects the API at the origin root for typical Flutter config (`ApiConfig.baseUrl` = `https://YOUR_DOMAIN`). In that case the config from section 15 with `location /` proxying to Node is enough until you add static hosting.

If you add Flutter web under `/` and need API under the same host without path prefix changes, use two server blocks or separate subdomains such as `app.YOUR_DOMAIN` and `api.YOUR_DOMAIN`. Subdomains require extra DNS A records and extra Certbot `-d` flags.

---

# 19. Prepare Flutter web hosting folder

If hosting Flutter web on the VPS:

```bash
sudo mkdir -p /var/www/hrms
sudo chown -R deploy:deploy /var/www/hrms
```

---

# 20. Build Flutter web locally

On Windows PowerShell from your project clone:

```powershell
cd C:\path\to\hrms_plaridel
flutter clean
flutter pub get
flutter build web --release --pwa-strategy=none --dart-define=API_BASE_URL=https://YOUR_DOMAIN
```

`--pwa-strategy=none` reduces stale service worker cache issues during iterative deploys.

---

# 21. Upload Flutter web to the VPS

From your PC:

```powershell
scp -r .\build\web deploy@YOUR_SERVER_IP:/tmp/hrms-web
```

On the VPS:

```bash
find /var/www/hrms -mindepth 1 -delete
cp -a /tmp/hrms-web/web/. /var/www/hrms/
rm -rf /tmp/hrms-web
sudo find /var/www/hrms -type d -exec chmod 755 {} \;
sudo find /var/www/hrms -type f -exec chmod 644 {} \;
sudo systemctl reload nginx
```

Update Nginx to serve `root /var/www/hrms` and `try_files` for SPA routing on front-end only routes; keep API paths proxying to Node. Merge carefully with your chosen URL layout.

---

# 22. Build Android APK

On Windows:

```powershell
cd C:\path\to\hrms_plaridel
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR_DOMAIN
```

APK output:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Split per ABI:

```powershell
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://YOUR_DOMAIN
```

---

# 23. Office biometric sync script

On the office machine that runs `backend/scripts/zkteco-sync-py.py`, choose the API base for your architecture.

Architecture A, VPS backend:

```env
HRMS_API_URL=https://YOUR_DOMAIN
BIO_SYNC_API_KEY=same_value_as_VPS_backend_env
```

Office pushes punches to the VPS API; the VPS writes into PostgreSQL over Tailscale to the office DB.

Architecture B, office backend:

```env
HRMS_API_URL=http://localhost:3000
BIO_SYNC_API_KEY=same_value_as_office_backend_env
```

Office sync reads the biometric clock over LAN and posts directly to the office backend, which writes to local PostgreSQL. Public users still use `https://YOUR_DOMAIN`; VPS Nginx proxies that HTTPS traffic to the same office backend over Tailscale.

---

# 24. Schema and database initialization

Run on the office PostgreSQL server or any machine that can connect with psql:

```bash
psql -U postgres -d hrms_plaridel -f /path/to/backend/scripts/init-schema.sql
```

Run extra scripts only if your deployment uses those modules, same as `backend/README.md` describes.

---

# 25. Normal update workflow

## 25.1 Backend code update, Architecture A

Push to Git from your dev machine, then on the VPS:

```bash
cd /opt/hrms-plaridel
git pull
sudo systemctl restart hrms-api
sudo systemctl status hrms-api --no-pager
curl -s http://127.0.0.1:3000/health/db
```

Run dependency installation only if `backend/package.json` or `backend/package-lock.json` changed:

```bash
cd /opt/hrms-plaridel
cd backend
npm install
```

## 25.2 Backend code update, Architecture B

Push to Git from your dev machine, then update the office PC backend:

```powershell
cd C:\Users\Admin\hrms_plaridel
git pull
```

Run dependency installation only if `backend/package.json` or `backend/package-lock.json` changed:

```powershell
cd C:\Users\Admin\hrms_plaridel\backend
npm install
```

Restart the office backend process. If you run it manually, stop the old `npm start` with `Ctrl+C`, then run:

```powershell
npm start
```

Then test on the office PC:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health/db
```

Then test from the VPS:

```bash
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health/db
curl -s https://YOUR_DOMAIN/health/db
```

For Architecture B, you usually do not need to pull backend source code on the VPS unless you also host Flutter web/static files there, keep a rollback copy, or changed Nginx/deployment docs.

## 25.3 Backend `.env` change, Architecture A

```bash
nano /opt/hrms-plaridel/backend/.env
chmod 600 /opt/hrms-plaridel/backend/.env
sudo systemctl restart hrms-api
```

## 25.4 Backend `.env` change, Architecture B

Edit the office PC file:

```powershell
notepad C:\Users\Admin\hrms_plaridel\backend\.env
```

Restart the office backend process after saving. Then verify from both sides:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health/db
```

```bash
curl -s https://YOUR_DOMAIN/health/db
```

---

# 26. Troubleshooting

## 26.1 health/db returns 503

Architecture A, VPS backend:

```bash
sudo journalctl -u hrms-api -n 100 --no-pager
curl -s http://127.0.0.1:3000/health/db
```

Test psql from VPS to office again (include `YOUR_DB_PORT`, not only 5432):

```bash
psql "postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@YOUR_OFFICE_TAILSCALE_IP:YOUR_DB_PORT/hrms_plaridel" -c "SELECT 1;"
```

Architecture B, office backend:

On the office PC:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health/db
```

On the VPS:

```bash
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health/db
curl -s https://YOUR_DOMAIN/health/db
```

If the office test works but the VPS Tailscale test fails, check Tailscale and Windows Firewall for office port `3000`. If the Tailscale test works but HTTPS fails, check Nginx `proxy_pass`.

## 26.2 Tailscale works but Postgres refuses

Revisit `pg_hba.conf` (VPS IP `/32`, correct database and user), `postgresql.conf` (`listen_addresses`, `port`), and PostgreSQL service restarted on Windows.

## 26.3 Connection refused on port 5432 but PostgreSQL uses 5433

Your `DATABASE_URL` and firewall rule must use the same port as `port =` in `postgresql.conf` (often `5433` for PostgreSQL 18 on Windows).

## 26.4 Could not translate host name containing password

If the password contains `@`, encode it as `%40` inside `DATABASE_URL`, or change the password.

## 26.5 Nginx 502 Bad Gateway

Architecture A, VPS backend: Node is down or not listening on the VPS:

```bash
sudo systemctl status hrms-api --no-pager
curl -s http://127.0.0.1:3000/health
```

Architecture B, office backend: the VPS cannot reach the office backend:

```bash
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health
sudo nginx -T | grep proxy_pass
```

Then check on the office PC:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health
tailscale status
```

## 26.6 Flutter web CORS errors

Set `CORS_ORIGINS` in backend `.env` to the exact web origin including scheme and port. Mobile apps do not use browser CORS.

---

# 27. Quick final verification

Architecture A, VPS backend:

```bash
sudo systemctl status hrms-api --no-pager
curl -s http://127.0.0.1:3000/health/db
sudo nginx -t
curl -s https://YOUR_DOMAIN/health/db
```

Architecture B, office backend:

On the office PC:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health/db
```

On the VPS:

```bash
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health/db
sudo nginx -t
curl -s https://YOUR_DOMAIN/health/db
```

In a browser:

```text
https://YOUR_DOMAIN/health
https://YOUR_DOMAIN/health/db
```

---

# 28. Repo environment variables reference

These optional variables are documented in `backend/.env.example` and support this deployment:

```text
HOST=127.0.0.1 for Architecture A, or 0.0.0.0 for Architecture B
PORT=3000
TRUST_PROXY=1
CORS_ORIGINS=https://YOUR_DOMAIN
PG_CONNECTION_TIMEOUT_MS=15000
PG_POOL_MAX=20
JWT_SECRET=...
JWT_REFRESH_SECRET=...
BIO_SYNC_API_KEY=...
HRMS_API_URL=http://localhost:3000
ZK_POLL_INTERVAL=10
ZK_TIMEZONE_OFFSET=+08:00
```

VPN itself does not need Node code changes. Tailscale provides the private path between VPS and office.
