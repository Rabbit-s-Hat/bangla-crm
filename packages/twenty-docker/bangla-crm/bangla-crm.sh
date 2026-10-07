#!/usr/bin/env bash
# Everyday commands for Bangla CRM on macOS and Linux. Run them from this folder:
#   bash bangla-crm.sh start                     start Bangla CRM and open it in the browser
#   bash bangla-crm.sh stop                      stop it (your data is kept)
#   bash bangla-crm.sh restart | status | open
#   bash bangla-crm.sh logs                      follow the logs (Ctrl+C to quit)
#   bash bangla-crm.sh backup [--keep-days N]    save database + uploaded files + settings into backups/<date-time>/
#   bash bangla-crm.sh update [--version X]      back up, then install the newest release (or version X)
#   bash bangla-crm.sh restore backups/<date-time>   replace ALL current data with that backup
#   sudo bash bangla-crm.sh finish-setup         cloud servers: open the site to everyone after you signed up
if [ -z "${BASH_VERSION:-}" ]; then echo "Please run this with bash:  bash bangla-crm.sh"; exit 1; fi
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

STORAGE_PATH=/app/packages/twenty-server/.local-storage
RELEASES_API=https://api.github.com/repos/Rabbit-s-Hat/bangla-crm/releases/latest
SERVER_TRIES=360 # x 5 s = 30 minutes (the first start creates the database)

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- .env helpers -----------------------------------------------------------------------------

env_get() { # env_get KEY [DEFAULT]
  local value=""
  if [ -f .env ]; then
    value="$(awk -v k="$1" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' .env)"
  fi
  printf '%s' "${value:-${2:-}}"
}

set_env() { # set_env KEY VALUE  (replaces the line or appends it; keeps file permissions)
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/bangla-crm-env.XXXXXX")"
  awk -v k="$1" -v v="$2" '
    index($0, k "=") == 1 { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }' .env > "$tmp"
  cat "$tmp" > .env
  rm -f "$tmp"
}

file_get() { # file_get FILE KEY  (read KEY=value from another env file, e.g. a backup's env.txt)
  awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$1"
}

rand_b64() { head -c 32 /dev/urandom | base64 | tr -d '\n'; }
rand_hex() { head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

valid_version() {
  [ "$1" = latest ] && return 0
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]
}

# The address to open on THIS computer (LAN installs also work at localhost; cloud uses the domain).
local_url() {
  if [ -n "$(env_get DOMAIN)" ]; then
    env_get SERVER_URL
  else
    printf 'http://localhost:%s' "$(env_get HTTP_PORT 3000)"
  fi
}

# --- Docker helpers ---------------------------------------------------------------------------

require_docker() {
  local out
  command -v docker >/dev/null 2>&1 ||
    fail "Docker is not installed. Install Docker Desktop (macOS) or Docker Engine (Linux): https://docs.docker.com/get-docker/"
  docker compose version >/dev/null 2>&1 ||
    fail "Docker Compose v2 ('docker compose') is missing. Update Docker Desktop, or install the docker-compose-plugin / docker-compose-v2 package."
  if ! out="$(docker info 2>&1)"; then
    case "$out" in
      *ermission*denied*) fail "This user may not use Docker. Run with sudo, or add the user to the 'docker' group and log in again." ;;
    esac
    fail "Docker is not running. Start Docker Desktop (or: sudo systemctl start docker) and try again."
  fi
}

container_id() { docker compose ps -aq "$1" 2>/dev/null | head -n 1; }
is_running()   { [ -n "$(docker compose ps --status running -q "$1" 2>/dev/null)" ]; }
volume_exists() { docker volume inspect "bangla-crm_$1" >/dev/null 2>&1; }

wait_healthy() { # wait_healthy [SERVICE] [TRIES]  (one try = 5 seconds)
  local service="${1:-server}" tries="${2:-$SERVER_TRIES}" id status i=0
  id="$(docker compose ps -q "$service" 2>/dev/null | head -n 1)"
  [ -n "$id" ] || fail "The $service container is not running. See: docker compose logs $service"
  while [ "$i" -lt "$tries" ]; do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || true)"
    case "$status" in
      healthy) printf '\n'; return 0 ;;
      unhealthy|exited|dead)
        printf '\n'; fail "The $service container stopped or reported a problem. See: docker compose logs $service" ;;
    esac
    i=$((i + 1))
    printf '.'
    sleep 5
  done
  printf '\n'
  fail "$service is still not ready after $((tries * 5 / 60)) minutes. See: docker compose logs $service"
}

# Start everything: database first, then the server (with a visible progress line), then the rest.
start_all() {
  say "Starting Bangla CRM. The first start sets up the database and can take 5-15 minutes; later starts take about a minute."
  docker compose up -d db redis
  wait_healthy db 60
  docker compose up -d server
  wait_healthy server
  docker compose up -d
}

open_browser() {
  local url
  url="$(local_url)"
  if [ "$(uname)" = "Darwin" ]; then
    open "$url" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    xdg-open "$url" >/dev/null 2>&1 || true
  fi
  say "Bangla CRM: $url"
}

free_kb() { df -Pk "${1:-.}" | awk 'NR == 2 { print $4 }'; }

# --- Commands ---------------------------------------------------------------------------------

cmd_backup() {
  local keep_days="" user db stamp dir server_id db_kb need_kb
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep-days) [ $# -ge 2 ] || fail "--keep-days needs a number"; keep_days="$2"; shift 2 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done
  if [ -n "$keep_days" ] && ! [[ "$keep_days" =~ ^[0-9]+$ ]]; then fail "--keep-days needs a number"; fi

  if ! is_running db; then
    say "Starting the database for the backup..."
    docker compose up -d db
    wait_healthy db 60
  fi
  user="$(env_get PG_DATABASE_USER postgres)"
  db="$(env_get PG_DATABASE_NAME default)"

  # Free space: the dump is smaller than the live database, so 2x database + 1 GB is a safe margin.
  db_kb="$(docker compose exec -T db psql -U "$user" -d "$db" -tAc "SELECT pg_database_size(current_database()) / 1024" 2>/dev/null | tr -dc '0-9' || true)"
  need_kb=$(( ${db_kb:-0} * 2 + 1048576 ))
  mkdir -p backups
  chmod 700 backups
  if [ "$(free_kb backups)" -lt "$need_kb" ]; then
    fail "Not enough free disk space for a backup (need about $((need_kb / 1024)) MB). Delete old backups or free some space."
  fi

  stamp="$(date +%Y-%m-%d_%H%M%S)"
  dir="backups/$stamp"
  mkdir -p "$dir"
  chmod 700 "$dir"

  say "Saving the database..."
  docker compose exec -T db pg_dump -U "$user" -d "$db" -Fc -f /tmp/bangla-crm-backup.dump
  docker cp "$(container_id db):/tmp/bangla-crm-backup.dump" "$dir/database.dump"
  docker compose exec -T db rm -f /tmp/bangla-crm-backup.dump

  say "Saving uploaded files..."
  server_id="$(container_id server)"
  if [ -z "$server_id" ]; then
    docker compose create server >/dev/null 2>&1 || true
    server_id="$(container_id server)"
  fi
  [ -n "$server_id" ] || fail "Could not reach the uploaded files. The database part of the backup is in $dir."
  docker cp "$server_id:$STORAGE_PATH" "$dir/files"

  docker compose images server 2>/dev/null | awk 'NR > 1 { print $2 ":" $3 }' > "$dir/version.txt" || true
  cp .env "$dir/env.txt"
  chmod 600 "$dir/env.txt"
  say "Backup saved in: $dir"
  say "It contains your encryption key. Keep it private, and copy it to another disk or cloud storage."

  if [ -n "$keep_days" ]; then
    find backups -mindepth 1 -maxdepth 1 -type d -name '20*_*' -mtime +"$keep_days" -exec rm -rf {} +
  fi
  BACKUP_DIR="$dir"
}

# restore DIR [--yes]   (--yes: no questions and no safety backup; used by update's automatic rollback)
cmd_restore() {
  local dir="" yes=0 user db answer backup_key backup_fallback stamp
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes) yes=1; shift ;;
      *) [ -z "$dir" ] || fail "Usage: bash bangla-crm.sh restore backups/<date-time>"; dir="$1"; shift ;;
    esac
  done
  [ -n "$dir" ] || fail "Usage: bash bangla-crm.sh restore backups/<date-time>"
  dir="${dir%/}"
  [ -s "$dir/database.dump" ] || fail "$dir/database.dump not found or empty."

  if [ "$yes" -eq 0 ]; then
    say "This REPLACES everything in Bangla CRM with the backup in $dir."
    say "(A safety backup of the current data is made first.)"
    printf 'Type RESTORE to continue: '
    read -r answer || answer=""
    [ "$answer" = "RESTORE" ] || fail "Cancelled. Nothing was changed."
    say "Making a safety backup of the current data first..."
    cmd_backup
    say "Safety backup: $BACKUP_DIR"
  fi

  user="$(env_get PG_DATABASE_USER postgres)"
  db="$(env_get PG_DATABASE_NAME default)"
  docker compose stop server worker >/dev/null 2>&1 || true
  docker compose up -d db redis
  wait_healthy db 60

  say "Checking and restoring the database (into a temporary database first)..."
  docker cp "$dir/database.dump" "$(container_id db):/tmp/bangla-crm-restore.dump"
  docker compose exec -T db pg_restore -l /tmp/bangla-crm-restore.dump >/dev/null ||
    { docker compose up -d; fail "The backup file is damaged (pg_restore cannot read it). Nothing was changed."; }
  docker compose exec -T db dropdb -U "$user" --if-exists --force "${db}_restore"
  docker compose exec -T db createdb -U "$user" "${db}_restore"
  if ! docker compose exec -T db pg_restore -U "$user" -d "${db}_restore" --no-owner --single-transaction /tmp/bangla-crm-restore.dump; then
    docker compose exec -T db dropdb -U "$user" --if-exists --force "${db}_restore" || true
    docker compose exec -T db rm -f /tmp/bangla-crm-restore.dump || true
    docker compose up -d
    fail "The database could not be restored (errors above). Your current data was NOT changed."
  fi
  docker compose exec -T db dropdb -U "$user" --if-exists --force "$db"
  docker compose exec -T db psql -U "$user" -d postgres -v ON_ERROR_STOP=1 -c "ALTER DATABASE \"${db}_restore\" RENAME TO \"$db\"" >/dev/null
  docker compose exec -T db rm -f /tmp/bangla-crm-restore.dump

  # The restored data is encrypted with the key from the backup's settings.
  if [ -f "$dir/env.txt" ]; then
    backup_key="$(file_get "$dir/env.txt" ENCRYPTION_KEY)"
    backup_fallback="$(file_get "$dir/env.txt" FALLBACK_ENCRYPTION_KEY)"
    if [ -n "$backup_key" ] && [ "$backup_key" != "$(env_get ENCRYPTION_KEY)" ]; then
      stamp="$(date +%Y-%m-%d_%H%M%S)"
      cp .env ".env.before-restore-$stamp"
      chmod 600 ".env.before-restore-$stamp"
      set_env ENCRYPTION_KEY "$backup_key"
      set_env FALLBACK_ENCRYPTION_KEY "$backup_fallback"
      say "Switched to the encryption key from the backup (previous settings saved in .env.before-restore-$stamp)."
    fi
  else
    warn "$dir/env.txt is missing: if this backup came from another installation, saved passwords and connected accounts will not work."
  fi

  if [ -d "$dir/files" ]; then
    say "Restoring uploaded files..."
    docker compose run --rm --no-deps --user root -v "$(cd "$dir/files" && pwd):/restore:ro" --entrypoint sh server \
      -c "rm -rf $STORAGE_PATH/* && cp -a /restore/. $STORAGE_PATH/ && chown -R 1000:1000 $STORAGE_PATH" ||
      warn "Uploaded files could not be restored (the database was restored)."
  fi

  start_all
  say "Restore finished."
}

latest_release() { # prints the newest published release number, or nothing
  local json
  json="$(curl -fsSL --max-time 20 "$RELEASES_API" 2>/dev/null || wget -qO- --timeout=20 "$RELEASES_API" 2>/dev/null || true)"
  printf '%s' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"bangla-v\([^"]*\)".*/\1/p' | head -n 1
}

cmd_update() {
  local new_version="" old_version pre_backup
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) [ $# -ge 2 ] || fail "--version needs a value"; new_version="$2"; shift 2 ;;
      *) fail "Unknown option: $1" ;;
    esac
  done
  old_version="$(env_get TAG latest)"
  if [ -z "$new_version" ]; then
    if [ "$old_version" = latest ]; then
      new_version=latest
    else
      say "Checking for a new version..."
      new_version="$(latest_release)"
      [ -n "$new_version" ] || fail "Could not check for new versions (no internet?). You can name one: bash bangla-crm.sh update --version 0.2.0"
      if [ "$new_version" = "$old_version" ]; then
        say "Bangla CRM is up to date (version $old_version)."
        return 0
      fi
    fi
  fi
  valid_version "$new_version" || fail "Version must look like 0.2.0."
  say "Updating Bangla CRM: $old_version -> $new_version"

  say "Making a backup before updating..."
  cmd_backup
  pre_backup="$BACKUP_DIR"

  set_env TAG "$new_version"
  if ! docker compose pull; then
    set_env TAG "$old_version"
    fail "Download failed. Nothing was changed; Bangla CRM keeps running version $old_version."
  fi
  if ( start_all ); then
    say "Bangla CRM is now running version $new_version. (Backup from before the update: $pre_backup)"
    return 0
  fi

  warn "The new version did not start. Going back to version $old_version and the backup made just before the update..."
  set_env TAG "$old_version"
  cmd_restore "$pre_backup" --yes
  fail "The update to $new_version failed, and Bangla CRM was put back to $old_version. Please contact support with: docker compose logs server"
}

cmd_finish_setup() {
  [ -n "$(env_get DOMAIN)" ] || fail "finish-setup is only for cloud installs."
  set_env SETUP_GATE off
  docker compose up -d caddy
  say "Done: https://$(env_get DOMAIN) is now open to everyone. Invite your team from Settings -> Members."
}

main() {
  local cmd="${1:-help}"
  if [ $# -gt 0 ]; then shift; fi
  case "$cmd" in
    start|stop|restart|status|logs|backup|update|restore|finish-setup)
      [ -f .env ] || fail "No .env file in this folder. Run the installer first:  bash install.sh"
      require_docker ;;
  esac
  case "$cmd" in
    start)   start_all; open_browser ;;
    stop)    docker compose stop; say "Bangla CRM is stopped. Your data is kept." ;;
    restart) docker compose stop; start_all; open_browser ;;
    status)  docker compose ps ;;
    logs)    docker compose logs -f --tail 200 server worker ;;
    open)    open_browser ;;
    backup)  cmd_backup "$@" ;;
    update)  cmd_update "$@" ;;
    restore) cmd_restore "$@" ;;
    finish-setup) cmd_finish_setup ;;
    help|-h|--help) sed -n '2,11p' "${BASH_SOURCE[0]##*/}" | sed 's/^# \{0,1\}//' ;;
    *) fail "Unknown command: $cmd  (try: bash bangla-crm.sh help)" ;;
  esac
}

# Run only when executed directly; install.sh sources this file to reuse the helpers.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
