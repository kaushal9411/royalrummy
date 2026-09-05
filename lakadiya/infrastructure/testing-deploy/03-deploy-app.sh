#!/usr/bin/env bash
# Syncs lakadiya/ to the EC2 instance from 02-launch-ec2.sh and brings the
# whole stack up there: Postgres runs natively (matching local dev — this
# app has no docker-compose.yml), backend + admin run as plain Node
# processes managed by pm2. Re-run this any time you want to push local
# changes; it's idempotent (keeps the same DB/JWT secrets across re-deploys).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd ../.. && pwd)"   # -> lakadiya/

# shellcheck source=config.env
source ./config.env
# shellcheck source=credentials.txt
source ./credentials.txt

# DB_PASSWORD is optional in config.env — generate one on first deploy and
# persist it to credentials.txt so re-deploys reuse the same password
# instead of locking themselves out of the existing database.
if [ -z "${DB_PASSWORD:-}" ]; then
  if grep -q '^DB_PASSWORD=' ./credentials.txt 2>/dev/null; then
    DB_PASSWORD=$(grep '^DB_PASSWORD=' ./credentials.txt | cut -d= -f2-)
  else
    DB_PASSWORD=$(openssl rand -base64 18)
    echo "DB_PASSWORD=$DB_PASSWORD" >> ./credentials.txt
    echo "Generated DB_PASSWORD, saved to credentials.txt."
  fi
fi

SSH_KEY="./${KEY_NAME}.pem"
REMOTE="ubuntu@${PUBLIC_IP}"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new $REMOTE"

echo "Waiting for cloud-init (Postgres/Node/pm2 install) to finish on the instance..."
until $SSH 'test -f ~/cloud-init-done' 2>/dev/null; do sleep 5; done
echo "Cloud-init done."

echo "Syncing repo to ${REMOTE}:~/royalrummy/lakadiya ..."
rsync -az --delete \
  --exclude node_modules --exclude .git --exclude .next \
  --exclude 'backend/uploads' \
  --exclude '.env' --exclude '.env.local' --exclude '.env.*.local' \
  --exclude '.env.development' --exclude '.env.production' --exclude '.env.test' \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new" \
  "$REPO_ROOT/" "$REMOTE:~/royalrummy/lakadiya/"

echo "Running remote setup (this can take a few minutes — installs deps, builds the admin app)..."
$SSH bash -s -- "$TEST_DOMAIN" "$DB_NAME" "$DB_USER" "$DB_PASSWORD" <<'REMOTE_SCRIPT'
set -euo pipefail
TEST_DOMAIN="$1"; DB_NAME="$2"; DB_USER="$3"; DB_PASSWORD="$4"

cd ~/royalrummy/lakadiya
export PATH="$PATH:$(npm config get prefix)/bin"
export NODE_OPTIONS="--max-old-space-size=1536"

echo "-- ensuring Postgres role + database exist --"
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}'"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}"

echo "-- backend: npm install --"
cd ~/royalrummy/lakadiya/backend
npm install

if [ ! -f .env ]; then
  echo "-- generating backend/.env (fresh secrets — first deploy) --"
  {
    echo "NODE_ENV=development"
    echo "PORT=3001"
    echo "DB_HOST=localhost"
    echo "DB_PORT=5432"
    echo "DB_NAME=${DB_NAME}"
    echo "DB_USER=${DB_USER}"
    echo "DB_PASSWORD=${DB_PASSWORD}"
    node ../infrastructure/testing-deploy/gen-secrets.js | grep -v '^DB_PASSWORD='
    echo "JWT_EXPIRES_IN=7d"
    # Placeholders — fill in manually after deploy, real login/payment/OTP
    # flows won't work until you do:
    echo "GOOGLE_CLIENT_ID=your_google_client_id"
    echo "GOOGLE_CLIENT_SECRET=your_google_client_secret"
    echo "ALLOWED_ORIGINS=http://${TEST_DOMAIN}:3000,http://${TEST_DOMAIN}:3001"
    echo "RAZORPAY_KEY_ID=rzp_test_xxxxxxxxxxxxxxxx"
    echo "RAZORPAY_KEY_SECRET=your_razorpay_key_secret"
    echo "GMAIL_USER=your_gmail@gmail.com"
    echo "GMAIL_APP_PASSWORD=xxxx_xxxx_xxxx_xxxx"
    echo "FIREBASE_PROJECT_ID=your-firebase-project-id"
    echo "FIREBASE_CLIENT_EMAIL=your-firebase-client-email"
    echo "FIREBASE_PRIVATE_KEY=your-firebase-private-key"
  } > .env
else
  echo "-- backend/.env already exists — leaving secrets as-is, re-deploy keeps sessions valid --"
fi

echo "-- migrate + seed --"
npm run migrate
npm run seed || echo "(seed script reported an issue — check output above; safe to ignore if data already seeded)"

echo "-- admin: npm install + build --"
cd ~/royalrummy/lakadiya/admin
npm install
echo "NEXT_PUBLIC_API_URL=http://${TEST_DOMAIN}:3001" > .env.local
npm run build

echo "-- (re)starting via pm2 --"
APP_ROOT="$HOME/royalrummy/lakadiya"
pm2 delete lakadiya-backend lakadiya-admin >/dev/null 2>&1 || true
pm2 start "$APP_ROOT/backend/src/server.js" --name lakadiya-backend --cwd "$APP_ROOT/backend"
pm2 start npm --name lakadiya-admin --cwd "$APP_ROOT/admin" -- start
pm2 save
REMOTE_SCRIPT

echo ""
echo "== Deployed =="
echo "Backend API: http://${TEST_DOMAIN}:3001"
echo "Admin panel: http://${TEST_DOMAIN}:3000"
echo "SSH:         ssh -i ./${KEY_NAME}.pem ubuntu@${PUBLIC_IP}   (pm2 logs / pm2 status once inside)"
echo ""
echo "Remember: GOOGLE_CLIENT_ID/SECRET, RAZORPAY_*, GMAIL_*, FIREBASE_* in backend/.env are"
echo "placeholders — edit them on the server (then 'pm2 restart lakadiya-backend') before"
echo "relying on Google login, payments, email, or OTP push notifications."
