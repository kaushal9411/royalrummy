#!/usr/bin/env bash
# "Option A" — rsync-based redeploy. Pushes local code changes to the
# server WITHOUT touching domain/SSL config: syncs the repo (still
# excluding .env* — the server's real env/nginx config stays as-is),
# re-runs the DB migration (safe, idempotent — no-op if nothing changed),
# rebuilds the admin app, restarts both processes via pm2. Use this for
# every ordinary code change after the initial 03/04/05 setup — NOT
# 03-deploy-app.sh (which resets admin back to the sslip.io domain) or
# 04-setup-domain.sh (which rewrites nginx and would undo certbot's edits).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# shellcheck source=config.env
source ./config.env
# shellcheck source=credentials.txt
source ./credentials.txt

SSH_KEY="./${KEY_NAME}.pem"
REMOTE="ubuntu@${PUBLIC_IP}"
REPO_ROOT="$(cd ../.. && pwd)"

echo "Syncing repo to ${REMOTE}:~/royalrummy/lakadiya ..."
rsync -az --delete \
  --exclude node_modules --exclude .git --exclude .next \
  --exclude 'backend/uploads' \
  --exclude '.env' --exclude '.env.local' --exclude '.env.*.local' \
  --exclude '.env.development' --exclude '.env.production' --exclude '.env.test' \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new" \
  "$REPO_ROOT/" "$REMOTE:~/royalrummy/lakadiya/"

echo "Rebuilding + restarting on the server (env/nginx untouched)..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$REMOTE" bash -s <<'REMOTE_SCRIPT'
set -euo pipefail
export NODE_OPTIONS="--max-old-space-size=1536"

echo "-- backend: npm install --"
cd ~/royalrummy/lakadiya/backend
npm install

echo "-- migrate (no-op if nothing changed) --"
npm run migrate

echo "-- admin: npm install + build --"
cd ~/royalrummy/lakadiya/admin
npm install
npm run build

echo "-- restarting via pm2 --"
pm2 restart lakadiya-backend lakadiya-admin
pm2 save
REMOTE_SCRIPT

echo ""
echo "== Redeploy done (rsync) — domain/SSL config untouched =="
