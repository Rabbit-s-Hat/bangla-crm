#!/usr/bin/env bash
# Bangla CRM installer for macOS and Linux.
#   bash install.sh                       this computer only, at http://localhost:3000
#   bash install.sh --port 3100           use another port
#   bash install.sh --lan                 also reachable from other computers on your network
#   bash install.sh --version 0.1.0       install a specific release (default: the one in .env)
#   bash install.sh --domain crm.example.com --email you@example.com [--allow-ip 203.0.113.7]
#                                         cloud server with HTTPS (deploy-cloud.sh runs this for you)
# Running it again is safe: secrets in an existing .env are never replaced.
if [ -z "${BASH_VERSION:-}" ]; then echo "Please run this with bash:  bash install.sh"; exit 1; fi
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=bangla-crm.sh
. ./bangla-crm.sh

VERSION=""; PORT=""; LAN=0; DOMAIN=""; EMAIL=""; ALLOW_IP=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version|--port|--domain|--email|--allow-ip)
      [ $# -ge 2 ] || fail "$1 needs a value"
      case "$1" in
        --version) VERSION="$2" ;;
        --port) PORT="$2" ;;
        --domain) DOMAIN="$2" ;;
        --email) EMAIL="$2" ;;
        --allow-ip) ALLOW_IP="$2" ;;
      esac
      shift 2 ;;
    --lan) LAN=1; shift ;;
    -h|--help) sed -n '2,9p' install.sh | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "Unknown option: $1  (see: bash install.sh --help)" ;;
  esac
done

if [ -n "$VERSION" ] && ! valid_version "$VERSION"; then fail "--version must look like 0.1.0."; fi
if [ -n "$PORT" ]; then
  if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then fail "--port must be a number from 1 to 65535."; fi
fi
if [ -n "$DOMAIN" ]; then
  [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]] ||
    fail "--domain must be a domain name such as crm.example.com (no http://)."
  [ -n "$EMAIL" ] || fail "--domain also needs --email (used for the free HTTPS certificate)."
fi
if [ -n "$EMAIL" ]; then
  [[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || fail "--email does not look like an email address."
fi
if [ -n "$ALLOW_IP" ] && ! [[ "$ALLOW_IP" =~ ^[0-9A-Fa-f.:/]+$ ]]; then fail "--allow-ip must be an IP address."; fi

port_in_use() { (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1; }

lan_ip() { # the address of the network card that carries the default route
  local ip=""
  if [ "$(uname)" = "Darwin" ]; then
    local ifc
    ifc="$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }' || true)"
    [ -n "$ifc" ] && ip="$(ipconfig getifaddr "$ifc" 2>/dev/null || true)"
  else
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }' || true)"
    [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{ print $1 }' || true)"
  fi
  printf '%s' "$ip"
}

operator_ip() { # the public address this SSH session comes from (for the cloud setup gate)
  local ip="${SSH_CLIENT:-}"
  ip="${ip%% *}"
  if [ -z "$ip" ]; then ip="$(who -m --ips 2>/dev/null | awk '{ print $NF }' | tr -d '()' || true)"; fi
  [[ "$ip" =~ ^[0-9A-Fa-f.:]+$ ]] || ip=""
  printf '%s' "$ip"
}

say "== Bangla CRM installer =="

# The image is built for x86-64. macOS (Docker Desktop) emulates it; Linux on ARM usually cannot.
if [ "$(uname)" != "Darwin" ]; then
  case "$(uname -m)" in
    x86_64|amd64) ;;
    *) [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ] ||
         fail "This computer has an ARM processor ($(uname -m)). Bangla CRM needs an x86-64 (Intel/AMD) computer or server." ;;
  esac
fi
require_docker

# --- .env: create once, never regenerate secrets -----------------------------------------------
if [ -f .env ]; then
  say "Keeping the existing .env (its secrets are never replaced)."
  NEW_ENV=0
else
  [ -f .env.example ] || fail ".env.example is missing. Download the complete Bangla CRM package again."
  if volume_exists db-data; then
    fail "Bangla CRM data already exists on this computer (from another Bangla CRM folder).
  Copy the .env file (and the backups folder) from your previous Bangla CRM folder into this folder,
  then run the installer again. You can also use env.txt from a backup, renamed to .env.
  To update, you do not need a new folder:  bash bangla-crm.sh update   in your existing folder."
  fi
  (umask 077; cp .env.example .env)
  NEW_ENV=1
fi
chmod 600 .env
[ -n "$(env_get PG_DATABASE_PASSWORD)" ] || set_env PG_DATABASE_PASSWORD "$(rand_hex)"
[ -n "$(env_get ENCRYPTION_KEY)" ] || set_env ENCRYPTION_KEY "$(rand_b64)"
if [ -n "$VERSION" ]; then set_env TAG "$VERSION"; fi

if [ -z "$DOMAIN" ] && [ -n "$(env_get DOMAIN)" ]; then
  # Re-run on an existing cloud install: keep it a cloud install.
  [ "$LAN" -eq 0 ] || fail "This is a cloud install (https://$(env_get DOMAIN)); --lan is only for computers in an office."
  if [ -n "$PORT" ]; then set_env HTTP_PORT "$PORT"; fi
elif [ -n "$DOMAIN" ]; then
  [ "$LAN" -eq 0 ] || fail "--lan is for local installs; a cloud install is reachable at https://$DOMAIN."
  FIRST_CLOUD=0
  [ "$(env_get DOMAIN)" = "$DOMAIN" ] || FIRST_CLOUD=1
  set_env DOMAIN "$DOMAIN"
  set_env ACME_EMAIL "$EMAIL"
  set_env COMPOSE_FILE "docker-compose.yml:docker-compose.cloud.yml"
  set_env SERVER_URL "https://$DOMAIN"
  set_env BIND_ADDRESS 127.0.0.1
  if [ -n "$PORT" ]; then set_env HTTP_PORT "$PORT"; fi
  if [ "$NEW_ENV" -eq 1 ] || [ "$FIRST_CLOUD" -eq 1 ]; then
    # Until the owner has signed up (and become administrator), only the owner's IP may open the site.
    [ -n "$ALLOW_IP" ] || ALLOW_IP="$(operator_ip)"
    if [ -n "$ALLOW_IP" ]; then
      set_env SETUP_GATE on
      set_env SETUP_ALLOW_IP "$ALLOW_IP"
    else
      set_env SETUP_GATE off
      warn "Could not detect your IP address, so the site is open to everyone right away: SIGN UP IMMEDIATELY."
    fi
  fi
elif [ "$NEW_ENV" -eq 1 ] || [ -n "$PORT" ] || [ "$LAN" -eq 1 ]; then
  PORT="${PORT:-$(env_get HTTP_PORT 3000)}"
  set_env HTTP_PORT "$PORT"
  if [ "$LAN" -eq 1 ]; then
    IP="$(lan_ip)"
    set_env BIND_ADDRESS 0.0.0.0
    if [ -n "$IP" ]; then
      set_env SERVER_URL "http://$IP:$PORT"
      say "Other computers can open: http://$IP:$PORT  (ask your network admin to reserve this IP address for this computer)."
    else
      warn "Could not find this computer's network address; links in emails will use localhost."
      set_env SERVER_URL "http://localhost:$PORT"
    fi
    if [ "$(uname)" != "Darwin" ]; then warn "Docker-published ports bypass the ufw firewall on Linux."; fi
  else
    set_env BIND_ADDRESS 127.0.0.1
    set_env SERVER_URL "http://localhost:$PORT"
  fi
fi

# --- Ports ----------------------------------------------------------------------------------
if ! is_running server; then
  p="$(env_get HTTP_PORT 3000)"
  if port_in_use "$p"; then
    if [ -n "$(env_get DOMAIN)" ]; then
      fail "Port $p is already used by another program on this server. Run again with another port, e.g.: sudo bash install.sh --port 3100"
    fi
    fail "Port $p is already used by another program. Run again with another port, e.g.: bash install.sh --port 3100"
  fi
fi
if [ -n "$(env_get DOMAIN)" ] && ! is_running caddy; then
  for p in 80 443; do
    if port_in_use "$p"; then fail "Port $p is already used by another program (a web server?). Stop it first."; fi
  done
fi

# --- Download and start -----------------------------------------------------------------------
say "Downloading Bangla CRM $(env_get TAG latest). The first download is about 1 GB and can take a while..."
if ! docker compose pull; then
  fail "Download failed. Check the internet connection. If the message says 'denied' or 'not found', version '$(env_get TAG latest)' is not published."
fi
start_all

say ""
if [ -n "$(env_get DOMAIN)" ]; then
  say "Bangla CRM is running at: $(env_get SERVER_URL)"
  say "(The HTTPS certificate is requested on the first visit. If that fails, check that $(env_get DOMAIN) points to this server and ports 80/443 are open.)"
  if [ "$(env_get SETUP_GATE off)" = on ]; then
    say ""
    say "SETUP MODE: for now only your own IP address ($(env_get SETUP_ALLOW_IP)) can open the site."
    say "  1. Open $(env_get SERVER_URL) now and sign up: the FIRST account becomes the administrator."
    say "  2. Then open the site to your team:   sudo bash bangla-crm.sh finish-setup"
  fi
else
  open_browser
  say ""
  say "Next steps:"
  say "  1. Open the address above and sign up. The FIRST account becomes the administrator."
fi
say "  Everyday commands:  bash bangla-crm.sh start | stop | backup | update | logs"
say "  Make regular backups (bash bangla-crm.sh backup) and keep .env safe - it holds your encryption key."
