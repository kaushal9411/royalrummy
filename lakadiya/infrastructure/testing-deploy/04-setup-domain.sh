#!/usr/bin/env bash
# Switches the deploy from the sslip.io address to real domains: installs
# nginx as a hostname-based reverse proxy (api./admin.<domain> -> ports
# 3001/3000, no more :PORT in URLs), points admin's env var at the new
# backend hostname, rebuilds the admin app (NEXT_PUBLIC_* is baked in at
# build time), and restarts everything. Requires BACKEND_HOSTNAME /
# ADMIN_HOSTNAME in config.env, and DNS A records already pointed at the
# Elastic IP in credentials.txt — this script doesn't touch DNS itself.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# shellcheck source=config.env
source ./config.env
# shellcheck source=credentials.txt
source ./credentials.txt

if [ -z "${BACKEND_HOSTNAME:-}" ] || [ -z "${ADMIN_HOSTNAME:-}" ]; then
  echo "Set BACKEND_HOSTNAME / ADMIN_HOSTNAME in config.env first." >&2
  exit 1
fi

export AWS_DEFAULT_REGION="$AWS_REGION"
SSH_KEY="./${KEY_NAME}.pem"
REMOTE="ubuntu@${PUBLIC_IP}"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new $REMOTE"

echo "Opening port 80 on the security group (idempotent)..."
aws ec2 authorize-security-group-ingress --group-id "$SECURITY_GROUP_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null 2>&1 \
  || echo "  (already open)"

echo "Quick DNS sanity check from this machine..."
for HOST in "$BACKEND_HOSTNAME" "$ADMIN_HOSTNAME"; do
  RESOLVED=$(getent hosts "$HOST" 2>/dev/null | awk '{print $1}' | head -1 || true)
  if [ "$RESOLVED" = "$PUBLIC_IP" ]; then
    echo "  $HOST -> $RESOLVED  OK"
  else
    echo "  $HOST -> ${RESOLVED:-<not resolving yet>}  (expected $PUBLIC_IP — DNS may still be propagating)"
  fi
done

echo "Configuring nginx + switching env vars on the server..."
$SSH bash -s -- "$BACKEND_HOSTNAME" "$ADMIN_HOSTNAME" <<'REMOTE_SCRIPT'
set -euo pipefail
BACKEND_HOSTNAME="$1"; ADMIN_HOSTNAME="$2"
APP_ROOT="$HOME/royalrummy/lakadiya"
export PATH="$PATH:$(npm config get prefix)/bin"

if ! command -v nginx >/dev/null 2>&1; then
  echo "-- installing nginx --"
  sudo apt-get update -y
  sudo apt-get install -y nginx
fi

echo "-- writing nginx config --"
sudo tee /etc/nginx/sites-available/lakadiya-test.conf > /dev/null <<NGINX
server {
    listen 80;
    server_name ${BACKEND_HOSTNAME};
    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
server {
    listen 80;
    server_name ${ADMIN_HOSTNAME};
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
sudo ln -sf /etc/nginx/sites-available/lakadiya-test.conf /etc/nginx/sites-enabled/lakadiya-test.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx || sudo systemctl restart nginx

echo "-- updating backend/.env ALLOWED_ORIGINS --"
sed -i "s#^ALLOWED_ORIGINS=.*#ALLOWED_ORIGINS=http://${ADMIN_HOSTNAME},http://${BACKEND_HOSTNAME}#" "$APP_ROOT/backend/.env"

echo "-- updating admin/.env.local --"
echo "NEXT_PUBLIC_API_URL=http://${BACKEND_HOSTNAME}" > "$APP_ROOT/admin/.env.local"

echo "-- rebuilding admin (NEXT_PUBLIC_* is build-time) --"
export NODE_OPTIONS="--max-old-space-size=1536"
cd "$APP_ROOT/admin"
npm run build

echo "-- restarting via pm2 --"
pm2 restart lakadiya-backend lakadiya-admin
pm2 save
REMOTE_SCRIPT

echo ""
echo "== Domain switch done =="
echo "Backend API: http://${BACKEND_HOSTNAME}"
echo "Admin panel: http://${ADMIN_HOSTNAME}"
echo "(If any hostname showed 'not resolving yet' above, give DNS a few more minutes and retry — everything else is already done.)"
