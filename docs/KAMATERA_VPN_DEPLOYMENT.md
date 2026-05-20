# HRMS Plaridel Kamatera VPS hosting guide sheet

This guide covers deployment where the Node.js API runs on a Kamatera VPS and PostgreSQL remains on the office LAN as the single source of truth. Remote users call HTTPS on the VPS. The VPS reaches PostgreSQL only over a private VPN mesh (this guide uses Tailscale).

Use these placeholders:

- `YOUR_SERVER_IP`: your VPS public IP, example `79.108.225.134`
- `YOUR_DOMAIN`: your API domain, example `hrms.example.gov.ph`
- `YOUR_REPO_URL`: your Git repository URL (GitHub or other)
- `YOUR_OFFICE_TAILSCALE_IP`: the office PostgreSQL host Tailscale address, example `100.64.0.12` (shown in Tailscale admin or `tailscale ip -4` on that machine)
- `YOUR_VPS_TAILSCALE_IP`: the VPS Tailscale address (for office firewall or Postgres allow rules if you prefer allowlisting the VPS)
- `YOUR_DB_USER`: PostgreSQL role used only for the API, example `hrms_api`
- `YOUR_DB_PASSWORD`: that role password (avoid raw `@` in passwords or encode as `%40` inside URLs)
- `YOUR_EMAIL`: email for Let's Encrypt certificate notices

Example names you can copy or rename:

- VPS Linux user: `deploy`
- Project folder: `/opt/hrms-plaridel`
- Backend folder: `/opt/hrms-plaridel/backend`
- Flutter web folder on VPS: `/var/www/hrms`
- systemd service: `hrms-api`
- Backend local bind: `127.0.0.1:3000`
- Public API root: `https://YOUR_DOMAIN`

Important layout:

- PostgreSQL runs in the office, not on the VPS.
- Do not expose PostgreSQL port 5432 to the public internet.
- Tailscale runs on the Kamatera VPS and on the office machine that hosts PostgreSQL (or on a PC that can reach Postgres on the LAN with subnet routing enabled in Tailscale, advanced).

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
- Use a VPS cron or systemd timer backup for VPS-owned data and optional offsite copies. See section 14.1.

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

---

# 6. Install Node.js LTS

Run on the VPS:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs build-essential
node -v
npm -v
```

---

# 7. Install Tailscale on the VPS

Run on the VPS:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Complete browser login when the command prints a URL.

Confirm Tailscale IP:

```bash
tailscale ip -4
```

Save this value as `YOUR_VPS_TAILSCALE_IP` if you document allow rules.

---

# 8. Install Tailscale on the office PostgreSQL host

On the Windows or Linux machine that runs PostgreSQL (or that has LAN access to it with subnet routing, advanced):

1. Install Tailscale from https://tailscale.com/download
2. Sign in with the same Tailscale organization as the VPS
3. Note the machine Tailscale IP, example `100.x.x.x`

Save this as `YOUR_OFFICE_TAILSCALE_IP` for `DATABASE_URL` and for testing.

From the VPS, test:

```bash
ping -c 4 YOUR_OFFICE_TAILSCALE_IP
```

---

# 9. Office PostgreSQL listen addresses and authentication

On the office DB server:

1. Edit postgresql.conf and set listen_addresses so the server accepts connections on the interface Tailscale uses. Follow the PostgreSQL documentation for listen_addresses (the setting that listens on all configured interfaces is the standard choice when you lock down access with pg_hba.conf).

Narrowing to specific interfaces is possible if you know your OS layout; restrict who may connect using pg_hba.conf and Windows Firewall, not only listen_addresses.

2. Edit `pg_hba.conf` and add a line that allows the VPS to connect over Tailscale only if you use one fixed VPS Tailscale IP (recommended narrow rule):

```text
host    hrms_plaridel    YOUR_DB_USER    YOUR_VPS_TAILSCALE_IP/32    scram-sha-256
```

Replace database name and user name to match your setup. Use a dedicated role for the API, not the postgres superuser.

3. Reload or restart PostgreSQL. On Linux:

```bash
sudo systemctl reload postgresql
```

On Windows, restart the PostgreSQL service from Services or use pg_ctl.

4. On the office firewall, do not forward port 5432 from the internet. Allow PostgreSQL only from LAN and from Tailscale as needed.

---

# 10. Test database connectivity from the VPS

On the Kamatera VPS:

```bash
sudo apt install -y postgresql-client
psql "postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@YOUR_OFFICE_TAILSCALE_IP:5432/hrms_plaridel" -c "SELECT 1;"
```

If this fails, fix Tailscale login on both sides, `pg_hba.conf`, password, listen_addresses, or office firewall before continuing.

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

# 12. Backend environment file

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
DATABASE_URL=postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@YOUR_OFFICE_TAILSCALE_IP:5432/hrms_plaridel
JWT_SECRET=PASTE_FIRST_HEX_HERE
JWT_REFRESH_SECRET=PASTE_SECOND_HEX_HERE
HOST=127.0.0.1
PORT=3000
TRUST_PROXY=1
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

Optional biometric punch ingestion from the office sync script on the VPS must match the same key:

```env
BIO_SYNC_API_KEY=generate_a_long_random_secret
```

Secure the file:

```bash
chmod 600 .env
```

---

# 13. Install backend dependencies and smoke test

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

# 14. systemd service for the HRMS API

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

## 14.1 VPS backup scheduler

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

HTTP-only first (Certbot will upgrade later):

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

Enable:

```bash
sudo ln -sf /etc/nginx/sites-available/hrms-api /etc/nginx/sites-enabled/hrms-api
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

---

# 16. Domain DNS

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

If you later host Flutter web static files on this VPS under the same hostname, add a root and split locations so `/` serves web and API paths proxy to Node. Example pattern:

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

# 23. Office biometric sync script points to the public API

On the office machine that runs `backend/scripts/zkteco-sync-py.py`, set the API base to the Kamatera HTTPS URL, not localhost.

Example `.env` or environment for that script:

```env
API_URL=https://YOUR_DOMAIN
BIO_SYNC_API_KEY=same_value_as_VPS_backend_env
```

Office pushes punches to the VPS API; the VPS writes into PostgreSQL over Tailscale to the office DB.

---

# 24. Schema and database initialization

Run on the office PostgreSQL server or any machine that can connect with psql:

```bash
psql -U postgres -d hrms_plaridel -f /path/to/backend/scripts/init-schema.sql
```

Run extra scripts only if your deployment uses those modules, same as `backend/README.md` describes.

---

# 25. Normal update workflow

## 25.1 Backend code update

Push to Git from your dev machine, then on the VPS:

```bash
cd /opt/hrms-plaridel
git pull
cd backend
npm install
sudo systemctl restart hrms-api
sudo systemctl status hrms-api --no-pager
curl -s http://127.0.0.1:3000/health/db
```

## 25.2 Backend `.env` change

```bash
nano /opt/hrms-plaridel/backend/.env
chmod 600 /opt/hrms-plaridel/backend/.env
sudo systemctl restart hrms-api
```

---

# 26. Troubleshooting

## 26.1 health/db returns 503 on VPS

Check API logs and database URL:

```bash
sudo journalctl -u hrms-api -n 100 --no-pager
curl -s http://127.0.0.1:3000/health/db
```

Test psql from VPS to office again:

```bash
psql "postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@YOUR_OFFICE_TAILSCALE_IP:5432/hrms_plaridel" -c "SELECT 1;"
```

## 26.2 Tailscale works but Postgres refuses

Revisit `pg_hba.conf`, role password, database name, and `listen_addresses`.

## 26.3 Could not translate host name containing password

If the password contains `@`, encode it as `%40` inside `DATABASE_URL`, or change the password.

## 26.4 Nginx 502 Bad Gateway

Node is down or not listening:

```bash
sudo systemctl status hrms-api --no-pager
curl -s http://127.0.0.1:3000/health
```

## 26.5 Flutter web CORS errors

Set `CORS_ORIGINS` in backend `.env` to the exact web origin including scheme and port. Mobile apps do not use browser CORS.

---

# 27. Quick final verification

On the VPS:

```bash
sudo systemctl status hrms-api --no-pager
curl -s http://127.0.0.1:3000/health/db
sudo nginx -t
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
TRUST_PROXY=1
CORS_ORIGINS=https://YOUR_DOMAIN
PG_CONNECTION_TIMEOUT_MS=15000
PG_POOL_MAX=20
BIO_SYNC_API_KEY=...
```

VPN itself does not need Node code changes. Tailscale provides the private path between VPS and office.
