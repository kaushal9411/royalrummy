#!/usr/bin/env bash
# Free Let's Encrypt certs (via Certbot) for the 2 named hosts (api./admin.
# <domain>) — fully automatic, HTTP-01 challenge, auto-renewing. Requires
# BACKEND_HOSTNAME/ADMIN_HOSTNAME in config.env and 04-setup-domain.sh
# already run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# shellcheck source=config.env
source ./config.env
# shellcheck source=credentials.txt
source ./credentials.txt

if [ -z "${BACKEND_HOSTNAME:-}" ] || [ -z "${ADMIN_HOSTNAME:-}" ]; then
  echo "Set BACKEND_HOSTNAME / ADMIN_HOSTNAME in config.env first (run 04-setup-domain.sh first)." >&2
  exit 1
fi

export AWS_DEFAULT_REGION="$AWS_REGION"
SSH_KEY="./${KEY_NAME}.pem"
REMOTE="ubuntu@${PUBLIC_IP}"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new $REMOTE"

echo "Opening port 443 on the security group (idempotent)..."
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 >/dev/null 2>&1 \
  || echo "  (already open)"

echo "Requesting certs + switching apps to https..."
$SSH bash -s -- "$BACKEND_HOSTNAME" "$ADMIN_HOSTNAME" <<'REMOTE_SCRIPT'
set -euo pipefail
BACKEND_HOSTNAME="$1"; ADMIN_HOSTNAME="$2"
APP_ROOT="$HOME/royalrummy/lakadiya"
export PATH="$PATH:$(npm config get prefix)/bin"

if ! command -v certbot >/dev/null 2>&1; then
  echo "-- installing certbot --"
  sudo apt-get update -y
  sudo apt-get install -y certbot python3-certbot-nginx
fi

echo "-- requesting certs for the 2 named hosts (HTTP-01, auto-renewing via certbot.timer) --"
sudo certbot --nginx \
  -d "$BACKEND_HOSTNAME" -d "$ADMIN_HOSTNAME" \
  --non-interactive --agree-tos --redirect --register-unsafely-without-email

echo "-- switching apps to https:// --"
sed -i "s#^ALLOWED_ORIGINS=.*#ALLOWED_ORIGINS=https://${ADMIN_HOSTNAME},https://${BACKEND_HOSTNAME},http://${ADMIN_HOSTNAME},http://${BACKEND_HOSTNAME}#" "$APP_ROOT/backend/.env"
echo "NEXT_PUBLIC_API_URL=https://${BACKEND_HOSTNAME}" > "$APP_ROOT/admin/.env.local"

echo "-- rebuilding admin (NEXT_PUBLIC_* is build-time) --"
export NODE_OPTIONS="--max-old-space-size=1536"
cd "$APP_ROOT/admin"
npm run build

echo "-- restarting via pm2 --"
pm2 restart lakadiya-backend lakadiya-admin
pm2 save
REMOTE_SCRIPT

echo ""
echo "== SSL done =="
echo "Backend API: https://${BACKEND_HOSTNAME}"
echo "Admin panel: https://${ADMIN_HOSTNAME}"
echo "Certs auto-renew via certbot's systemd timer — nothing further needed."
