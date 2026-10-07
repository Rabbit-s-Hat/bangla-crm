#!/usr/bin/env bash
# Put Bangla CRM on an Ubuntu cloud server (22.04 or 24.04, x86-64) with HTTPS.
#   sudo bash deploy-cloud.sh crm.example.com you@example.com [--version 0.1.0]
#
# Before running:
#   1. Create an x86-64 (Intel/AMD) server with at least 2 GB RAM (4 GB recommended) and 20 GB disk.
#   2. Point your domain's DNS "A" record to the server's public IP address.
#   3. Copy this whole folder to the server and run the command above inside it, over SSH.
# The script installs Docker (if missing), opens ports 80/443 in ufw (if active), offers a swap
# file and a nightly backup, then installs Bangla CRM in setup mode (only your IP can open it
# until you have signed up and run: sudo bash bangla-crm.sh finish-setup).
if [ -z "${BASH_VERSION:-}" ]; then echo "Please run this with bash:  sudo bash deploy-cloud.sh ..."; exit 1; fi
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
ask_yes() { # ask_yes "Question" -> 0 for yes (default yes)
  local answer
  printf '%s [Y/n] ' "$1"
  read -r answer || answer=""
  case "$answer" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

[ $# -ge 2 ] || { sed -n '2,11p' deploy-cloud.sh | sed 's/^# \{0,1\}//'; exit 1; }
DOMAIN="$1"; EMAIL="$2"; shift 2
EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --version) [ $# -ge 2 ] || fail "--version needs a value"; EXTRA+=(--version "$2"); shift 2 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || fail "Run this with sudo:  sudo bash deploy-cloud.sh $DOMAIN $EMAIL"
{ [ -f install.sh ] && [ -f docker-compose.cloud.yml ]; } || fail "Run this inside the complete Bangla CRM folder."
case "$(uname -m)" in
  x86_64|amd64) ;;
  *) fail "This server has an ARM processor ($(uname -m)). Bangla CRM needs an x86-64 (Intel/AMD) server." ;;
esac

# --- Docker ------------------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  OS_ID=""
  if [ -r /etc/os-release ]; then OS_ID="$(. /etc/os-release && printf '%s' "${ID:-}")"; fi
  if [ "$OS_ID" != "ubuntu" ]; then
    fail "Docker with Compose v2 is needed. On this system ($OS_ID) install it from https://docs.docker.com/engine/install/ and run this again."
  fi
  if command -v cloud-init >/dev/null 2>&1; then
    say "Waiting for the server's first-boot setup (cloud-init) to finish..."
    cloud-init status --wait >/dev/null 2>&1 || true
  fi
  say "Installing Docker from the Ubuntu repositories (waiting for Ubuntu's automatic updates if they are running)..."
  ok=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if apt-get -o DPkg::Lock::Timeout=600 update &&
       DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y docker.io docker-compose-v2; then
      ok=1; break
    fi
    say "apt is busy; trying again in 30 seconds..."
    sleep 30
  done
  [ "$ok" -eq 1 ] || fail "Could not install Docker with apt. Try again in a few minutes."
fi
systemctl enable --now docker >/dev/null 2>&1 || true

# --- DNS check ---------------------------------------------------------------------------------
RESOLVED="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR == 1 { print $1 }' || true)"
if [ -z "$RESOLVED" ]; then
  warn "$DOMAIN does not resolve yet. HTTPS will only work after its DNS A record points to this server."
  ask_yes "Continue anyway?" || exit 1
else
  say "DNS: $DOMAIN -> $RESOLVED (this must be this server's public IP address)."
fi

# --- Firewall ----------------------------------------------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  say "Opening ports 80 and 443 in the ufw firewall..."
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw allow 443/udp >/dev/null
fi
say "(If your cloud provider has its own firewall / security group, allow ports 80 and 443 there too.)"

# --- Swap on small servers ---------------------------------------------------------------------
MEM_MB="$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)"
SWAP_MB="$(awk '/^SwapTotal:/ { print int($2 / 1024) }' /proc/meminfo)"
if [ "$MEM_MB" -lt 3500 ] && [ "$SWAP_MB" -lt 1024 ] && [ ! -e /swapfile ]; then
  if ask_yes "This server has ${MEM_MB} MB RAM and no swap. Create a 2 GB swap file (recommended)?"; then
    if { fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none; } &&
       chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile; then
      grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    else
      warn "Could not enable swap on this server (often not allowed on container-based plans); continuing without it."
      swapoff /swapfile 2>/dev/null || true
      rm -f /swapfile
    fi
  fi
fi

# --- Nightly backup (asked now, so the last message you see is "Bangla CRM is running") ------
HERE="$(pwd)"
if [ ! -f /etc/cron.d/bangla-crm-backup ] && ask_yes "Make a backup every night at 02:30 (Bangladesh time) and keep the last 14 days?"; then
  # Convert 02:30 Asia/Dhaka to this server's clock (cloud servers usually run on UTC).
  read -r CRON_M CRON_H <<EOF
$(date -d 'TZ="Asia/Dhaka" 02:30' '+%-M %-H' 2>/dev/null || echo "30 20")
EOF
  mkdir -p "$HERE/backups"
  chmod 700 "$HERE/backups"
  cat > /etc/cron.d/bangla-crm-backup <<EOF
# Bangla CRM nightly backup at 02:30 Asia/Dhaka (created by deploy-cloud.sh)
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
$CRON_M $CRON_H * * * root cd "$HERE" && bash bangla-crm.sh backup --keep-days 14 >> "$HERE/backups/backup.log" 2>&1
EOF
  chmod 644 /etc/cron.d/bangla-crm-backup
  say "Nightly backups go to $HERE/backups. Copy them off this server regularly."
fi

# --- Install (setup mode: only the IP of this SSH session can open the site at first) ----------
ALLOW=()
OWNER_IP="${SSH_CLIENT:-}"
OWNER_IP="${OWNER_IP%% *}"
[ -n "$OWNER_IP" ] || OWNER_IP="$(who -m --ips 2>/dev/null | awk '{ print $NF }' | tr -d '()' || true)"
if [[ "$OWNER_IP" =~ ^[0-9A-Fa-f.:]+$ ]]; then ALLOW=(--allow-ip "$OWNER_IP"); fi
bash ./install.sh --domain "$DOMAIN" --email "$EMAIL" ${EXTRA[@]+"${EXTRA[@]}"} ${ALLOW[@]+"${ALLOW[@]}"}
