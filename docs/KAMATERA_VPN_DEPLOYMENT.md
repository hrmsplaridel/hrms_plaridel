# HRMS Plaridel Kamatera VPS Deployment Guide

This guide is separated into two complete deployment tracks.

Use **Current Architecture** for the HRMS setup you are running now.
Use **Old Architecture** only as a fallback or reference.

```text
Old Architecture:
Users/mobile/web -> VPS Nginx HTTPS -> VPS Node backend -> Tailscale -> office PostgreSQL

Current Architecture:
Users/mobile/web -> VPS Nginx HTTPS -> Tailscale -> office Node backend -> office PostgreSQL
```

Quick choice:

| Architecture         | Status          | Backend runs on | Database runs on | Use this when                                         |
| -------------------- | --------------- | --------------- | ---------------- | ----------------------------------------------------- |
| Old Architecture     | Fallback only   | VPS             | Office PC        | You want the API process on Kamatera or need rollback |
| Current Architecture | Your live setup | Office PC       | Office PC        | Office DB is the main truth and speed is the priority |

Important:

- For your live HRMS, follow **Current Architecture**.
- The VPS still matters in the current setup. It provides public HTTPS through Nginx.
- The VPS backend service `hrms-api` is not needed for live traffic in the current setup.
- PostgreSQL must not be exposed publicly.
- Office backend port `3000` must not be router-port-forwarded publicly.
- Mobile APK release should use `https://hrmsplaridel.site`.

Placeholders:

```text
YOUR_DOMAIN                 example: hrmsplaridel.site
YOUR_SERVER_IP              VPS public IP
YOUR_REPO_URL               Git repository URL
YOUR_EMAIL                  email for LetsEncrypt/Certbot
YOUR_OFFICE_TAILSCALE_IP    example: 100.88.123.26
YOUR_VPS_TAILSCALE_IP       example: 100.108.196.109
YOUR_DB_USER                example: postgres
YOUR_DB_PASSWORD            PostgreSQL password
YOUR_DB_PORT                example: 5433
```

Related guides:

- [HRMS hybrid health checks](HRMS_HYBRID_HEALTH_CHECKS.md)
- [HRMS security checks](HRMS_SECURITY_CHECKS.md)

---

# Old Architecture

This is the old/fallback setup.

```text
Users/mobile/web
-> VPS Nginx HTTPS
-> VPS Node backend
-> Tailscale
-> office PostgreSQL
```

In this setup:

- VPS runs the public Nginx gateway.
- VPS also runs the Node backend as `hrms-api`.
- Office PC runs PostgreSQL only.
- Every SQL query travels from VPS to office over Tailscale.

Use this only if you intentionally want the backend on the VPS or need a rollback path.

## Old Step 1: Create And Prepare The VPS

Create a Kamatera VPS:

```text
Region: Singapore
OS: Ubuntu Server 22.04 LTS or 24.04 LTS
Starter size: 2 vCPU, 4 GB RAM, 50 GB SSD
Public IP: enabled
```

SSH as root:

```powershell
ssh root@YOUR_SERVER_IP
```

Create the deploy user:

```bash
adduser deploy
usermod -aG sudo deploy
id deploy
```

Copy your SSH key from Windows:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh deploy@YOUR_SERVER_IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

Login as deploy:

```powershell
ssh deploy@YOUR_SERVER_IP
sudo whoami
```

Expected:

```text
root
```

## Old Step 2: Harden SSH

On the VPS:

```bash
sudo nano /etc/ssh/sshd_config
```

Use:

```text
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
```

Validate and reload:

```bash
sudo sshd -t
sudo systemctl reload ssh
```

Keep one SSH session open while testing a second login.

## Old Step 3: Configure VPS Firewall

On the VPS:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Optional SSH rate limit:

```bash
sudo ufw delete allow OpenSSH
sudo ufw limit OpenSSH
```

Do not allow:

```text
3000/tcp
5432/tcp
5433/tcp
```

## Old Step 4: Install Node.js On The VPS

```bash
sudo apt update
sudo apt install -y curl ca-certificates gnupg build-essential
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs
node -v
npm -v
```

## Old Step 5: Install Tailscale On The VPS

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale status
tailscale ip -4
```

Save the VPS Tailscale IP as:

```text
YOUR_VPS_TAILSCALE_IP
```

## Old Step 6: Install Tailscale On The Office DB Host

On the office PC:

```powershell
tailscale status
tailscale ip -4
```

Save the office Tailscale IP as:

```text
YOUR_OFFICE_TAILSCALE_IP
```

Test from the VPS:

```bash
tailscale ping YOUR_OFFICE_TAILSCALE_IP
```

Best result:

```text
via direct
```

## Old Step 7: Allow VPS To Reach Office PostgreSQL

On the office PostgreSQL host, edit `postgresql.conf`.

Set:

```text
listen_addresses = '*'
port = YOUR_DB_PORT
```

Edit `pg_hba.conf`.

Add a line for the VPS Tailscale IP:

```text
host    hrms_plaridel    YOUR_DB_USER    YOUR_VPS_TAILSCALE_IP/32    scram-sha-256
```

Restart PostgreSQL.

On Windows, allow PostgreSQL only from the VPS Tailscale IP:

```powershell
New-NetFirewallRule `
  -DisplayName "PostgreSQL Tailscale" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort YOUR_DB_PORT `
  -RemoteAddress YOUR_VPS_TAILSCALE_IP `
  -Profile Any
```

## Old Step 8: Test PostgreSQL From The VPS

Install client tools:

```bash
sudo apt install -y postgresql-client
```

Test:

```bash
psql "postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@YOUR_OFFICE_TAILSCALE_IP:YOUR_DB_PORT/hrms_plaridel" -c "SELECT 1;"
```

Expected:

```text
?column?
----------
        1
```

## Old Step 9: Clone The Project On The VPS

```bash
sudo mkdir -p /opt/hrms-plaridel
sudo chown deploy:deploy /opt/hrms-plaridel
git clone YOUR_REPO_URL /opt/hrms-plaridel
cd /opt/hrms-plaridel
```

## Old Step 10: Configure VPS Backend `.env`

Path:

```bash
/opt/hrms-plaridel/backend/.env
```

Example:

```env
DATABASE_URL=postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@YOUR_OFFICE_TAILSCALE_IP:YOUR_DB_PORT/hrms_plaridel
HOST=127.0.0.1
PORT=3000
TRUST_PROXY=1
HRMS_TIMEZONE=Asia/Manila

JWT_SECRET=long_random_secret
JWT_REFRESH_SECRET=another_long_random_secret
JWT_EXPIRATION=15m
JWT_REFRESH_EXPIRATION=30d

BIO_SYNC_API_KEY=long_random_secret_for_biometric_sync
CORS_ORIGINS=https://YOUR_DOMAIN
```

Secure it:

```bash
chmod 600 /opt/hrms-plaridel/backend/.env
```

## Old Step 11: Install Backend Dependencies On The VPS

```bash
cd /opt/hrms-plaridel/backend
npm install
```

Smoke test:

```bash
HOST=127.0.0.1 PORT=3000 node src/index.js
```

In another SSH session:

```bash
curl -s http://127.0.0.1:3000/health
curl -s http://127.0.0.1:3000/health/db
```

Stop manual Node with `Ctrl+C`.

## Old Step 12: Create The VPS `hrms-api` Service

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
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now hrms-api
sudo systemctl status hrms-api --no-pager
curl -s http://127.0.0.1:3000/health/db
```

Logs:

```bash
sudo journalctl -u hrms-api -n 100 --no-pager
```

## Old Step 13: Configure Nginx To Proxy To VPS Backend

Install Nginx:

```bash
sudo apt install -y nginx
sudo systemctl enable --now nginx
```

Create site:

```bash
sudo nano /etc/nginx/sites-available/hrms-api
```

HTTP-only first:

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

## Old Step 14: DNS And HTTPS

Point DNS to the VPS public IP:

```text
A     YOUR_DOMAIN       YOUR_SERVER_IP
A     www               YOUR_SERVER_IP
```

Install Certbot:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d YOUR_DOMAIN -d www.YOUR_DOMAIN
```

Test:

```bash
curl -s https://YOUR_DOMAIN/health
curl -s https://YOUR_DOMAIN/health/db
```

## Old Step 15: Biometric Sync

On the office machine running the ZKTeco sync script:

```env
HRMS_API_URL=https://YOUR_DOMAIN
BIO_SYNC_API_KEY=same_value_as_VPS_backend_env
ZK_POLL_INTERVAL=10
ZK_TIMEZONE_OFFSET=+08:00
```

The script posts punches to the VPS backend, and the VPS backend writes to office PostgreSQL over Tailscale.

## Old Step 16: Backend Update Workflow

On the VPS:

```bash
cd /opt/hrms-plaridel
git pull
sudo systemctl restart hrms-api
sudo systemctl status hrms-api --no-pager
curl -s http://127.0.0.1:3000/health/db
```

Run only if dependencies changed:

```bash
cd /opt/hrms-plaridel/backend
npm install
sudo systemctl restart hrms-api
```

## Old Step 17: Old Architecture Verification

```bash
sudo systemctl status hrms-api --no-pager
curl -s http://127.0.0.1:3000/health/db
sudo nginx -t
curl -s https://YOUR_DOMAIN/health/db
```

---

# Current Architecture

This is your current production setup.

```text
Users/mobile/web
-> VPS Nginx HTTPS
-> Tailscale private tunnel
-> office Node backend
-> office PostgreSQL
```

In this setup:

- VPS runs Nginx only for public HTTPS traffic.
- Office PC runs the Node backend.
- Office PC runs PostgreSQL.
- Backend queries are local and faster.
- Tailscale connects the VPS privately to the office backend.
- The VPS `hrms-api` service is not needed for live traffic.

Follow this track when creating the server again.

## Current Step 1: Create And Prepare The VPS

Create a Kamatera VPS:

```text
Region: Singapore
OS: Ubuntu Server 22.04 LTS or 24.04 LTS
Starter size: 2 vCPU, 4 GB RAM, 50 GB SSD
Public IP: enabled
```

SSH as root:

```powershell
ssh root@YOUR_SERVER_IP
```

Create deploy user:

```bash
adduser deploy
usermod -aG sudo deploy
id deploy
```

Copy your SSH key:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh deploy@YOUR_SERVER_IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

Login as deploy:

```powershell
ssh deploy@YOUR_SERVER_IP
sudo whoami
```

## Current Step 2: Harden VPS SSH

```bash
sudo nano /etc/ssh/sshd_config
```

Use:

```text
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
```

Validate and reload:

```bash
sudo sshd -t
sudo systemctl reload ssh
```

## Current Step 3: Configure VPS Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Optional SSH rate limit:

```bash
sudo ufw delete allow OpenSSH
sudo ufw limit OpenSSH
```

Expected public ports:

```text
22
80
443
```

Do not expose:

```text
3000
5432
5433
```

## Current Step 4: Install Tailscale On The VPS

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale status
tailscale ip -4
```

Save this as:

```text
YOUR_VPS_TAILSCALE_IP
```

## Current Step 5: Install Tailscale On The Office PC

On the office backend/database PC:

```powershell
tailscale status
tailscale ip -4
tailscale netcheck
```

Save this as:

```text
YOUR_OFFICE_TAILSCALE_IP
```

Use wired LAN/Ethernet for the office PC if possible. This is more stable than Wi-Fi for the backend/database host.

From the VPS:

```bash
tailscale ping YOUR_OFFICE_TAILSCALE_IP
```

Best:

```text
active; direct
```

## Current Step 6: Change Tailscale Account Later

Use this if you need to move the VPS and office PC to a different Tailscale account/tailnet.

Important:

- The VPS and office PC must be logged in to the same Tailscale account/tailnet.
- Tailscale IPs may change after switching accounts.
- If the office Tailscale IP changes, update Nginx `proxy_pass`.
- If the VPS Tailscale IP changes, update Windows Firewall rules that allow the VPS.

### Current Step 6.1: Log Out And Re-Authenticate The VPS

Run on the VPS:

```bash
sudo tailscale logout
sudo tailscale up
tailscale status
tailscale ip -4
```

Login in the browser using the new Tailscale account.

Save the new VPS Tailscale IP as:

```text
YOUR_VPS_TAILSCALE_IP
```

### Current Step 6.2: Log Out And Re-Authenticate The Office PC

On the office PC, use the Tailscale tray icon:

```text
Tailscale icon -> account/menu -> Log out
Tailscale icon -> Log in
```

Or use PowerShell as Administrator:

```powershell
tailscale logout
tailscale up
tailscale status
tailscale ip -4
```

Login using the same new Tailscale account as the VPS.

Save the new office Tailscale IP as:

```text
YOUR_OFFICE_TAILSCALE_IP
```

### Current Step 6.3: Confirm Both Machines See Each Other

On the office PC:

```powershell
tailscale status
tailscale ping YOUR_VPS_TAILSCALE_IP
```

On the VPS:

```bash
tailscale status
tailscale ping YOUR_OFFICE_TAILSCALE_IP
```

Good:

```text
via direct
```

DERP is still secure, but can be slower:

```text
via DERP(...)
```

### Current Step 6.4: Update Office Windows Firewall Rules

If the VPS Tailscale IP changed, update the office firewall rule for backend port `3000`.

Remove the old rule:

```powershell
Remove-NetFirewallRule -DisplayName "HRMS Office API from VPS Tailscale"
```

Create the new rule:

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

If you also keep direct VPS access to PostgreSQL for admin tests or rollback, update that rule too:

```powershell
Remove-NetFirewallRule -DisplayName "PostgreSQL Tailscale"

New-NetFirewallRule `
  -DisplayName "PostgreSQL Tailscale" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort YOUR_DB_PORT `
  -RemoteAddress YOUR_VPS_TAILSCALE_IP `
  -Profile Any
```

### Current Step 6.5: Update PostgreSQL `pg_hba.conf` If Needed

If `pg_hba.conf` allows the old VPS Tailscale IP, replace it with the new one:

```text
host    hrms_plaridel    YOUR_DB_USER    YOUR_VPS_TAILSCALE_IP/32    scram-sha-256
```

Restart PostgreSQL after saving.

This is only needed if the VPS still connects directly to PostgreSQL for admin testing or fallback. The current live backend uses local PostgreSQL through `localhost`.

### Current Step 6.6: Update Nginx If The Office Tailscale IP Changed

Run on the VPS:

```bash
sudo nano /etc/nginx/sites-available/hrms-api
```

Update every office backend proxy target:

```nginx
proxy_pass http://YOUR_OFFICE_TAILSCALE_IP:3000;
```

Then:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### Current Step 6.7: Verify After Tailscale Account Change

On the office PC:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health/db
```

On the VPS:

```bash
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health/db
curl -s https://YOUR_DOMAIN/health/db
```

From a phone/browser:

```text
https://YOUR_DOMAIN/health/db
```

If public health returns `502 Bad Gateway`, check:

```bash
sudo nginx -T | grep proxy_pass
tailscale ping YOUR_OFFICE_TAILSCALE_IP
```

## Current Step 7: Configure Office PostgreSQL

Because the backend also runs on the office PC, the live backend connects to PostgreSQL through `localhost`.

Your office backend `.env` will use:

```env
DATABASE_URL=postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@localhost:YOUR_DB_PORT/hrms_plaridel
```

You may still allow VPS PostgreSQL access over Tailscale for admin tests or rollback.

If allowing VPS PostgreSQL access, edit `postgresql.conf`:

```text
listen_addresses = '*'
port = YOUR_DB_PORT
```

Edit `pg_hba.conf`:

```text
host    hrms_plaridel    YOUR_DB_USER    YOUR_VPS_TAILSCALE_IP/32    scram-sha-256
```

Windows Firewall rule for PostgreSQL:

```powershell
New-NetFirewallRule `
  -DisplayName "PostgreSQL Tailscale" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort YOUR_DB_PORT `
  -RemoteAddress YOUR_VPS_TAILSCALE_IP `
  -Profile Any
```

Local DB test on office PC:

```powershell
psql -U YOUR_DB_USER -p YOUR_DB_PORT -d hrms_plaridel -c "SELECT 1;"
```

## Current Step 8: Configure Office Backend `.env`

Path:

```text
C:\Users\Admin\hrms_plaridel\backend\.env
```

Example:

```env
DATABASE_URL=postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@localhost:YOUR_DB_PORT/hrms_plaridel
HOST=0.0.0.0
PORT=3000
TRUST_PROXY=1
HRMS_TIMEZONE=Asia/Manila

JWT_SECRET=long_random_secret
JWT_REFRESH_SECRET=another_long_random_secret
JWT_EXPIRATION=15m
JWT_REFRESH_EXPIRATION=30d

BIO_SYNC_API_KEY=long_random_secret_for_biometric_sync
HRMS_API_URL=http://localhost:3000
ZK_POLL_INTERVAL=10
ZK_TIMEZONE_OFFSET=+08:00
```

Important:

- `DATABASE_URL` uses `localhost` because the DB is local to the office backend.
- `HOST=0.0.0.0` lets the VPS reach the office backend over Tailscale.
- `HRMS_API_URL=http://localhost:3000` is for the biometric sync script on the same office PC.
- Keep real `.env` secrets out of Git.

## Current Step 9: Start And Test Office Backend

On office PC:

```powershell
cd C:\Users\Admin\hrms_plaridel\backend
npm install
npm start
```

Local tests:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health/db
```

Good DB result:

```json
{ "ok": true, "message": "PostgreSQL connection OK" }
```

For production-like use, run the office backend with PM2/NSSM/Task Scheduler so it stays running after PowerShell closes.

PM2 example:

```powershell
npm install -g pm2
cd C:\Users\Admin\hrms_plaridel\backend
pm2 start src/index.js --name hrms-office-api
pm2 save
pm2 status
```

## Current Step 10: Allow VPS To Reach Office Backend Port 3000

Run on office PC PowerShell as Administrator:

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

Do not port-forward office port `3000` on the router.

## Current Step 11: Test Office Backend From The VPS

Run on the VPS:

```bash
tailscale ping YOUR_OFFICE_TAILSCALE_IP
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health/db
```

Timing check:

```bash
curl -o /dev/null -s -w "total=%{time_total}s\n" http://YOUR_OFFICE_TAILSCALE_IP:3000/health/db
```

Good:

```text
total=0.1s to 0.5s
```

If slow, check:

```bash
tailscale netcheck
tailscale ping YOUR_OFFICE_TAILSCALE_IP
```

On office PC:

```powershell
tailscale netcheck
tailscale ping YOUR_VPS_TAILSCALE_IP
```

Use wired LAN for the office PC if possible.

## Current Step 12: Install Nginx On The VPS

```bash
sudo apt update
sudo apt install -y nginx
sudo systemctl enable --now nginx
```

Create site:

```bash
sudo nano /etc/nginx/sites-available/hrms-api
```

Use this current architecture config:

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

        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
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

## Current Step 13: DNS And HTTPS

Point DNS to the VPS public IP:

```text
A     YOUR_DOMAIN       YOUR_SERVER_IP
A     www               YOUR_SERVER_IP
```

Install Certbot:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d YOUR_DOMAIN -d www.YOUR_DOMAIN
```

Test:

```bash
curl -s https://YOUR_DOMAIN/health
curl -s https://YOUR_DOMAIN/health/db
```

Expected:

```json
{ "ok": true }
```

## Current Step 14: Optional Nginx Rate Limit

Create:

```bash
sudo nano /etc/nginx/conf.d/hrms-rate-limit.conf
```

Content:

```nginx
limit_req_zone $binary_remote_addr zone=hrms_general:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=hrms_login:10m rate=5r/m;
```

In `/etc/nginx/sites-available/hrms-api`, put login route above `location /`:

```nginx
location = /auth/login {
    limit_req zone=hrms_login burst=5 nodelay;

    proxy_pass http://YOUR_OFFICE_TAILSCALE_IP:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Add this inside general `location /`:

```nginx
limit_req zone=hrms_general burst=60 nodelay;
```

Reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Current Step 15: Optional Fail2ban

```bash
sudo apt update
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

Fail2ban protects SSH from repeated failed login attempts.

## Current Step 16: Stop Old VPS Backend Service If It Exists

Only do this after public HTTPS works through the office backend:

```bash
curl -s https://YOUR_DOMAIN/health/db
```

Then:

```bash
sudo systemctl stop hrms-api
sudo systemctl disable hrms-api
```

Do not delete the project from the VPS yet. Keep it for rollback, docs, web hosting, or scripts.

## Current Step 17: Biometric Sync

On the office PC:

```env
HRMS_API_URL=http://localhost:3000
BIO_SYNC_API_KEY=same_value_as_office_backend_env
ZK_POLL_INTERVAL=10
ZK_TIMEZONE_OFFSET=+08:00
```

Run:

```powershell
cd C:\Users\Admin\hrms_plaridel\backend
python scripts/zkteco-sync-py.py
```

The sync script reads the biometric device over LAN and posts directly to the office backend.

## Current Step 18: Flutter Mobile Build

For release APK, use the public domain:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR_DOMAIN
```

Optional split APKs:

```powershell
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://YOUR_DOMAIN
```

For local office development, you may run against the office LAN IP:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000
```

Do not use the office LAN IP for release APKs used outside the office.

## Current Step 19: Applicant Landing Page Hosting On VPS

Use this when you want the public website to show only the applicant landing page, not the full HRMS login/dashboard app.

Build the landing page locally from the Flutter frontend:

```powershell
cd C:\Users\Admin\hrms_plaridel\frontend
flutter build web --release -t lib/main_landing.dart --dart-define=API_BASE_URL=https://YOUR_DOMAIN
```

This creates the static web files here:

```text
C:\Users\Admin\hrms_plaridel\frontend\build\web
```

Upload the contents of `frontend/build/web` to the VPS:

```text
/var/www/hrms-landing
```

Example upload from Windows PowerShell:

```powershell
scp -r C:\Users\Admin\hrms_plaridel\frontend\build\web\* deploy@YOUR_SERVER_IP:/tmp/hrms-landing/
```

Then on the VPS:

```bash
sudo mkdir -p /var/www/hrms-landing
sudo rsync -a --delete /tmp/hrms-landing/ /var/www/hrms-landing/
sudo chown -R www-data:www-data /var/www/hrms-landing
```

Create or update the Nginx site:

```bash
sudo nano /etc/nginx/sites-available/hrms-landing
```

Use this if the same domain serves the landing page and proxies API requests to the office backend:

```nginx
server {
    listen 80;
    listen [::]:80;

    server_name YOUR_DOMAIN www.YOUR_DOMAIN;

    root /var/www/hrms-landing;
    index index.html;

    location /api/ {
        proxy_pass http://YOUR_OFFICE_TAILSCALE_IP:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /auth/ {
        proxy_pass http://YOUR_OFFICE_TAILSCALE_IP:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /health {
        proxy_pass http://YOUR_OFFICE_TAILSCALE_IP:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

Enable the site:

```bash
sudo ln -sf /etc/nginx/sites-available/hrms-landing /etc/nginx/sites-enabled/hrms-landing
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

If HTTPS is not installed yet:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d YOUR_DOMAIN -d www.YOUR_DOMAIN
```

Verify:

```bash
curl -I https://YOUR_DOMAIN
curl -s https://YOUR_DOMAIN/health
```

Expected public result:

```text
Browser -> VPS Nginx HTTPS -> static Flutter landing page
Landing API calls -> VPS Nginx HTTPS -> Tailscale -> office backend
```

Important:

- Always use `-t lib/main_landing.dart` for the public applicant website.
- Do not use plain `flutter build web --release` for this site because that builds the normal HRMS app entry.
- Rebuild and re-upload `frontend/build/web` whenever landing page code changes.

## Current Step 19.1: Full HRMS Web App Hosting On VPS

Use this later if you also want to host the full HRMS web app online for admin/employee browser access.

This is separate from the applicant landing page.

Build the full HRMS web app locally:

```powershell
cd C:\Users\Admin\hrms_plaridel\frontend
flutter build web --release --dart-define=API_BASE_URL=https://YOUR_APP_DOMAIN
```

This creates:

```text
C:\Users\Admin\hrms_plaridel\frontend\build\web
```

Upload the contents of `frontend/build/web` to a different VPS folder from the applicant landing page:

```text
/var/www/hrms-app
```

Example upload from Windows PowerShell:

```powershell
scp -r C:\Users\Admin\hrms_plaridel\frontend\build\web\* deploy@YOUR_SERVER_IP:/tmp/hrms-app/
```

Then on the VPS:

```bash
sudo mkdir -p /var/www/hrms-app
sudo rsync -a --delete /tmp/hrms-app/ /var/www/hrms-app/
sudo chown -R www-data:www-data /var/www/hrms-app
```

Recommended domain setup:

```text
careers.YOUR_DOMAIN or YOUR_DOMAIN       -> applicant landing page
app.YOUR_DOMAIN or hrms.YOUR_DOMAIN      -> full HRMS web app
```

Create or update the Nginx site for the full HRMS web app:

```bash
sudo nano /etc/nginx/sites-available/hrms-app
```

Example using `app.YOUR_DOMAIN`:

```nginx
server {
    listen 80;
    listen [::]:80;

    server_name app.YOUR_DOMAIN;

    root /var/www/hrms-app;
    index index.html;

    location /api/ {
        proxy_pass http://YOUR_OFFICE_TAILSCALE_IP:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /auth/ {
        proxy_pass http://YOUR_OFFICE_TAILSCALE_IP:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /health {
        proxy_pass http://YOUR_OFFICE_TAILSCALE_IP:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

Enable the site:

```bash
sudo ln -sf /etc/nginx/sites-available/hrms-app /etc/nginx/sites-enabled/hrms-app
sudo nginx -t
sudo systemctl reload nginx
```

Install HTTPS for the app domain:

```bash
sudo certbot --nginx -d app.YOUR_DOMAIN
```

Verify:

```bash
curl -I https://app.YOUR_DOMAIN
curl -s https://app.YOUR_DOMAIN/health
```

Expected full HRMS web result:

```text
Browser -> VPS Nginx HTTPS -> static Flutter HRMS app
App API calls -> VPS Nginx HTTPS -> Tailscale -> office backend
```

Important:

- Use plain `flutter build web --release` for the full HRMS web app.
- Use `flutter build web --release -t lib/main_landing.dart` only for the applicant landing page.
- Each Flutter web build replaces `frontend/build/web`, so upload one build before building the other.
- Keep the landing page and full HRMS app in different VPS folders or different deployment targets.

## Current Step 20: Current Backend Update Workflow

Backend code is live on the office PC, not the VPS.

On office PC:

```powershell
cd C:\Users\Admin\hrms_plaridel
git pull
```

Run only if dependencies changed:

```powershell
cd C:\Users\Admin\hrms_plaridel\backend
npm install
```

Restart backend:

```powershell
pm2 restart hrms-office-api
```

or, if running manually:

```powershell
cd C:\Users\Admin\hrms_plaridel\backend
npm start
```

Verify:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health/db
Invoke-WebRequest -UseBasicParsing https://YOUR_DOMAIN/health/db
```

You usually do not need `git pull` on the VPS for backend changes in the current architecture.

Pull on the VPS only if you changed:

- Nginx config/docs
- Flutter web files hosted on the VPS
- VPS scripts
- rollback copy

## Current Step 21: Current Final Verification

Office PC:

```powershell
tailscale status
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health/db
pm2 status
```

VPS:

```bash
tailscale status
tailscale ping YOUR_OFFICE_TAILSCALE_IP
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health/db
sudo nginx -t
curl -s https://YOUR_DOMAIN/health/db
sudo ufw status
sudo ss -ltnp
```

Mobile/browser:

```text
https://YOUR_DOMAIN/health
https://YOUR_DOMAIN/health/db
```

Good public flow:

```text
Phone/browser -> VPS Nginx HTTPS -> Tailscale -> office backend -> office PostgreSQL
```

## Current Step 22: Troubleshooting

### 502 Bad Gateway

Nginx cannot reach the office backend.

Check office PC:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/health
```

Check VPS:

```bash
curl -s http://YOUR_OFFICE_TAILSCALE_IP:3000/health
sudo nginx -T | grep proxy_pass
```

### Public Is Slow But Local Is Fast

Check Tailscale:

```bash
tailscale ping YOUR_OFFICE_TAILSCALE_IP
curl -o /dev/null -s -w "total=%{time_total}s\n" http://YOUR_OFFICE_TAILSCALE_IP:3000/health/db
```

Use wired LAN for the office PC if possible.

### DTR Local Fast But Public Slow

The database is not the problem. Check:

- Tailscale direct/DERP path
- office router
- office LAN/Wi-Fi
- Nginx proxy route
- response payload size

### DB Health Fails Locally

Check office `.env`:

```env
DATABASE_URL=postgresql://YOUR_DB_USER:YOUR_DB_PASSWORD@localhost:YOUR_DB_PORT/hrms_plaridel
```

Check PostgreSQL service and port.

### Cannot Login On Mobile

Check public health first:

```text
https://YOUR_DOMAIN/health
https://YOUR_DOMAIN/health/db
```

Then check office backend logs, because the office backend is live in the current architecture.
