#!/usr/bin/env bash
set -Eeuo pipefail

# HRMS Plaridel VPS backup helper.
# Use from cron or a systemd timer on Linux. If the office Windows server is the
# production source of truth, this VPS job is a secondary/offsite backup and
# should not replace the Windows Task Scheduler backup.

PROJECT_ROOT="${PROJECT_ROOT:-/opt/hrms-plaridel}"
BACKEND_DIR="${BACKEND_DIR:-$PROJECT_ROOT/backend}"
ENV_FILE="${ENV_FILE:-$BACKEND_DIR/.env}"
BACKUP_ROOT="${HRMS_BACKUP_ROOT:-/var/backups/hrms-plaridel}"
OFFSITE_BACKUP_ROOT="${HRMS_OFFSITE_BACKUP_ROOT:-}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-12}"
INCLUDE_ENV_FILE="${INCLUDE_ENV_FILE:-0}"
SKIP_DB="${SKIP_DB:-0}"
SKIP_UPLOADS="${SKIP_UPLOADS:-0}"

timestamp="$(date +%Y%m%d_%H%M%S)"
daily_root="$BACKUP_ROOT/daily"
weekly_root="$BACKUP_ROOT/weekly"
monthly_root="$BACKUP_ROOT/monthly"
log_root="$BACKUP_ROOT/logs"
snapshot_dir="$daily_root/$timestamp"
log_file="$log_root/backup_$timestamp.log"

mkdir -p "$snapshot_dir" "$log_root"
chmod 700 "$BACKUP_ROOT" "$snapshot_dir" "$log_root" 2>/dev/null || true

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$log_file"
}

dotenv_value() {
  local key="$1"
  local file="$2"

  [ -f "$file" ] || return 1

  awk -F= -v key="$key" '
    $0 !~ /^[[:space:]]*#/ && $1 == key {
      sub(/^[^=]*=/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      gsub(/^"|"$/, "", $0)
      gsub(/^'\''|'\''$/, "", $0)
      print $0
      exit
    }
  ' "$file"
}

copy_snapshot() {
  local source="$1"
  local destination="$2"
  local parent

  parent="$(dirname "$destination")"
  mkdir -p "$parent"
  log "Copying snapshot to $destination"
  cp -a "$source" "$destination"
}

prune_snapshots() {
  local root="$1"
  local keep="$2"

  [ "$keep" -gt 0 ] || return 0
  [ -d "$root" ] || return 0

  find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
    sort -r |
    tail -n +"$((keep + 1))" |
    while IFS= read -r old_name; do
      [ -n "$old_name" ] || continue
      log "Removing old snapshot $root/$old_name"
      rm -rf -- "$root/$old_name"
    done
}

log "Starting HRMS VPS backup"
log "Project root: $PROJECT_ROOT"
log "Backup root: $BACKUP_ROOT"

database_url="${DATABASE_URL:-}"
if [ -z "$database_url" ]; then
  database_url="$(dotenv_value DATABASE_URL "$ENV_FILE" || true)"
fi

if [ "$SKIP_DB" != "1" ]; then
  if [ -z "$database_url" ]; then
    log "DATABASE_URL not found; skipping database dump"
  else
    if ! command -v pg_dump >/dev/null 2>&1; then
      log "pg_dump not found; install postgresql-client to enable database dumps"
      exit 1
    fi

    log "Running pg_dump"
    pg_dump --format=custom --no-owner --no-acl --file="$snapshot_dir/database.dump" "$database_url"
  fi
else
  log "Skipping database dump because SKIP_DB=1"
fi

upload_dir="${UPLOAD_DIR:-}"
if [ -z "$upload_dir" ]; then
  upload_dir="$(dotenv_value UPLOAD_DIR "$ENV_FILE" || true)"
fi
if [ -z "$upload_dir" ]; then
  upload_dir="$BACKEND_DIR/uploads"
elif [[ "$upload_dir" != /* ]]; then
  upload_dir="$BACKEND_DIR/$upload_dir"
fi

if [ "$SKIP_UPLOADS" != "1" ]; then
  if [ -d "$upload_dir" ]; then
    if find "$upload_dir" -mindepth 1 -print -quit | grep -q .; then
      log "Archiving uploads from $upload_dir"
      tar -czf "$snapshot_dir/uploads.tar.gz" -C "$upload_dir" .
    else
      log "Upload directory exists but is empty"
      printf 'Upload directory existed but had no files.\n' > "$snapshot_dir/uploads_empty.txt"
    fi
  else
    log "Upload directory does not exist: $upload_dir"
    printf 'Upload directory was not found: %s\n' "$upload_dir" > "$snapshot_dir/uploads_missing.txt"
  fi
else
  log "Skipping uploads archive because SKIP_UPLOADS=1"
fi

if [ "$INCLUDE_ENV_FILE" = "1" ] && [ -f "$ENV_FILE" ]; then
  log "Including backend .env file. Treat this backup as sensitive."
  cp "$ENV_FILE" "$snapshot_dir/backend.env"
  chmod 600 "$snapshot_dir/backend.env"
fi

cat > "$snapshot_dir/manifest.json" <<EOF
{
  "created_at": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "project_root": "$PROJECT_ROOT",
  "env_file": "$ENV_FILE",
  "upload_dir": "$upload_dir",
  "include_env_file": "$INCLUDE_ENV_FILE",
  "keep_daily": "$KEEP_DAILY",
  "keep_weekly": "$KEEP_WEEKLY",
  "keep_monthly": "$KEEP_MONTHLY"
}
EOF

created_tiers=("daily:$snapshot_dir")

if [ "$(date +%u)" = "7" ]; then
  weekly_snapshot="$weekly_root/$timestamp"
  copy_snapshot "$snapshot_dir" "$weekly_snapshot"
  created_tiers+=("weekly:$weekly_snapshot")
fi

if [ "$(date +%d)" = "01" ]; then
  monthly_snapshot="$monthly_root/$timestamp"
  copy_snapshot "$snapshot_dir" "$monthly_snapshot"
  created_tiers+=("monthly:$monthly_snapshot")
fi

if [ -n "$OFFSITE_BACKUP_ROOT" ]; then
  for tier_entry in "${created_tiers[@]}"; do
    tier="${tier_entry%%:*}"
    path="${tier_entry#*:}"
    copy_snapshot "$path" "$OFFSITE_BACKUP_ROOT/$tier/$timestamp"
  done
fi

prune_snapshots "$daily_root" "$KEEP_DAILY"
prune_snapshots "$weekly_root" "$KEEP_WEEKLY"
prune_snapshots "$monthly_root" "$KEEP_MONTHLY"

if [ -n "$OFFSITE_BACKUP_ROOT" ]; then
  prune_snapshots "$OFFSITE_BACKUP_ROOT/daily" "$KEEP_DAILY"
  prune_snapshots "$OFFSITE_BACKUP_ROOT/weekly" "$KEEP_WEEKLY"
  prune_snapshots "$OFFSITE_BACKUP_ROOT/monthly" "$KEEP_MONTHLY"
fi

log "Backup completed successfully: $snapshot_dir"
